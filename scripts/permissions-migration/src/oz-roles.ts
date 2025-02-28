import { AbiCoder, ethers, id, JsonRpcProvider } from "ethers";

import md from "./markdown";
import { makeContractCall, sortLogs } from "./utils";
import bytes, { Address, HexStrPrefixed } from "./bytes";

import {
  LidoContractName,
  LIDO_CONTRACTS_NAMES,
  LIDO_GENESIS_BLOCK,
  CONTRACT_LABELS,
} from "../config/lido-contracts";

export type OZContractRolesConfig = Record<string, OZContractConfig>;

interface OZContractConfig {
  address: Address;
  roles: Record<string, LidoContractName[]>;
}

interface OZRoleInfo {
  roleName: string;
  isModified: boolean;
  holdersToGrantRole: LidoContractName[];
  holdersToRevokeRole: LidoContractName[];
  holderAlreadyGrantedWithRole: LidoContractName[];
}

interface OZRolesInfo {
  [contractName: string]: OZRoleInfo[];
}

interface OZRoleHolders {
  [contract: Address]: {
    [role: HexStrPrefixed]: Address[];
  };
}

const DEFAULT_ADMIN_ROLE_HASH = ethers.ZeroHash;

function formatContractRolesSection(ozContractsInfo: OZRolesInfo) {
  const resSectionLines: string[] = ["### OpenZeppelin Roles Transition \n"];

  let totalModifiedRoles = 0;

  for (const [contractName, roles] of Object.entries(ozContractsInfo)) {
    if (roles.length === 0) continue;
    resSectionLines.push(`#### ${contractName}\n`);
    const [modifiedRolesCount, rowsText] = formatRolesInfoTable(roles);
    resSectionLines.push(rowsText);
    resSectionLines.push("\n");
    totalModifiedRoles += modifiedRolesCount;
  }

  resSectionLines.push(`\n **Total Roles Modified: ${totalModifiedRoles}** \n`);

  return resSectionLines.join("\n");
}

async function collectRolesInfo(
  provider: JsonRpcProvider,
  config: Record<string, OZContractConfig>
) {
  const ozRolesInfo: OZRolesInfo = {};

  const ozRolesHolders = await fetchRoleHolders(provider, config);

  for (const [contractName, { address, roles }] of Object.entries(config)) {
    ozRolesInfo[contractName] = [];

    for (const [roleName, desiredRoleGrantees] of Object.entries(roles)) {
      const roleHash = await getRoleHash(provider, address, roleName);

      const currentlyGrantedTo = (ozRolesHolders[address][roleHash] || []).map(
        (roleHolderAddress) => {
          if (LIDO_CONTRACTS_NAMES[roleHolderAddress] === undefined) {
            return "Unknown";
          }
          return LIDO_CONTRACTS_NAMES[roleHolderAddress];
        }
      ) as LidoContractName[];

      const holdersToGrantRole = desiredRoleGrantees.filter(
        (roleHolder) => !currentlyGrantedTo.includes(roleHolder)
      );
      const holdersToRevokeRole = currentlyGrantedTo.filter(
        (roleHolderName) => !desiredRoleGrantees.includes(roleHolderName)
      );
      const holderAlreadyGrantedWithRole = desiredRoleGrantees.filter(
        (roleHolder) => currentlyGrantedTo.includes(roleHolder)
      );

      const holdersToRevokeWithoutUnknown = holdersToRevokeRole.filter(
        (roleHolder) => !roleHolder.startsWith("Unknown")
      );

      ozRolesInfo[contractName].push({
        roleName,
        holdersToGrantRole,
        holdersToRevokeRole,
        holderAlreadyGrantedWithRole,
        isModified:
          holdersToGrantRole.length > 0 || holdersToRevokeWithoutUnknown.length > 0,
      });
    }
  }
  return ozRolesInfo;
}

function formatRolesInfoTable(ozRolesInfo: OZRoleInfo[]) {
  const columnHeaders = ["Role", "Revoked", "Granted"];
  const rows: string[][] = [];

  let modifiedRolesCount = 0;

  for (const role of ozRolesInfo.sort(
    (a, b) => Number(!a.isModified) - Number(!b.isModified)
  )) {
    if (role.isModified) {
      modifiedRolesCount += 1;
    }

    const unknownRoleHolders = role.holdersToRevokeRole.filter((holderName) =>
      holderName.startsWith("Unknown")
    );

    const revokedFromItems =
      role.holdersToRevokeRole.length === 0
        ? [md.empty()]
        : role.holdersToRevokeRole.map((roleHolder) => {
            if (roleHolder.startsWith("Unknown")) {
              return false;
            }
            return md.bold(md.label(CONTRACT_LABELS[roleHolder] ?? roleHolder))
          }).filter(Boolean);

    if (unknownRoleHolders.length > 0){
      revokedFromItems.push(md.label(`+${unknownRoleHolders.length} ${md.bold("UNKNOWN")} holders`));
    }

    const grantedToItems: string[] = [
      ...role.holderAlreadyGrantedWithRole.map((roleHolder) =>
        md.label(CONTRACT_LABELS[roleHolder] ?? roleHolder)
      ),
      ...role.holdersToGrantRole.map((roleHolder) =>
        md.bold(md.label(CONTRACT_LABELS[roleHolder] ?? roleHolder))
      ),
    ];

    if (grantedToItems.length === 0) {
      grantedToItems.push(md.empty());
    }

    const roleNameText = role.isModified
      ? md.modified(role.roleName)
      : md.unchanged(role.roleName);

    rows.push([
      roleNameText,
      revokedFromItems.join(", "),
      grantedToItems.join(", "),
    ]);
  }
  return [
    modifiedRolesCount,
    [md.header(columnHeaders), ...rows.map((row) => md.row(row))].join("\n"),
  ] as const;
}

