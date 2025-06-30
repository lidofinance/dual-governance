import { HOODI_PERMISSIONS_CONFIG } from "../config/hoodi";
import { MAINNET_PERMISSIONS_CONFIG } from "../config/mainnet";
import { HOLESKY_PERMISSIONS_CONFIG } from "../config/holesky";
import bytes, { Address, HexStrPrefixed } from "./bytes";

type OZContractRolesConfig = Record<string, string[]>;
type OZRolesConfig = Record<string, OZContractRolesConfig>;

interface AragonPermissionConfig {
  manager: string;
  grantedTo?: string[];
}
type AragonContractPermissionsConfig = Record<string, AragonPermissionConfig>;
type AragonPermissionsConfig = Record<string, AragonContractPermissionsConfig>;

export interface PermissionsConfigData {
  genesisBlock: number;
  explorerURL: string;
  labels: Record<string, Address>;
  aragon: AragonPermissionsConfig;
  oz: OZRolesConfig;
  getters: Record<string, Record<string, string>>;
}

export class PermissionsConfig {
  #data: PermissionsConfigData;

  private constructor(config: PermissionsConfigData) {
    this.#data = config;
  }

  static load(network: string) {
    if (network === "mainnet") {
      return new PermissionsConfig(MAINNET_PERMISSIONS_CONFIG);
    } else if (network === "holesky") {
      return new PermissionsConfig(HOLESKY_PERMISSIONS_CONFIG);
    } else if (network === "hoodi") {
      return new PermissionsConfig(HOODI_PERMISSIONS_CONFIG);
    } else {
      throw new Error(`Unsupported network "${network}"`);
    }
  }

  getGenesisBlockNumber() {
    return this.#data.genesisBlock;
  }

  getOZConfig(): OZRolesConfig;
  getOZConfig(contractLabel: string): OZContractRolesConfig;
  getOZConfig(contractLabel?: string) {
    if (!contractLabel) {
      return this.#data.oz;
    }
    if (!this.#data.oz[contractLabel]) {
      throw new Error(`OZ config for contract "${contractLabel}" not found`);
    }
    return this.#data.oz[contractLabel];
  }

  getAragonConfig(): AragonPermissionsConfig;
  getAragonConfig(contractLabel: string): AragonContractPermissionsConfig;
  getAragonConfig(contractLabel?: string) {
    if (!contractLabel) {
      return this.#data.aragon;
    }
    if (!this.#data.aragon[contractLabel]) {
      throw new Error(`Aragon config for contract "${contractLabel}" not found`);
    }
    return this.#data.aragon[contractLabel];
  }

  getGettersConfig(): Record<string, string>;
  getGettersConfig(contractLabel: string): Record<string, string>;
  getGettersConfig(contractLabel?: string) {
    if (!contractLabel) {
      return this.#data.getters;
    }
    if (!this.#data.getters[contractLabel]) {
      throw new Error(`Aragon config for contract "${contractLabel}" not found`);
    }
    return this.#data.getters[contractLabel];
  }

  getAragonACLAddress() {
    return this.getAddressByLabel("ACL");
  }

  getLabelByAddress(address: Address) {
    const match = Object.entries(this.#data.labels).find(
      ([, addr]) => bytes.normalize(addr) === bytes.normalize(address)
    );
    if (!match) {
      return `Unknown(${this.#shortenAddress(address)})`;
    }
    return match[0];
  }

  getAddressByLabel(label: string) {
    const match = Object.entries(this.#data.labels).find(([l]) => l === label);
    if (!match) {
      throw new Error(`Label "${label}" is not found in the config`);
    }
    return bytes.normalize(match[1]);
  }

  getExplorerAddressURL(address: string) {
    return `${this.#data.explorerURL}/address/${address}`;
  }

  getExplorerBlockURL(blockNumber: number) {
    return `${this.#data.explorerURL}/block/${blockNumber}`;
  }

  getExplorerTxURL(transactionHash: HexStrPrefixed) {
    return `${this.#data.explorerURL}/tx/${transactionHash}`;
  }

  #shortenAddress(address: Address) {
    return `${address.slice(0, 8)}..${address.slice(-8)}`;
  }
}
