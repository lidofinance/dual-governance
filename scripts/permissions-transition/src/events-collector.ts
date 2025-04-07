import { JsonRpcProvider, Log } from "ethers";
import bytes, { Address, HexStrPrefixed } from "./bytes";
import { decodeAddress, decodeBool, decodeBytes32 } from "./utils";

interface LogItem {
  address: Address;
  topics: HexStrPrefixed[];
  data: HexStrPrefixed;
  blockNumber: number;
  transactionHash: HexStrPrefixed;
  transactionIndex: number;
  blockHash: HexStrPrefixed;
  logIndex: number;
  removed: boolean;
}

export interface DecodedEvent extends LogItem {
  name: string;
  args: Record<string, any>;
}

interface FilterRange {
  fromBlock?: number;
  toBlock?: number;
}

// keccak256("SetPermission(address,address,bytes32,bool)")
const ARAGON_SET_PERMISSION_TOPIC: HexStrPrefixed =
  "0x759b9a74d5354b5801710a0c1b283cc9f0d32b607ac8ced10c83ac8e75c77d52";

// keccak256("SetPermissionParams(address,address,bytes32,bytes32)")
const ARAGON_SET_PERMISSION_PARAMS_TOPIC: HexStrPrefixed =
  "0x8dfee25d92d73b8c9b868f9fa3e215cc1981033f426e53803e3da4f09a2cfc30";

// keccak256("ChangePermissionManager(address,bytes32,address)")
const ARAGON_CHANGE_PERMISSION_MANAGER_TOPIC: HexStrPrefixed =
  "0xf3addc8b8e25ee11528a61b0e65092cae0666ef0ec0c64cb303993c88d689b4d";

// keccak256("RoleGranted(bytes32,address,address)")
const OZ_ROLE_GRANTED_TOPIC: HexStrPrefixed = "0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d";

// keccak256("RoleRevoked(bytes32,address,address)")
const OZ_ROLE_REVOKED_TOPIC: HexStrPrefixed = "0xf6391f5c32d9c69d2a47ea670b442974b53935d1edc7fd64eb21e047a839171b";

// keccak256("RoleAdminChanged(bytes32,bytes32,bytes32)")
const OZ_ROLE_ADMIN_CHANGED_TOPIC: HexStrPrefixed =
  "0xbd79b86ffe0ab8e8776151514217cd7cacd52c909f66475c3af44e129f0b00ff";

export class EventsCollector {
  #aragonACL: Address;
  #ozContracts: Address[];
  #provider: JsonRpcProvider;

  constructor(provider: JsonRpcProvider, aragonACL: Address, ozContracts: Address[]) {
    this.#provider = provider;
    this.#aragonACL = aragonACL;
    this.#ozContracts = ozContracts;
  }

  async collect(filterRange: FilterRange): Promise<DecodedEvent[]> {
    const fetchedLogItems: LogItem[] = [];

    console.log(`Fetching Aragon ACL ${this.#aragonACL} events...`);
    const [setPermissionLogs, setPermissionParamsLogs, changePermissionManagerLogs] = await Promise.all([
      this.#fetchLogs(this.#aragonACL, ARAGON_SET_PERMISSION_TOPIC, filterRange),
      this.#fetchLogs(this.#aragonACL, ARAGON_SET_PERMISSION_PARAMS_TOPIC, filterRange),
      this.#fetchLogs(this.#aragonACL, ARAGON_CHANGE_PERMISSION_MANAGER_TOPIC, filterRange),
    ]);

    fetchedLogItems.push(...setPermissionLogs, ...setPermissionParamsLogs, ...changePermissionManagerLogs);

    for (let ozContractAddress of this.#ozContracts) {
      console.log(`Fetching OZ events for contract ${ozContractAddress}...`);
      const [grantRoleLogs, revokeRoleLogs, roleAdminChangedLogs] = await Promise.all([
        this.#fetchLogs(ozContractAddress, OZ_ROLE_GRANTED_TOPIC, filterRange),
        this.#fetchLogs(ozContractAddress, OZ_ROLE_REVOKED_TOPIC, filterRange),
        this.#fetchLogs(ozContractAddress, OZ_ROLE_ADMIN_CHANGED_TOPIC, filterRange),
      ]);
      fetchedLogItems.push(...grantRoleLogs, ...revokeRoleLogs, ...roleAdminChangedLogs);
    }

    return this.#sortLogs(fetchedLogItems).map((logItem) => this.#decodeLogItem(logItem));
  }