async function fetchRoleHolders(
  provider: JsonRpcProvider,
  config: Record<string, OZContractConfig>
) {
  const ozRolesHolders: OZRoleHolders = {};

  for (const { address: ozContractAddress } of Object.values(config)) {
    ozRolesHolders[ozContractAddress] = {};

    const roleGrantedRevokedEvents = await getRoleGrantedRevokedEvents(
      provider,
      ozContractAddress,
      {
        fromBlock: LIDO_GENESIS_BLOCK,
      }
    );

    for (const event of roleGrantedRevokedEvents) {
      const role = bytes.normalize(event.args.role);
      const account = bytes.normalize(event.args.account);
      if (!ozRolesHolders[ozContractAddress][role]) {
        ozRolesHolders[ozContractAddress][role] = [];
      }

      if (event.eventName === "RoleGranted") {
        ozRolesHolders[ozContractAddress][role].push(account);
      } else if (event.eventName === "RoleRevoked") {
        ozRolesHolders[ozContractAddress][role] = ozRolesHolders[
          ozContractAddress
        ][role].filter((roleHolder) => roleHolder !== account);
      } else {
        throw Error(`Unknown event name ${event.eventName}`);
      }
    }
  }

  return ozRolesHolders;
}

async function checkRoleAdmins(
  provider: JsonRpcProvider,
  config: Record<string, OZContractConfig>
) {
  for (const [contractName, { address, roles }] of Object.entries(config)) {
    const roleNames = Object.keys(roles);

    const roleHashesAndAdmins = await Promise.all(
      roleNames.map(async (roleName) => {
        const roleHash = await getRoleHash(provider, address, roleName);
        return [
          roleHash,
          await getRoleAdminHash(provider, address, roleHash),
        ] as [roleHash: string, roleAdmin: string];
      })
    );

    console.log(`Checking role admins for "${contractName}":`);
    for (let i = 0; i < roleNames.length; ++i) {
      const [roleHash, roleAdminHash] = roleHashesAndAdmins[i];
      console.log(`  - ${roleNames[i]}(${roleHash}): ${roleAdminHash}`);
      if (bytes.normalize(roleAdminHash) !== DEFAULT_ADMIN_ROLE_HASH) {
        throw new Error(`🚨 Unexpected Role Admin`);
      }
    }
    console.log();

    // Protection from the  API requests per second limit
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
}

async function getRoleAdminHash(
  provider: JsonRpcProvider,
  address: Address,
  roleHash: string
) {
  return makeContractCall(
    provider,
    address,
    "getRoleAdmin",
    ["bytes32"],
    [roleHash]
  );
}

async function getRoleHash(
  provider: JsonRpcProvider,
  address: Address,
  roleName: string
) {
  return makeContractCall(provider, address, roleName);
}

async function getRoleGrantedRevokedEvents(
  provider: JsonRpcProvider,
  contract: Address,
  filterRange?: { fromBlock: number; toBlock?: number }
) {
  const roleGrantedTopic = id("RoleGranted(bytes32,address,address)");
  const roleRevokedTopic = id("RoleRevoked(bytes32,address,address)");
  const filterParams = {
    address: contract,
    fromBlock: filterRange?.fromBlock,
    toBlock: filterRange?.toBlock,
  };
  const [grantRoleLogs, revokeRoleLogs] = await Promise.all([
    provider.getLogs({ ...filterParams, topics: [roleGrantedTopic] }),
    provider.getLogs({ ...filterParams, topics: [roleRevokedTopic] }),
  ]);
  return sortLogs([...grantRoleLogs, ...revokeRoleLogs]).map((log) => {
    if (log.topics.length !== 4) {
      throw new Error("Unexpected topics length");
    }
    return {
      eventName:
        log.topics[0] === roleGrantedTopic ? "RoleGranted" : "RoleRevoked",
      blockNumber: log.blockNumber,
      index: log.index,
      transactionIndex: log.transactionIndex,
      args: {
        role: log.topics[1],
        account: AbiCoder.defaultAbiCoder().decode(
          ["address"],
          log.topics[2]
        )[0] as HexStrPrefixed,
        sender: AbiCoder.defaultAbiCoder().decode(
          ["address"],
          log.topics[3]
        )[0] as HexStrPrefixed,
      },
    };
  });
}

export default {
  collectRolesInfo,
  formatContractRolesSection,
  checkRoleAdmins,
};
