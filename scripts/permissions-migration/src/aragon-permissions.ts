import { id, JsonRpcProvider } from "ethers";

import md from "./markdown";
import bytes, { Address, HexStrPrefixed } from "./bytes";
import {
  decodeAddress,
  decodeBool,
  decodeBytes32,
  makeContractCall,
  sortLogs,
} from "./utils";

import {
  CONTRACT_LABELS,
  LIDO_CONTRACTS,
  LIDO_CONTRACTS_NAMES,
  LIDO_GENESIS_BLOCK,
  LidoContractName,
} from "../config/lido-contracts";

export interface AragonPermissionConfig {
  manager: LidoContractName;
  grantedTo?: LidoContractName[];
}

export interface AragonContractPermissionConfig {
  address: Address;
  permissions: Record<string, AragonPermissionConfig>;
}

export type AragonContractPermissionConfigs = Record<
  string,
  AragonContractPermissionConfig
>;

interface AragonPermissionInfo {
  name: string;
  isModified: boolean;
  oldManager: LidoContractName;
  newManager: LidoContractName;
  holdersToGrantRole: LidoContractName[];
  holdersToRevokeRole: LidoContractName[];
  holderAlreadyGrantedWithRole: LidoContractName[];
}

interface AragonPermissionsInfo {
  [contractName: string]: AragonPermissionInfo[];
}

interface AragonPermissionHolders {
  managers: {
    [app: Address]: {
      [role: HexStrPrefixed]: Address;
    };
  };
  permissions: {
    [app: Address]: {
      [role: HexStrPrefixed]: Address[];
    };
  };
}

function formatContractPermissionsSection(
  aragonContractsInfo: AragonPermissionsInfo
) {
  const resSectionLines: string[] = ["### Aragon Roles Transition \n"];

  let totalModifiedRoles = 0;

  for (const [contractName, roles] of Object.entries(aragonContractsInfo)) {
    if (roles.length === 0) continue;
    resSectionLines.push(`#### ${contractName}\n`);
    const [modifiedRolesCount, rowsText] = formatPermissionsInfoTable(roles);
    resSectionLines.push(rowsText);
    resSectionLines.push("\n");
    totalModifiedRoles += modifiedRolesCount;
  }

  resSectionLines.push(`\n **Total Roles Modified: ${totalModifiedRoles}** \n`);

  return resSectionLines.join("\n");
}

function formatPermissionsInfoTable(aragonRolesInfo: AragonPermissionInfo[]) {
  const columnHeaders = ["Role", "Manager", "Revoked", "Granted"];
  const rows: string[][] = [];

  let modifiedRolesCount = 0;

  for (const role of aragonRolesInfo.sort(
    (a, b) => Number(!a.isModified) - Number(!b.isModified)
  )) {
    if (role.isModified) {
      modifiedRolesCount += 1;
    }

    const oldManagerLabel = md.label(
      role.oldManager === "None" ? md.empty() : role.oldManager
    );
    const newManagerLabel = md.label(
      role.newManager === "None" ? md.empty() : role.newManager
    );

    const managerTransition =
      role.oldManager != role.newManager
        ? md.bold(`${oldManagerLabel} -> ${newManagerLabel}`)
        : md.label(oldManagerLabel);

    const unknownRoleHolders = role.holdersToRevokeRole.filter((holderName) =>
      holderName.startsWith("Unknown")
    );
    const knownRoleHolders = role.holdersToRevokeRole.filter(
      (holderName) => !holderName.startsWith("Unknown")
    );

    const revokedFromItems =
      role.holdersToRevokeRole.length === 0
        ? [md.empty()]
        : knownRoleHolders.map((roleHolder) =>
            md.bold(md.label(CONTRACT_LABELS[roleHolder] ?? roleHolder))
          );

    if (unknownRoleHolders.length > 0) {
      revokedFromItems.push(
        md.label(`+${unknownRoleHolders.length} UNKNOWN holders`)
      );
    }

    const grantedToItems: string[] = [
      ...role.holderAlreadyGrantedWithRole.map((roleHolder) =>
        md.label(CONTRACT_LABELS[roleHolder] ?? roleHolder)
      ),
      ...role.holdersToGrantRole.map((roleHolder) =>
        md.bold(CONTRACT_LABELS[roleHolder] ?? md.label(roleHolder))
      ),
    ];

    if (grantedToItems.length === 0) {
      grantedToItems.push(md.empty());
    }

    const roleNameText = role.isModified
      ? md.modified(role.name)
      : md.unchanged(role.name);

    rows.push([
      roleNameText,
      managerTransition,
      revokedFromItems.join(", "),
      grantedToItems.join(", "),
    ]);
  }
  return [
    modifiedRolesCount,
    [md.header(columnHeaders), ...rows.map((row) => md.row(row))].join("\n"),
  ] as const;
}