  #decodeLogItem(logItem: LogItem): DecodedEvent {
    if (logItem.topics[0] === ARAGON_SET_PERMISSION_TOPIC) {
      return {
        ...logItem,
        name: "SetPermission",
        args: {
          entity: decodeAddress(logItem.topics[1]),
          app: decodeAddress(logItem.topics[2]),
          role: decodeBytes32(logItem.topics[3]),
          allowed: decodeBool(logItem.data),
        },
      };
    } else if (logItem.topics[0] === ARAGON_SET_PERMISSION_PARAMS_TOPIC) {
      return {
        ...logItem,
        name: "SetPermissionParams",
        args: {
          entity: decodeAddress(logItem.topics[1]),
          app: decodeAddress(logItem.topics[2]),
          role: decodeBytes32(logItem.topics[3]),
          paramsHash: decodeBytes32(logItem.data),
        },
      };
    } else if (logItem.topics[0] === ARAGON_CHANGE_PERMISSION_MANAGER_TOPIC) {
      return {
        ...logItem,
        name: "ChangePermissionManager",
        args: {
          app: decodeAddress(logItem.topics[1]),
          role: decodeBytes32(logItem.topics[2]),
          manager: decodeAddress(logItem.topics[3]),
        },
      };
    } else if (logItem.topics[0] === OZ_ROLE_ADMIN_CHANGED_TOPIC) {
      return {
        ...logItem,
        name: "RoleAdminChanged",
        args: {
          role: logItem.topics[1],
          previousAdminRole: logItem.topics[2],
          newAdminRole: logItem.topics[3],
        },
      };
    } else if (logItem.topics[0] === OZ_ROLE_GRANTED_TOPIC || logItem.topics[0] === OZ_ROLE_REVOKED_TOPIC) {
      return {
        ...logItem,
        name: logItem.topics[0] === OZ_ROLE_GRANTED_TOPIC ? "RoleGranted" : "RoleRevoked",
        args: {
          role: logItem.topics[1],
          account: decodeAddress(logItem.topics[2]),
          sender: decodeAddress(logItem.topics[3]),
        },
      };
    } else {
      throw new Error(`Unexpected event topic ${logItem.topics[0]}`);
    }
  }

  async #fetchLogs(address: Address, topic: HexStrPrefixed, filterRange: FilterRange = {}): Promise<LogItem[]> {
    const logs = await this.#provider.getLogs({
      address,
      fromBlock: filterRange.fromBlock,
      toBlock: filterRange.toBlock,
      topics: [topic],
    });

    return logs.map((logItem: Log) => ({
      blockHash: bytes.normalize(logItem.blockHash),
      blockNumber: logItem.blockNumber,
      transactionIndex: logItem.transactionIndex,
      address: bytes.normalize(logItem.address),
      logIndex: logItem.index,
      data: bytes.normalize(logItem.data),
      removed: logItem.removed,
      topics: logItem.topics.map((topic: string) => bytes.normalize(topic)),
      transactionHash: bytes.normalize(logItem.transactionHash),
    }));
  }

  #sortLogs(logs: LogItem[]) {
    return logs.sort((a, b) => {
      if (a.blockNumber !== b.blockNumber) {
        return a.blockNumber - b.blockNumber; // Sort by block number
      }
      return a.logIndex - b.logIndex; // Sort by log index
    });
  }
}
