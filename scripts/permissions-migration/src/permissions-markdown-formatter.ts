import { HexStrPrefixed, Address } from "./bytes";
import { AragonPermissionsSnapshot, OZPermissionsSnapshot } from "./roles-reducer";
import { PermissionsLayout } from "./permissions-config";
import { decodeAddress, makeContractCall, ZERO_HASH } from "./utils";

interface AccountInfo {
  label: string;
  address: Address | null;
}

interface PermissionsSnapshot {
  snapshotBlockNumber: number;
  aragon: AragonPermissionsSnapshot;
  oz: OZPermissionsSnapshot;
}

interface OZContractsPermissions {
  contractLabel: string;
  rolesData: OZRoleTableData[];
}

interface AragonContractsPermissions {
  contractLabel: string;
  permissionsData: AragonPermissionTableData[];
}

interface OZRoleTableData {
  name: string;
  hash: HexStrPrefixed;
  isModified: boolean;
  adminRole: HexStrPrefixed;
  currentRoleHolders: AccountInfo[];
  holdersToGrantRole: AccountInfo[];
  holdersToRevokeRole: AccountInfo[];
}

interface AragonPermissionTableData {
  name: string;
  hash: HexStrPrefixed;
  isModified: boolean;
  newManager: AccountInfo;
  currentManager: AccountInfo;
  currentRoleHolders: AccountInfo[];
  holdersToGrantRole: AccountInfo[];
  holdersToRevokeRole: AccountInfo[];
}

interface OwnershipSectionData {
  address: Address;
  isModified: boolean;
  contractLabel: string;
  propertyGetter: string;
  oldManagedBy: AccountInfo;
  newManagedBy: AccountInfo;
}

export class PermissionsMarkdownFormatter {
  #roleHashesMap: Record<string, HexStrPrefixed> = {};
  #rpcURL: string;
  #config: PermissionsLayout;
  #snapshot: PermissionsSnapshot;

  #ozContractTableColumns: string[] = ["Role", "Role Admin", "Revoked", "Granted"];
  #aragonContractTableColumns: string[] = ["Role", "Role Manager", "Revoked", "Granted"];
  #contractsOwnershipTableColumns: string[] = ["Contract", "Property", "Old Owner", "New Owner"];

  constructor(rpcURL: string, config: PermissionsLayout, snapshot: PermissionsSnapshot) {
    this.#rpcURL = rpcURL;
    this.#config = config;
    this.#snapshot = snapshot;
  }

