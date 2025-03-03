import { JsonRpcProvider } from "ethers";

import md from "./markdown";
import { Address } from "./bytes";
import { decodeAddress, makeContractCall } from "./utils";

import {
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
  managedContractsPropertiesInfo: ManagedContractPropertyInfo[],
) {
  const resSectionLines: string[] = ["### Managed Contracts Updates \n"];
  const [totalModifiedRoles, tableText] = formatControlledContractsTable(
    managedContractsPropertiesInfo,
  );

  resSectionLines.push(tableText);
  resSectionLines.push(`\n **Total Roles Modified: ${totalModifiedRoles}** \n`);
  resSectionLines.push(formatOperations(managedContractsPropertiesInfo));
  resSectionLines.push(`\n`);

  return resSectionLines.join("\n");
}

function formatOperations(
  managedContractsPropertiesInfo: ManagedContractPropertyInfo[],
) {
  const operations: string[] = [];

  const contractsMap = new Map<string, ManagedContractPropertyInfo[]>();

  for (const info of managedContractsPropertiesInfo) {
    if (!contractsMap.has(info.contractName)) {
      contractsMap.set(info.contractName, []);
    }
    contractsMap.get(info.contractName)!.push(info);
  }

  for (const [contractName, properties] of contractsMap) {
    const contractOperations: string[] = [];

    for (const property of properties) {
      if (property.isModified) {
        const setterMethodName = `set${property.propertyName.charAt(0).toUpperCase() + property.propertyName.slice(1)}`;
        contractOperations.push(
          `${setterMethodName}(${property.newManagedBy})`,
        );
      }
    }

    if (contractOperations.length > 0) {
      operations.push(`\n#### ${contractName}\n`);
      operations.push(...contractOperations);
    }
  }

  return operations.join("\n");
}

function formatControlledContractsTable(
  managedContractsPropertiesInfo: ManagedContractPropertyInfo[],
) {
  const columnHeaders = ["Contract", "Property", "Old Manager", "New Manager"];
  const rows: string[][] = [];

  let modifiedPropertiesCount = 0;
  for (const info of managedContractsPropertiesInfo) {
    if (info.isModified) {
      modifiedPropertiesCount += 1;
    }
    const contractNameText = info.isModified
      ? md.modified(info.contractName)
      : md.unchanged(info.contractName);
    const newManagedBy = info.isModified
      ? md.modified(info.newManagedBy)
      : md.label(info.newManagedBy);
    const oldManagedBy = info.isModified
      ? md.modified(info.oldManagedBy)
      : md.label(info.oldManagedBy);
    rows.push([
      contractNameText,
      md.label(info.propertyGetter + "()"),
      oldManagedBy,
      newManagedBy,
    ]);
  }

  return [
    modifiedPropertiesCount,
    [md.header(columnHeaders), ...rows.map((row) => md.row(row))].join("\n"),
  ] as const;
}

async function collectManagedContractsInfo(
  provider: JsonRpcProvider,
  config: ManagedContractsConfig,
) {
  const controlledContractsInfo: ManagedContractPropertyInfo[] = [];

  for (const [contractName, { address, properties }] of Object.entries(
    config,
  )) {
    for (const [propertyName, { property, managedBy }] of Object.entries(
      properties,
    )) {
      const currentlyManagedByAddress = decodeAddress(
        await makeContractCall(provider, address, property),
      );
      if (!LIDO_CONTRACTS_NAMES[currentlyManagedByAddress]) {
        throw new Error(
          `Unknown lido contract address ${currentlyManagedByAddress}`,
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