async function collectPermissionsData(
  provider: JsonRpcProvider,
  config: AragonContractPermissionConfigs
) {
  const { managers, permissions } = await fetchACLPermissionsInfo(provider);
  const aragonContractsInfo: AragonPermissionsInfo = {};

  for (const [contractName, contractInfo] of Object.entries(config)) {
    const address = bytes.normalize(contractInfo.address);
    aragonContractsInfo[contractName] = [];

    for (const [permissionName, { manager, grantedTo }] of Object.entries(
      contractInfo.permissions
    )) {
      const permissionHash = await getPermissionHash(
        provider,
        address,
        permissionName
      );

      const newManager = manager;
      const oldManagerAddress = managers[address]?.[permissionHash];
      const oldManager = oldManagerAddress
        ? LIDO_CONTRACTS_NAMES[oldManagerAddress]
        : "None";

      const currentlyGrantedTo = (
        permissions[address]?.[permissionHash] ?? []
      ).map((roleHolderAddress) => {
        return LIDO_CONTRACTS_NAMES[roleHolderAddress] === undefined
          ? (`Unknown(${roleHolderAddress})` as LidoContractName)
          : LIDO_CONTRACTS_NAMES[roleHolderAddress];
      });

      const holdersToGrantRole = (grantedTo ?? []).filter(
        (roleHolder) => !currentlyGrantedTo.includes(roleHolder)
      );
      const holdersToRevokeRole = currentlyGrantedTo.filter(
        (roleHolderName) => !(grantedTo ?? []).includes(roleHolderName)
      );
      const holderAlreadyGrantedWithRole = (grantedTo ?? []).filter(
        (roleHolder) => currentlyGrantedTo.includes(roleHolder)
      );

      aragonContractsInfo[contractName].push({
        name: permissionName,
        oldManager,
        newManager,
        isModified:
          newManager !== oldManager ||
          holdersToGrantRole.length > 0 ||
          holdersToRevokeRole.length > 0,
        holdersToGrantRole,
        holdersToRevokeRole,
        holderAlreadyGrantedWithRole,
      });
    }
  }
  return aragonContractsInfo;
}

async function fetchACLPermissionsInfo(provider: JsonRpcProvider) {
  const aclPermissionsEvents = await getACLPermissionEvents(provider, {
    fromBlock: LIDO_GENESIS_BLOCK,
  });

  const result: AragonPermissionHolders = {
    managers: {},
    permissions: {},
  };

  for (const event of aclPermissionsEvents) {
    if (event.name === "ChangePermissionManager") {
      const { app, role, manager } = event.args;
      if (!result.managers[app]) {
        result.managers[app] = {};
      }
      result.managers[app][role] = manager!;
    } else if (event.name === "SetPermission") {
      const { entity, app, role, allowed } = event.args;

      if (!result.permissions[app]) {
        result.permissions[app] = {};
      }

      if (!result.permissions[app][role]) {
        result.permissions[app][role] = [];
      }

      if (allowed && !result.permissions[app][role].includes(entity!)) {
        if (result.permissions[app][role].includes(entity!)) {
        }
        result.permissions[app][role].push(entity!);
      } else {
        if (!result.permissions[app][role].includes(entity!)) {
        }
        result.permissions[app][role] = result.permissions[app][role].filter(
          (e) => e !== entity
        );
      }
    }
    // TODO: Check that SetPermissionParams events doesn't impact the granted permissions
  }

  return result;
}

async function getACLPermissionEvents(
  provider: JsonRpcProvider,
  filterRange?: { fromBlock: number; toBlock?: number }
) {
  const setPermissionTopic = id("SetPermission(address,address,bytes32,bool)");
  const setPermissionParamsTopic = id(
    "SetPermissionParams(address,address,bytes32,bytes32)"
  );
  const changePermissionManagerTopic = id(
    "ChangePermissionManager(address,bytes32,address)"
  );

  const filterParams = {
    address: LIDO_CONTRACTS.ACL,
    fromBlock: filterRange?.fromBlock,
    toBlock: filterRange?.toBlock,
  };
  const [
    setPermissionLogs,
    setPermissionParamsLogs,
    changePermissionManagerLogs,
  ] = await Promise.all([
    provider.getLogs({ ...filterParams, topics: [setPermissionTopic] }),
    provider.getLogs({ ...filterParams, topics: [setPermissionParamsTopic] }),
    provider.getLogs({
      ...filterParams,
      topics: [changePermissionManagerTopic],
    }),
  ]);
  return sortLogs([
    ...setPermissionLogs,
    ...setPermissionParamsLogs,
    ...changePermissionManagerLogs,
  ]).map((log) => {
    const commonEventInfo = {
      blockNumber: log.blockNumber,
      index: log.index,
      transactionIndex: log.transactionIndex,
    };
    if (log.topics[0] === setPermissionTopic) {
      return {
        ...commonEventInfo,
        name: "SetPermission",
        args: {
          entity: decodeAddress(log.topics[1]),
          app: decodeAddress(log.topics[2]),
          role: decodeBytes32(log.topics[3]),
          allowed: decodeBool(log.data),
        },
      } as const;
    } else if (log.topics[0] === setPermissionParamsTopic) {
      return {
        ...commonEventInfo,
        name: "SetPermissionParams",
        args: {
          entity: decodeAddress(log.topics[1]),
          app: decodeAddress(log.topics[2]),
          role: decodeBytes32(log.topics[3]),
          paramsHash: decodeBytes32(log.data),
        } as const,
      };
    } else if (log.topics[0] === changePermissionManagerTopic) {
      return {
        ...commonEventInfo,
        name: "ChangePermissionManager",
        args: {
          app: decodeAddress(log.topics[1]),
          role: decodeBytes32(log.topics[2]),
          manager: decodeAddress(log.topics[3]),
        } as const,
      };
    } else {
      throw new Error(`Unexpected event topic ${log.topics[0]}`);
    }
  });
}

async function getPermissionHash(
  provider: JsonRpcProvider,
  address: Address,
  permissionName: string
) {
  return makeContractCall(provider, address, permissionName);
}

export default {
  formatContractPermissionsSection,
  collectPermissionsData,
};
