import { JsonRpcProvider } from "ethers";

import md from "./markdown";
import { Address } from "./bytes";
import { decodeAddress, makeContractCall } from "./utils";

import {
  CONTRACT_LABELS,
  LIDO_CONTRACTS_NAMES,
  LidoContractName,
} from "../config/lido-contracts";

export type ManagedContractsConfig = Record<string, ManagedContractConfig>;

interface ManagedContractConfig {
  address: Address;
  properties: Record<string, ManagedContractProperty>;
}

interface ManagedContractProperty {
  property: string;
  managedBy: LidoContractName;
}

interface ManagedContractPropertyInfo {
  address: Address;
  isModified: boolean;
  contractName: string;
  propertyName: string;
  propertyGetter: string;
  oldManagedBy: LidoContractName;
  newManagedBy: LidoContractName;
}

function formatControlledContractsSection(
  managedContractsPropertiesInfo: ManagedContractPropertyInfo[]
) {
  const resSectionLines: string[] = ["### Managed Contracts Updates \n"];
  const [totalModifiedRoles, tableText] = formatControlledContractsTable(
    managedContractsPropertiesInfo
  );

  resSectionLines.push(tableText);
  resSectionLines.push(`\n **Total Roles Modified: ${totalModifiedRoles}** \n`);

  return resSectionLines.join("\n");
}

function formatControlledContractsTable(
  managedContractsPropertiesInfo: ManagedContractPropertyInfo[]
) {
  const columnHeaders = ["Contract", "Property", "Old Manager", "New Manager"];
  const rows: string[][] = [];

  let modifiedPropertiesCount = 0;
  for (const info of managedContractsPropertiesInfo) {
    if (info.isModified) {
      modifiedPropertiesCount += 1;
    }
    const contractNameText = info.isModified
      ? md.bold(md.modified(info.contractName))
      : md.unchanged(info.contractName);
    const newManagedBy = info.isModified
      ? md.bold(
          md.label(CONTRACT_LABELS[info.newManagedBy] ?? info.newManagedBy)
        )
      : md.label(CONTRACT_LABELS[info.newManagedBy] ?? info.newManagedBy);
    rows.push([
      contractNameText,
      md.label(info.propertyGetter + "()"),
      md.label(CONTRACT_LABELS[info.oldManagedBy] ?? info.oldManagedBy),
      CONTRACT_LABELS[info.oldManagedBy] ?? newManagedBy,
    ]);
  }

  return [
    modifiedPropertiesCount,
    [md.header(columnHeaders), ...rows.map((row) => md.row(row))].join("\n"),
  ] as const;
}

async function collectManagedContractsInfo(
  provider: JsonRpcProvider,
  config: ManagedContractsConfig
) {
  const controlledContractsInfo: ManagedContractPropertyInfo[] = [];

  for (const [contractName, { address, properties }] of Object.entries(
    config
  )) {
    for (const [propertyName, { property, managedBy }] of Object.entries(
      properties
    )) {
      const currentlyManagedByAddress = decodeAddress(
        await makeContractCall(provider, address, property)
      );
      if (!LIDO_CONTRACTS_NAMES[currentlyManagedByAddress]) {
        throw new Error(
          `Unknown lido contract address ${currentlyManagedByAddress}`
        );
      }
      const currentlyManagedBy =
        LIDO_CONTRACTS_NAMES[currentlyManagedByAddress];

      controlledContractsInfo.push({
        address,
        isModified: managedBy !== currentlyManagedBy,
        contractName,
        propertyName,
        propertyGetter: property,
        newManagedBy: managedBy,
        oldManagedBy: currentlyManagedBy,
      });
    }
  }

  return controlledContractsInfo;
}

export default {
  formatControlledContractsSection,
  collectManagedContractsInfo,
};
