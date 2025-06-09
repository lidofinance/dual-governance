import { JsonRpcProvider } from "ethers";

import { HexStrPrefixed, Address } from "./bytes";
import { PermissionsSnapshot } from "./events-reducer";
import { PermissionsConfig } from "./permissions-config";
import { decodeAddress, makeContractCall, ZERO_HASH } from "./utils";

interface AccountInfo {
  label: string;
  address: Address | null;
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

interface GettersTableData {
  address: Address;
  isModified: boolean;
  contractLabel: string;
  getters: GettersTableDataItem[];
}

interface GettersTableDataItem {
  isModified: boolean;
  propertyGetter: string;
  actualValue: AccountInfo;
  expectedValue: AccountInfo;
}

export class PermissionsMarkdownFormatter {
  #provider: JsonRpcProvider;
  #config: PermissionsConfig;
  #snapshot: PermissionsSnapshot;
  #roleHashesMap: Record<string, HexStrPrefixed> = {};

  #ozContractTableColumns: string[] = ["Role", "Role Admin", "Revoked", "Granted"];
  #aragonContractTableColumns: string[] = ["Permission", "Permission Manager", "Revoked", "Granted"];
  #contractsGettersTableColumns: string[] = ["Getter", "Actual Value", "Expected Value"];

  constructor(provider: JsonRpcProvider, config: PermissionsConfig, snapshot: PermissionsSnapshot) {
    this.#provider = provider;
    this.#config = config;
    this.#snapshot = snapshot;
  }