  async format() {
    const result: string[] = ["## Lido Permissions Transition\n"];
    const contractTablesData = await this.#buildContractTablesData();

    const [aragonContractTables, aragonPermissionMigrationSteps, ozRolesMigrationSteps, ozContractTables] =
      await Promise.all([
        this.#formatAragonContractTables(contractTablesData.aragon),
        this.#formatAragonPermissionMigrationSteps(contractTablesData.aragon),
        this.#formatOZRolesMigrationSteps(contractTablesData.oz),
        this.#formatOZContractTables(contractTablesData.oz),
      ]);

    let migrationNumber = 1;
    result.push("### Aragon Permissions");
    for (let i = 0; i < contractTablesData.aragon.length; ++i) {
      result.push(this.#formatContractHeader(contractTablesData.aragon[i].contractLabel));
      result.push(aragonContractTables[i]);
      result.push("");
      if (aragonPermissionMigrationSteps[i].length > 0) {
        result.push("##### Migration Steps\n");
        result.push("```");
        for (let migrationStep of aragonPermissionMigrationSteps[i]) {
          result.push(`${migrationNumber++}. ${migrationStep}`);
        }
        result.push("```\n");
      }
    }

    result.push("### OZ Roles");
    for (let i = 0; i < contractTablesData.oz.length; ++i) {
      result.push(this.#formatContractHeader(contractTablesData.oz[i].contractLabel));
      result.push(ozContractTables[i]);
      result.push("");
      if (ozRolesMigrationSteps[i].length > 0) {
        result.push("##### Migration Steps\n");
        result.push("```");
        for (let migrationStep of ozRolesMigrationSteps[i]) {
          result.push(`${migrationNumber++}. ${migrationStep}`);
        }
        result.push("```\n");
      }
    }

    result.push("### Contracts Ownership");
    result.push(this.#formatContractsOwnershipTable(contractTablesData.ownership));
    result.push("```");
    result.push(
      this.#formatContractsOwnershipMigrationSteps(contractTablesData.ownership)
        .map((migrationStep) => `${migrationNumber++}. ${migrationStep}`)
        .join("\n")
    );
    result.push("```");

    return result.join("\n");
  }

  async #buildContractTablesData() {
    const result: {
      oz: OZContractsPermissions[];
      aragon: AragonContractsPermissions[];
      ownership: OwnershipSectionData[];
    } = {
      oz: [],
      aragon: [],
      ownership: [],
    };

    const ozContractLabels = Object.keys(this.#config.getOZConfig());

    for (const ozContractLabel of ozContractLabels) {
      result.oz.push({
        contractLabel: ozContractLabel,
        rolesData: Object.values(await this.#buildOZSectionData(ozContractLabel)),
      });
    }

    result.oz.sort((a, b) => {
      const isAModified = a.rolesData.some((roleData) => roleData.isModified);
      const isBModified = b.rolesData.some((roleData) => roleData.isModified);
      if (isAModified && !isBModified) return -1;
      if (!isAModified && isBModified) return 1;
      return 0;
    });

    const aragonContractLabels = Object.keys(this.#config.getAragonConfig());
    for (const aragonContractLabel of aragonContractLabels) {
      result.aragon.push({
        contractLabel: aragonContractLabel,
        permissionsData: Object.values(await this.#buildAragonSectionData(aragonContractLabel)),
      });
    }

    result.aragon.sort((a, b) => {
      const isAModified = a.permissionsData.some((aRoleData) => aRoleData.isModified);
      const isBModified = b.permissionsData.some((bRoleDAta) => bRoleDAta.isModified);
      if (isAModified && !isBModified) return -1;
      if (!isAModified && isBModified) return 1;

      const isAAgentOrACL = a.contractLabel === "ACL" || a.contractLabel === "Agent";
      const isBAgentOrACL = b.contractLabel === "ACL" || b.contractLabel === "Agent";

      if (isAAgentOrACL && !isBAgentOrACL) {
        return 1;
      }
      if (isBAgentOrACL && !isAAgentOrACL) {
        return -1;
      }
      return 0;
    });

    for (const ownershipContractLabel of Object.keys(this.#config.getOwnershipConfig())) {
      result.ownership.push(await this.#buildOwnershipSectionData(ownershipContractLabel));
    }

    result.ownership.sort((a, b) => {
      if (a.isModified && !b.isModified) {
        return -1;
      }
      if (!a.isModified && b.isModified) {
        return 1;
      }
      return 0;
    });

    return result;
  }

  async #buildAragonSectionData(contractLabel: string) {
    const contractAddress = this.#config.getAddressByLabel(contractLabel);

    const contractPermissionsConfig = this.#config.getAragonConfig(contractLabel);
    const contractPermissionsSnapshot = this.#snapshot.aragon[contractAddress] || { grantedTo: [] };

    const result: Record<string, AragonPermissionTableData> = {};
    for (const [roleName, permissionsConfig] of Object.entries(contractPermissionsConfig)) {
      if (!this.#roleHashesMap[roleName]) {
        this.#roleHashesMap[roleName] = await this.#getRoleHash(contractAddress, roleName);
      }
      const roleHash = this.#roleHashesMap[roleName];

      const roleSnapshot = contractPermissionsSnapshot[roleHash] || { roleAdmin: ZERO_HASH, grantedTo: [] };

      const roleManagerAddress = roleSnapshot.roleManager;

      const currentRoleManager = roleManagerAddress
        ? { address: roleManagerAddress, label: this.#config.getLabelByAddress(roleManagerAddress) }
        : { address: null, label: "∅" };

      const newRoleManagerLabel = permissionsConfig.manager;
      const newRoleManager =
        permissionsConfig.manager === "None"
          ? { address: null, label: "∅" }
          : { label: newRoleManagerLabel, address: this.#config.getAddressByLabel(newRoleManagerLabel) };

      const holdersToBeGrantedWithRole: AccountInfo[] = (permissionsConfig.grantedTo ?? []).map((granteeLabel) => ({
        label: granteeLabel,
        address: this.#config.getAddressByLabel(granteeLabel),
      }));

      let holdersCurrentlyGrantedWithRole: AccountInfo[] = roleSnapshot.grantedTo.map((grantee) => ({
        label: this.#config.getLabelByAddress(grantee.address),
        address: grantee.address,
      }));

      let sdvtNodeOperatorsCount = 0;
      const simpleDVTAddress = this.#config.getAddressByLabel("SimpleDVT");
      if (contractAddress === simpleDVTAddress && roleName === "MANAGE_SIGNING_KEYS") {
        for (const grantee of roleSnapshot.grantedTo) {
          if (grantee.paramsHash) {
            const paramsLength = await this.#getACLPermissionParamsLength(grantee.address, contractAddress, roleHash);

            if (paramsLength > 1) {
              throw new Error(`Invalid MANAGE_SIGNING_KEYS params length`);
            }

            // exclude managers from the list, as they do not require any actions and will be shown as collapsed badge
            holdersCurrentlyGrantedWithRole = holdersCurrentlyGrantedWithRole.filter(
              (g) => g.address !== grantee.address
            );
            sdvtNodeOperatorsCount += 1;
          }
        }
      }

      // All role holders who presented in both snapshot and config
      const currentRoleHolders = holdersCurrentlyGrantedWithRole.filter((currentGrantee) =>
        holdersToBeGrantedWithRole.some((newGrantee) => newGrantee.address === currentGrantee.address)
      );

      // All role holder who presented in the config AND not presented in the snapshot
      const holdersToGrantRole = holdersToBeGrantedWithRole.filter((newGrantee) =>
        holdersCurrentlyGrantedWithRole.every((currentGrantee) => newGrantee.address !== currentGrantee.address)
      );

      // All role holder who presented in the snapshot AND not presented in the config
      const holdersToRevokeRole = holdersCurrentlyGrantedWithRole.filter((currentGrantee) =>
        holdersToBeGrantedWithRole.every((newGrantee) => newGrantee.address !== currentGrantee.address)
      );

      if (sdvtNodeOperatorsCount > 0) {
        currentRoleHolders.push({ label: `+${sdvtNodeOperatorsCount} Simple DVT Operator(s)`, address: null });
      }

      result[roleName] = {
        name: roleName,
        hash: roleHash,
        isModified:
          newRoleManager.address !== currentRoleManager.address ||
          holdersToGrantRole.length > 0 ||
          holdersToRevokeRole.length > 0,
        newManager: newRoleManager,
        currentManager: currentRoleManager,
        currentRoleHolders,
        holdersToGrantRole,
        holdersToRevokeRole,
      };
    }
    return result;
  }

  async #buildOZSectionData(contractLabel: string) {
    const contractAddress = this.#config.getAddressByLabel(contractLabel);
    const contractRolesSnapshot = this.#snapshot.oz[contractAddress];

    const contractRolesConfig = this.#config.getOZConfig(contractLabel);

    const result: Record<string, OZRoleTableData> = {};
    for (const [roleName, labelsToGrantRole] of Object.entries(contractRolesConfig)) {
      if (!this.#roleHashesMap[roleName]) {
        this.#roleHashesMap[roleName] = await this.#getRoleHash(contractAddress, roleName);
      }
      const roleHash = this.#roleHashesMap[roleName];

      const roleSnapshot = contractRolesSnapshot[roleHash] || { roleAdmin: ZERO_HASH, grantedTo: [] };

      const roleAdminHash = roleSnapshot.roleAdmin;

      const holdersToBeGrantedWithRole = labelsToGrantRole.map((granteeLabel) => ({
        label: granteeLabel,
        address: this.#config.getAddressByLabel(granteeLabel),
      }));

      const holdersCurrentlyGrantedWithRole = roleSnapshot.grantedTo.map((granteeAddress) => ({
        label: this.#config.getLabelByAddress(granteeAddress),
        address: granteeAddress,
      }));

      // All role holders who presented in both snapshot and config
      const currentRoleHolders = holdersCurrentlyGrantedWithRole.filter((currentGrantee) =>
        holdersToBeGrantedWithRole.some((newGrantee) => newGrantee.address === currentGrantee.address)
      );

      // All role holder who presented in the config AND not presented in the snapshot
      const holdersToGrantRole = holdersToBeGrantedWithRole.filter((newGrantee) =>
        holdersCurrentlyGrantedWithRole.every((currentGrantee) => newGrantee.address !== currentGrantee.address)
      );

      // All role holder who presented in the snapshot AND not presented in the config
      const holdersToRevokeRole = holdersCurrentlyGrantedWithRole.filter((currentGrantee) =>
        holdersToBeGrantedWithRole.every((newGrantee) => newGrantee.address !== currentGrantee.address)
      );

      result[roleName] = {
        name: roleName,
        hash: roleHash,
        isModified: holdersToGrantRole.length > 0 || holdersToRevokeRole.length > 0,
        adminRole: roleAdminHash,
        currentRoleHolders,
        holdersToGrantRole,
        holdersToRevokeRole,
      };
    }
    return result;
  }

  async #buildOwnershipSectionData(contractLabel: string): Promise<OwnershipSectionData> {
    const config = this.#config.getOwnershipConfig(contractLabel);
    const address = this.#config.getAddressByLabel(contractLabel);

    const currentlyManagedByAddress = decodeAddress(await makeContractCall(this.#rpcURL, address, config.getter));
    const currentlyManagedByLabel = this.#config.getLabelByAddress(currentlyManagedByAddress);

    return {
      address,
      isModified: config.owner !== currentlyManagedByLabel,
      contractLabel,
      propertyGetter: config.getter,
      newManagedBy: { label: config.owner, address: this.#config.getAddressByLabel(config.owner) },
      oldManagedBy: { label: currentlyManagedByLabel, address: currentlyManagedByAddress },
    };
  }

  async #formatOZRolesMigrationSteps(contractsData: OZContractsPermissions[]) {
    const result: string[][] = [];

    for (const { contractLabel, rolesData } of contractsData) {
      const contractMigrationSteps: string[] = [];
      for (const roleData of rolesData) {
        for (const newGrantee of roleData.holdersToGrantRole) {
          contractMigrationSteps.push(`Grant ${roleData.name} to ${newGrantee.label} on ${contractLabel}`);
        }
        for (const granteesToRevoke of roleData.holdersToRevokeRole) {
          contractMigrationSteps.push(`Revoke ${roleData.name} from ${granteesToRevoke.label} on ${contractLabel}`);
        }
      }
      result.push(contractMigrationSteps);
    }
    return result;
  }

  async #formatAragonPermissionMigrationSteps(contractsData: AragonContractsPermissions[]) {
    const result: string[][] = [];

    for (const { contractLabel, permissionsData } of contractsData) {
      const contractMigrationSteps: string[] = [];
      for (const permissionData of permissionsData) {
        let isPermissionCreated = permissionData.currentManager.address !== null;
        for (const newGrantee of permissionData.holdersToGrantRole) {
          if (!isPermissionCreated) {
            contractMigrationSteps.push(
              `Create ${permissionData.name} permission on ${contractLabel} with manager ${permissionData.newManager.label} and grant it to ${newGrantee.label}`
            );
            isPermissionCreated = true;
          } else {
            contractMigrationSteps.push(
              `Grant ${permissionData.name} permission to ${newGrantee.label} on ${contractLabel}`
            );
          }
        }
        for (const granteesToRevoke of permissionData.holdersToRevokeRole) {
          contractMigrationSteps.push(
            `Revoke ${permissionData.name} permission from ${granteesToRevoke.label} on ${contractLabel}`
          );
        }
        if (
          permissionData.currentManager.address &&
          permissionData.currentManager.address !== permissionData.newManager.address
        ) {
          contractMigrationSteps.push(
            `Set ${permissionData.name} manager to ${permissionData.newManager.label} on ${contractLabel}`
          );
        }
        if (!permissionData.currentManager.address && permissionData.newManager.address && !isPermissionCreated) {
          contractMigrationSteps.push("[ERROR]: To create permission it should be granted to someone");
        }
      }
      result.push(contractMigrationSteps);
    }
    return result;
  }

  async #formatAragonContractTables(contractsData: AragonContractsPermissions[]) {
    const result: string[] = [];

    for (const { permissionsData } of contractsData) {
      const contractMigrationRows: string[] = [];
      contractMigrationRows.push(this.#formatAragonPermissionsTableHeader());

      const sortedContractTableData = Object.values(permissionsData).sort((a, b) => {
        const isAModified = a.holdersToGrantRole.length > 0 || a.holdersToRevokeRole.length > 0;
        const isBModified = b.holdersToGrantRole.length > 0 || b.holdersToRevokeRole.length > 0;
        if (isAModified && !isBModified) return -1;
        if (!isAModified && isBModified) return 1;
        return 0;
      });

      for (const roleData of sortedContractTableData) {
        contractMigrationRows.push(this.#formatAragonPermissionTableRow(roleData));
      }

      result.push(contractMigrationRows.join("\n"));
    }
    return result;
  }

  async #formatOZContractTables(contractsData: OZContractsPermissions[]) {
    const result: string[] = [];
    for (const { rolesData } of contractsData) {
      const contractMigrationRows: string[] = [];
      contractMigrationRows.push(this.#formatOZRoleTableHeader());

      const sortedContractTableData = Object.values(rolesData).sort((a, b) => {
        const isAModified = a.holdersToGrantRole.length > 0 || a.holdersToRevokeRole.length > 0;
        const isBModified = b.holdersToGrantRole.length > 0 || b.holdersToRevokeRole.length > 0;
        if (isAModified && !isBModified) return -1;
        if (!isAModified && isBModified) return 1;
        return 0;
      });

      for (const roleData of sortedContractTableData) {
        contractMigrationRows.push(this.#formatOZRoleTableRow(roleData));
      }
      result.push(contractMigrationRows.join("\n"));
    }
    return result;
  }

  #formatContractsOwnershipTable(contractsData: OwnershipSectionData[]) {
    const result: string[] = [this.#formatContractsOwnershipTableHeader()];
    for (const ownershipData of contractsData) {
      result.push(this.#formatContractsOwnershipTableRow(ownershipData));
    }
    return result.join("\n");
  }

  #formatContractsOwnershipMigrationSteps(contractsData: OwnershipSectionData[]) {
    const result: string[] = [];
    for (const roleData of contractsData) {
      if (roleData.isModified) {
        result.push(`Set admin to ${roleData.newManagedBy.label} on ${roleData.contractLabel}`);
      }
    }
    return result;
  }

  #formatMarkdownTableRow(items: string[]) {
    return `| ${items.join(" | ")} |`;
  }

  #formatOZRoleTableHeader(): string {
    return [
      this.#formatMarkdownTableRow(this.#ozContractTableColumns),
      this.#formatMarkdownTableRow(Array(this.#ozContractTableColumns.length).fill("---")),
    ].join("\n");
  }

  #formatOZRoleTableRow(role: OZRoleTableData) {
    const isModified = role.holdersToGrantRole.length > 0 || role.holdersToRevokeRole.length > 0;
    const adminRoleMatch = Object.entries(this.#roleHashesMap).find(([name, hash]) => role.adminRole === hash);
    const adminRoleNameOrHash = adminRoleMatch ? adminRoleMatch[0] : role.adminRole;

    return this.#formatMarkdownTableRow([
      this.#formatRoleName(role.name, isModified),
      this.#formatRoleAdmin(adminRoleNameOrHash),
      role.holdersToRevokeRole.map((acc) => this.#formatHolderToRevoke(acc)).join(" ") || "∅",
      [
        ...role.holdersToGrantRole.map((acc) => this.#formatHolderToGrantRole(acc)),
        ...role.currentRoleHolders.map((acc) => this.#formatCurrentRoleHolder(acc)),
      ].join(" ") || "∅",
    ]);
  }

  #formatAragonPermissionsTableHeader(): string {
    return [
      this.#formatMarkdownTableRow(this.#aragonContractTableColumns),
      this.#formatMarkdownTableRow(Array(this.#aragonContractTableColumns.length).fill("---")),
    ].join("\n");
  }

  #formatAragonPermissionTableRow(role: AragonPermissionTableData) {
    const isModified =
      role.currentManager.address !== role.newManager.address ||
      role.holdersToGrantRole.length > 0 ||
      role.holdersToRevokeRole.length > 0;

    return this.#formatMarkdownTableRow([
      this.#formatRoleName(role.name, isModified),
      this.#formatPermissionManager(role.currentManager, role.newManager, isModified),
      role.holdersToRevokeRole.map((acc) => this.#formatHolderToRevoke(acc)).join(" ") || "∅",
      [
        ...role.holdersToGrantRole.map((acc) => this.#formatHolderToGrantRole(acc)),
        ...role.currentRoleHolders.map((acc) => this.#formatCurrentRoleHolder(acc)),
      ].join(" ") || "∅",
    ]);
  }

  #formatContractsOwnershipTableHeader(): string {
    return [
      this.#formatMarkdownTableRow(this.#contractsOwnershipTableColumns),
      this.#formatMarkdownTableRow(Array(this.#contractsOwnershipTableColumns.length).fill("---")),
    ].join("\n");
  }

  #formatContractsOwnershipTableRow(ownershipData: OwnershipSectionData): string {
    return this.#formatMarkdownTableRow([
      this.#formatContractLabel(ownershipData.contractLabel, ownershipData.isModified),
      `\`${ownershipData.propertyGetter}\``,
      this.#formatContractLabel(ownershipData.oldManagedBy.label, false),
      this.#formatContractLabel(ownershipData.newManagedBy.label, ownershipData.isModified),
    ]);
  }

  #formatRoleName(roleName: string, isModified: boolean) {
    if (roleName === "DEFAULT_ADMIN_ROLE") {
      return isModified ? `⚠️ \`${roleName}\`` : `\`${roleName}\``;
    }

    const keccakEncoderLink = `https://emn178.github.io/online-tools/keccak_256.html?input=${roleName}&input_type=utf-8&output_type=hex`;
    return isModified ? `⚠️ [\`${roleName}\`](${keccakEncoderLink})` : `[\`${roleName}\`](${keccakEncoderLink})`;
  }

  #formatContractLabel(contractLabel: string, isModified: boolean) {
    const contractAddress = this.#config.getAddressByLabel(contractLabel);
    if (isModified) {
      return `⚠️ [\`${contractLabel}\`](${this.#config.getExplorerURL(contractAddress)})`;
    }
    return `[\`${contractLabel}\`](${this.#config.getExplorerURL(contractAddress)})`;
  }

  #formatRoleAdmin(text: string) {
    return this.#formatRoleName(text, false);
  }

  #formatCurrentRoleHolder(account: AccountInfo) {
    if (account.address) {
      return `[\`${account.label}\`](${this.#config.getExplorerURL(account.address)})`;
    }
    return `\`${account.label}\``;
  }

