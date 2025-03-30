import { HOODI_PERMISSIONS_CONFIG } from "../config/hoodi";
import { MAINNET_PERMISSIONS_CONFIG } from "../config/mainnet";
import { HOLESKY_PERMISSIONS_CONFIG } from "../config/holesky";
import bytes, { Address } from "./bytes";

type OZContractRolesConfig = Record<string, string[]>;
type OZRolesConfig = Record<string, OZContractRolesConfig>;

interface AragonPermissionConfig {
  manager: string;
  grantedTo?: string[];
}
type AragonContractPermissionsConfig = Record<string, AragonPermissionConfig>;
type AragonPermissionsConfig = Record<string, AragonContractPermissionsConfig>;

interface OwnershipConfigItem {
  owner: string;
  getter: string;
  setter: string;
}
type OwnershipConfig = Record<string, OwnershipConfigItem>;

export interface PermissionsConfig {
  genesisBlock: number;
  explorerURL: string;
  labels: Record<string, Address>;
  aragon: AragonPermissionsConfig;
  oz: OZRolesConfig;
  ownership: OwnershipConfig;
}

export class PermissionsLayout {
  #config: PermissionsConfig;

  private constructor(config: PermissionsConfig) {
    this.#config = config;
  }

  static load(network: string) {
    if (network === "mainnet") {
      return new PermissionsLayout(MAINNET_PERMISSIONS_CONFIG);
    } else if (network === "holesky") {
      return new PermissionsLayout(HOLESKY_PERMISSIONS_CONFIG);
    } else if (network === "hoodi") {
      return new PermissionsLayout(HOODI_PERMISSIONS_CONFIG);
    } else {
      throw new Error(`Unsupported network "${network}"`);
    }
  }

  getGenesisBlockNumber() {
    return this.#config.genesisBlock;
  }

  getOZConfig(): OZRolesConfig;
  getOZConfig(contractLabel: string): OZContractRolesConfig;
  getOZConfig(contractLabel?: string) {
    if (!contractLabel) {
      return this.#config.oz;
    }
    if (!this.#config.oz[contractLabel]) {
      throw new Error(`OZ config for contract "${contractLabel}" not found`);
    }
    return this.#config.oz[contractLabel];
  }

  getAragonConfig(): AragonPermissionsConfig;
  getAragonConfig(contractLabel: string): AragonContractPermissionsConfig;
  getAragonConfig(contractLabel?: string) {
    if (!contractLabel) {
      return this.#config.aragon;
    }
    if (!this.#config.aragon[contractLabel]) {
      throw new Error(`Aragon config for contract "${contractLabel}" not found`);
    }
    return this.#config.aragon[contractLabel];
  }

  getOwnershipConfig(): OwnershipConfig;
  getOwnershipConfig(contractLabel: string): OwnershipConfigItem;
  getOwnershipConfig(contractLabel?: string) {
    if (!contractLabel) {
      return this.#config.ownership;
    }
    if (!this.#config.ownership[contractLabel]) {
      throw new Error(`Aragon config for contract "${contractLabel}" not found`);
    }
    return this.#config.ownership[contractLabel];
  }

  getAragonACLAddress() {
    return this.getAddressByLabel("ACL");
  }

  getLabelByAddress(address: Address) {
    const match = Object.entries(this.#config.labels).find(
      ([, addr]) => bytes.normalize(addr) === bytes.normalize(address)
    );
    if (!match) {
      return `Unknown(${this.#shortenAddress(address)})`;
    }
    return match[0];
  }

  getAddressByLabel(label: string) {
    const match = Object.entries(this.#config.labels).find(([l]) => l === label);
    if (!match) {
      throw new Error(`Label "${label}" is not found in the config`);
    }
    return bytes.normalize(match[1]);
  }

  getExplorerURL(address: string) {
    return `${this.#config.explorerURL}/address/${address}`;
  }

  #shortenAddress(address: Address) {
    return `${address.slice(0, 8)}..${address.slice(-8)}`;
  }
}