  async format() {
    const result: string[] = [
      "## Lido Permissions Transition\n",
      this.#formatCollectDataInfo(),
      this.#formatDocumentHowTo(),
    ];
    const contractTablesData = await this.#buildContractTablesData();

    const [
      aragonContractTables,
      aragonPermissionTransitionSteps,
      ozRolesTransitionSteps,
      ozContractTables,
      gettersTables,
      gettersTransitionSteps,
    ] = await Promise.all([
      this.#formatAragonContractTables(contractTablesData.aragon),
      this.#formatAragonPermissionTransitionSteps(contractTablesData.aragon),
      this.#formatOZRolesTransitionSteps(contractTablesData.oz),
      this.#formatOZContractTables(contractTablesData.oz),
      this.#formatGettersTables(contractTablesData.getters),
      this.#formatGettersTransitionSteps(contractTablesData.getters),
    ]);

    let transitionStepNumber = 1;
    result.push("### Aragon Permissions");
    for (let i = 0; i < contractTablesData.aragon.length; ++i) {
      const isContractModified = contractTablesData.aragon[i].permissionsData.some((d) => d.isModified);
      result.push(this.#formatContractHeader(contractTablesData.aragon[i].contractLabel, isContractModified));
      result.push(aragonContractTables[i]);
      result.push("");
      if (aragonPermissionTransitionSteps[i].length > 0) {
        result.push("##### Transition Steps\n");
        result.push("```");
        for (let transitionStep of aragonPermissionTransitionSteps[i]) {
          result.push(`${transitionStepNumber++}. ${transitionStep}`);
        }
        result.push("```\n");
      }
    }

    result.push("### OZ Roles");
    for (let i = 0; i < contractTablesData.oz.length; ++i) {
      const isContractModified = contractTablesData.oz[i].rolesData.some((d) => d.isModified);
      result.push(this.#formatContractHeader(contractTablesData.oz[i].contractLabel, isContractModified));
      result.push(ozContractTables[i]);
      result.push("");
      if (ozRolesTransitionSteps[i].length > 0) {
        result.push("##### Transition Steps\n");
        result.push("```");
        for (let transitionStep of ozRolesTransitionSteps[i]) {
          result.push(`${transitionStepNumber++}. ${transitionStep}`);
        }
        result.push("```\n");
      }
    }

    result.push("### Contracts Ownership");
    for (let i = 0; i < contractTablesData.getters.length; ++i) {
      const contractGetterData = contractTablesData.getters[i];
      result.push(this.#formatContractHeader(contractGetterData.contractLabel, contractGetterData.isModified));
      result.push(gettersTables[i]);
      result.push("");
      if (gettersTransitionSteps[i].length > 0) {
        result.push("##### Transition Steps\n");
        result.push("```");
        for (let transitionStep of gettersTransitionSteps[i]) {
          result.push(`${transitionStepNumber++}. ${transitionStep}`);
        }
        result.push("```\n");
      }
    }

    result.push("");

    return result.join("\n");
  }

  async #buildContractTablesData() {
    const result: {
      oz: OZContractsPermissions[];
      aragon: AragonContractsPermissions[];
      getters: GettersTableData[];
    } = {
      oz: [],
      aragon: [],
      getters: [],
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

    for (const gettersContractLabel of Object.keys(this.#config.getGettersConfig())) {
      result.getters.push(await this.#buildGettersSectionData(gettersContractLabel));
    }

    result.getters.sort((a, b) => {
      if (a.isModified && !b.isModified) return -1;
      if (!a.isModified && b.isModified) return 1;
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

  async #buildGettersSectionData(contractLabel: string): Promise<GettersTableData> {
    const gettersConfig = this.#config.getGettersConfig(contractLabel);
    const address = this.#config.getAddressByLabel(contractLabel);

    const gettersTableItems: GettersTableDataItem[] = [];
    for (const [getterName, expectedGetterLabel] of Object.entries(gettersConfig)) {
      const actualGetterValue = decodeAddress(
        await makeContractCall(this.#provider, {
          address,
          methodName: getterName,
          blockTag: this.#snapshot.snapshotBlockNumber,
        })
      );
      const actualGetterLabel = this.#config.getLabelByAddress(actualGetterValue);
      gettersTableItems.push({
        isModified: expectedGetterLabel !== actualGetterLabel,
        propertyGetter: getterName,
        actualValue: { label: actualGetterLabel, address: actualGetterValue },
        expectedValue: { label: expectedGetterLabel, address: this.#config.getAddressByLabel(expectedGetterLabel) },
      });
    }
    return {
      address,
      contractLabel,
      isModified: gettersTableItems.some((item) => item.isModified),
      getters: gettersTableItems,
    };
  }

  #formatCollectDataInfo() {
    const snapshotBlockNumber = this.#snapshot.snapshotBlockNumber;
    const snapshotBlockExplorerURL = this.#config.getExplorerBlockURL(snapshotBlockNumber);
    const lastProcessedBlockNumber = this.#snapshot.lastProcessedBlockNumber;
    const lastProcessedBlockExplorerURL = this.#config.getExplorerBlockURL(lastProcessedBlockNumber);
    const lastProcessedTxHash = this.#snapshot.lastProcessedTransactionHash!;
    const lastProcessedTxExplorerURL = this.#config.getExplorerTxURL(lastProcessedTxHash);

    return [
      `> - Data was collected at block [\`${snapshotBlockNumber}\`](${snapshotBlockExplorerURL})`,
      [
        `> - The last permissions change occurred at block [\`${lastProcessedBlockNumber}\`](${lastProcessedBlockExplorerURL}),`,
        `transaction [\`${lastProcessedTxHash}\`](${lastProcessedTxExplorerURL})\n`,
      ].join(" "),
    ].join("\n");
  }

  #formatDocumentHowTo() {
    return [
      "How to read this document:",
      [
        '- If an item is prepended with the "⚠️" icon, it indicates that the item will be changed.',
        'The required updates are described in the corresponding "Transition Steps" sections.',
      ].join(" "),
      '- The special symbol "∅" indicates that:',
      "  - a permission or role is not granted to any address",
      "  - revocation of the permission or role is not performed",
      "  - no manager is set for the permission",
      '- The notation "`Old Manager` → `New Manager`" means the current manager is being changed to a new one.',
      [
        '  - A special case is "`∅` → `New Manager`", which means the permission currently has no manager,',
        "and the permission should be created before use.\n",
      ].join(" "),
    ].join("\n");
  }

  // ---
  // Aragon Permissions Formatting
  // ---

  async #formatAragonContractTables(contractsData: AragonContractsPermissions[]) {
    const result: string[] = [];

    for (const { permissionsData } of contractsData) {
      const contractTransitionRows: string[] = [];
      contractTransitionRows.push(this.#formatAragonPermissionsTableHeader());

      const sortedContractTableData = Object.values(permissionsData).sort((a, b) => {
        if (a.isModified && !b.isModified) return -1;
        if (!a.isModified && b.isModified) return 1;
        return 0;
      });

      for (const roleData of sortedContractTableData) {
        contractTransitionRows.push(this.#formatAragonPermissionTableRow(roleData));
      }

      result.push(contractTransitionRows.join("\n"));
    }
    return result;
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

  async #formatAragonPermissionTransitionSteps(contractsData: AragonContractsPermissions[]) {
    const result: string[][] = [];

    for (const { contractLabel, permissionsData } of contractsData) {
      const contractTransitionSteps: string[] = [];
      for (const permissionData of permissionsData) {
        let isPermissionCreated = permissionData.currentManager.address !== null;
        for (const newGrantee of permissionData.holdersToGrantRole) {
          if (!isPermissionCreated) {
            contractTransitionSteps.push(
              `Create ${permissionData.name} permission on ${contractLabel} with manager ${permissionData.newManager.label} and grant it to ${newGrantee.label}`
            );
            isPermissionCreated = true;
          } else {
            contractTransitionSteps.push(
              `Grant ${permissionData.name} permission to ${newGrantee.label} on ${contractLabel}`
            );
          }
        }
        for (const granteesToRevoke of permissionData.holdersToRevokeRole) {
          contractTransitionSteps.push(
            `Revoke ${permissionData.name} permission from ${granteesToRevoke.label} on ${contractLabel}`
          );
        }
        if (
          permissionData.currentManager.address &&
          permissionData.currentManager.address !== permissionData.newManager.address
        ) {
          contractTransitionSteps.push(
            `Set ${permissionData.name} manager to ${permissionData.newManager.label} on ${contractLabel}`
          );
        }
        if (!permissionData.currentManager.address && permissionData.newManager.address && !isPermissionCreated) {
          contractTransitionSteps.push("[ERROR]: To create permission it should be granted to someone");
        }
      }
      result.push(contractTransitionSteps);
    }
    return result;
  }

  // ---
  // OZ Roles Formatting
  // ---

  async #formatOZContractTables(contractsData: OZContractsPermissions[]) {
    const result: string[] = [];
    for (const { rolesData } of contractsData) {
      const contractTransitionRows: string[] = [];
      contractTransitionRows.push(this.#formatOZRoleTableHeader());

      const sortedContractTableData = Object.values(rolesData).sort((a, b) => {
        if (a.isModified && !b.isModified) return -1;
        if (!a.isModified && b.isModified) return 1;
        return 0;
      });

      for (const roleData of sortedContractTableData) {
        contractTransitionRows.push(this.#formatOZRoleTableRow(roleData));
      }
      result.push(contractTransitionRows.join("\n"));
    }
    return result;
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

  async #formatOZRolesTransitionSteps(contractsData: OZContractsPermissions[]) {
    const result: string[][] = [];

    for (const { contractLabel, rolesData } of contractsData) {
      const contractTransitionSteps: string[] = [];
      for (const roleData of rolesData) {
        for (const newGrantee of roleData.holdersToGrantRole) {
          contractTransitionSteps.push(`Grant ${roleData.name} to ${newGrantee.label} on ${contractLabel}`);
        }
        for (const granteesToRevoke of roleData.holdersToRevokeRole) {
          contractTransitionSteps.push(`Revoke ${roleData.name} from ${granteesToRevoke.label} on ${contractLabel}`);
        }
      }
      result.push(contractTransitionSteps);
    }
    return result;
  }

  // ---
  // Contract Getters Formatting
  // ---

  #formatGettersTables(contractsData: GettersTableData[]): string[] {
    const result: string[] = [];
    for (const contractData of contractsData) {
      const contractTransitionRows: string[] = [];
      contractTransitionRows.push(this.#formatGettersTableHeader());

      const sortedContractTableData = Object.values(contractData.getters).sort((a, b) => {
        if (a.isModified && !b.isModified) return -1;
        if (!a.isModified && b.isModified) return 1;
        return 0;
      });

      for (const roleData of sortedContractTableData) {
        contractTransitionRows.push(this.#formatGettersTableRow(roleData));
      }
      result.push(contractTransitionRows.join("\n"));
    }
    return result;
  }

  #formatGettersTransitionSteps(contractsData: GettersTableData[]) {
    const result: string[][] = [];

    for (const contractData of contractsData) {
      const contractTransitionSteps: string[] = [];
      for (const getter of contractData.getters) {
        if (getter.isModified) {
          const getterType = getter.propertyGetter.toLowerCase().includes("owner") ? "owner" : "admin";
          contractTransitionSteps.push(
            `Set ${getterType} to ${getter.expectedValue.label} on ${contractData.contractLabel}`
          );
        }
      }
      result.push(contractTransitionSteps);
    }

    return result;
  }

  #formatMarkdownTableRow(items: string[]) {
    return `| ${items.join(" | ")} |`;
  }

  #formatGettersTableHeader(): string {
    return [
      this.#formatMarkdownTableRow(this.#contractsGettersTableColumns),
      this.#formatMarkdownTableRow(Array(this.#contractsGettersTableColumns.length).fill("---")),
    ].join("\n");
  }

  #formatGettersTableRow(gettersDataItem: GettersTableDataItem): string {
    return this.#formatMarkdownTableRow([
      gettersDataItem.isModified ? `⚠️ \`${gettersDataItem.propertyGetter}\`` : `\`${gettersDataItem.propertyGetter}\``,
      this.#formatContractLabel(gettersDataItem.actualValue.label, false),
      this.#formatContractLabel(gettersDataItem.expectedValue.label, gettersDataItem.isModified),
    ]);
  }

  // ---
  // Common Formatters
  // ---

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
      return `⚠️ [\`${contractLabel}\`](${this.#config.getExplorerAddressURL(contractAddress)})`;
    }
    return `[\`${contractLabel}\`](${this.#config.getExplorerAddressURL(contractAddress)})`;
  }