  #formatHolderToRevoke(account: AccountInfo) {
    if (account.address) {
      return `⚠️ [\`${account.label}\`](${this.#config.getExplorerURL(account.address)})`;
    }
    return `⚠️ \`${account.label}\``;
  }

  #formatContractHeader(contractLabel: string) {
    const contractAddress = this.#config.getAddressByLabel(contractLabel);
    return `#### ${contractLabel} [${contractAddress}](${this.#config.getExplorerURL(contractAddress)})`;
  }

  #formatHolderToGrantRole(account: AccountInfo) {
    if (account.address) {
      return `⚠️ [\`${account.label}\`](${this.#config.getExplorerURL(account.address)})`;
    }
    return `⚠️ \`${account.label}\``;
  }

  #formatPermissionManager(currentManager: AccountInfo, newManager: AccountInfo, isModified: boolean) {
    const currentManagerLabel =
      currentManager.address === null
        ? currentManager.label
        : `[\`${currentManager.label}\`](${this.#config.getExplorerURL(currentManager.address)})`;
    const newManagerLabel =
      newManager.address === null
        ? newManager.label
        : `[\`${newManager.label}\`](${this.#config.getExplorerURL(newManager.address)})`;

    return currentManager.label === newManager.label
      ? currentManagerLabel
      : `⚠️ ${currentManagerLabel} → ${newManagerLabel}`;
  }

  async #getACLPermissionParamsLength(entity: Address, app: Address, role: HexStrPrefixed) {
    const paramsLengthAbiEncoded = await makeContractCall(
      this.#rpcURL,
      this.#config.getAragonACLAddress(),
      "getPermissionParamsLength",
      ["address", "address", "bytes32"],
      [entity, app, role]
    );
    return parseInt(BigInt(paramsLengthAbiEncoded).toString());
  }

  #getRoleHash(address: Address, roleName: string) {
    return makeContractCall(this.#rpcURL, address, roleName);
  }
}