  #formatRoleAdmin(text: string) {
    return this.#formatRoleName(text, false);
  }

  #formatCurrentRoleHolder(account: AccountInfo) {
    if (account.address) {
      return `[\`${account.label}\`](${this.#config.getExplorerAddressURL(account.address)})`;
    }
    return `\`${account.label}\``;
  }

  #formatHolderToRevoke(account: AccountInfo) {
    if (account.address) {
      return `⚠️ [\`${account.label}\`](${this.#config.getExplorerAddressURL(account.address)})`;
    }
    return `⚠️ \`${account.label}\``;
  }

  #formatContractHeader(contractLabel: string, isModified: boolean = false) {
    const contractAddress = this.#config.getAddressByLabel(contractLabel);
    return isModified
      ? `#### ⚠️ ${contractLabel} [${contractAddress}](${this.#config.getExplorerAddressURL(contractAddress)})`
      : `#### ${contractLabel} [${contractAddress}](${this.#config.getExplorerAddressURL(contractAddress)})`;
  }

  #formatHolderToGrantRole(account: AccountInfo) {
    if (account.address) {
      return `⚠️ [\`${account.label}\`](${this.#config.getExplorerAddressURL(account.address)})`;
    }
    return `⚠️ \`${account.label}\``;
  }

  #formatPermissionManager(currentManager: AccountInfo, newManager: AccountInfo, isModified: boolean) {
    const currentManagerLabel =
      currentManager.address === null
        ? currentManager.label
        : `[\`${currentManager.label}\`](${this.#config.getExplorerAddressURL(currentManager.address)})`;
    const newManagerLabel =
      newManager.address === null
        ? newManager.label
        : `[\`${newManager.label}\`](${this.#config.getExplorerAddressURL(newManager.address)})`;

    return currentManager.label === newManager.label
      ? currentManagerLabel
      : `⚠️ ${currentManagerLabel} → ${newManagerLabel}`;
  }

  // ---
  // Helper Permissions Methods
  // ---

  async #getACLPermissionParamsLength(entity: Address, app: Address, role: HexStrPrefixed) {
    const paramsLengthAbiEncoded = await makeContractCall(this.#provider, {
      address: this.#config.getAragonACLAddress(),
      methodName: "getPermissionParamsLength",
      argTypes: ["address", "address", "bytes32"],
      argValues: [entity, app, role],
    });
    return parseInt(BigInt(paramsLengthAbiEncoded).toString());
  }

  #getRoleHash(address: Address, roleName: string) {
    return makeContractCall(this.#provider, {
      address,
      methodName: roleName,
      blockTag: this.#snapshot.snapshotBlockNumber,
    });
  }
}
