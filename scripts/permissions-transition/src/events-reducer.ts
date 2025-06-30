import bytes, { HexStrPrefixed, Address } from "./bytes";
import { DecodedEvent } from "./events-collector";
import { ZERO_ADDRESS, ZERO_HASH } from "./utils";

export interface AragonPermissionsSnapshot {
  [contractAddress: Address]: {
    [roleHash: HexStrPrefixed]: {
      roleManager: Address | null;
      grantedTo: { address: Address; paramsHash: HexStrPrefixed | null }[];
    };
  };
}

export interface OZPermissionsSnapshot {
  [contractAddress: Address]: {
    [roleHash: HexStrPrefixed]: { roleAdmin: Address; grantedTo: Address[] };
  };
}

export interface PermissionsSnapshot {
  snapshotBlockNumber: number;
  lastProcessedBlockNumber: number;
  lastProcessedTransactionHash: HexStrPrefixed | null;
  aragon: AragonPermissionsSnapshot;
  oz: OZPermissionsSnapshot;
}

export class EventsReducer {
  #aragon: AragonPermissionsSnapshot = {};
  #oz: OZPermissionsSnapshot = {};

  #snapshotBlockNumber: number = 0;
  #lastProcessedBlockNumber: number = 0;
  #lastProcessedTransactionIndex: number = 0;
  #lastProcessedLogIndex: number = 0;
  #lastProcessedTransactionHash: HexStrPrefixed | null = null;

  constructor(snapshotBlockNumber: number) {
    this.#snapshotBlockNumber = snapshotBlockNumber;
  }

  #touchAragonRole(app: Address, role: HexStrPrefixed) {
    if (!this.#aragon[app]) {
      this.#aragon[app] = {};
    }
    if (!this.#aragon[app][role]) {
      this.#aragon[app][role] = { roleManager: null, grantedTo: [] };
    }
  }

  #setAragonManager(app: Address, role: HexStrPrefixed, manager: Address) {
    this.#touchAragonRole(app, role);
    if (manager === ZERO_ADDRESS) {
      this.#aragon[app][role].roleManager = null;
    } else {
      this.#aragon[app][role].roleManager = manager;
    }
  }

  #grantAragonPermission(entity: Address, app: Address, role: HexStrPrefixed) {
    this.#touchAragonRole(app, role);
    // ACL contract allows to rewrite permission & params without revoking it
    const isPermissionGrantedBefore = this.#aragon[app][role].grantedTo.some((grantee) => grantee.address === entity);
    if (isPermissionGrantedBefore) {
      this.#revokeAragonPermission(entity, app, role);
    }
    this.#aragon[app][role].grantedTo.push({ address: entity, paramsHash: null });
  }

  #revokeAragonPermission(entity: Address, app: Address, role: HexStrPrefixed) {
    this.#touchAragonRole(app, role);
    // ACL doesn't check if the permission was granted earlier, so doesn't check that
    // permission was granted earlier
    this.#aragon[app][role].grantedTo = this.#aragon[app][role].grantedTo.filter(
      (grantee) => grantee.address !== entity
    );
  }

  #setAragonPermissionParams(entity: Address, app: Address, role: HexStrPrefixed, paramsHash: HexStrPrefixed) {
    // SetPermissionParams emits ONLY after SetPermission event, so in correct events chain
    // entity MUST already be registered in the state
    const grantee = this.#aragon[app][role].grantedTo.find((grantee) => grantee.address === entity);
    if (!grantee) {
      throw new Error(`Invalid events chain. SetPermissionParams on role ${role} for unregistered entity ${entity}`);
    }
    grantee.paramsHash = paramsHash;
  }

  #touchOZRole(app: Address, role: HexStrPrefixed) {
    if (!this.#oz[app]) {
      this.#oz[app] = {};
    }
    if (!this.#oz[app][role]) {
      this.#oz[app][role] = { roleAdmin: bytes.normalize(ZERO_HASH), grantedTo: [] };
    }
  }

  #grantOZRole(entity: Address, app: Address, role: HexStrPrefixed) {
    this.#touchOZRole(app, role);
    if (this.#oz[app][role].grantedTo.includes(entity)) {
      throw new Error(`Invalid events chain. OZ role ${role} was granted to ${entity} second time`);
    }
    this.#oz[app][role].grantedTo.push(entity);
  }

  #revokeOZRole(entity: Address, app: Address, role: HexStrPrefixed) {
    this.#touchOZRole(app, role);
    if (!this.#oz[app][role].grantedTo.includes(entity)) {
      throw new Error(`Invalid events chain. OZ role ${role} was revoked from ${entity} without granting`);
    }
    this.#oz[app][role].grantedTo = this.#oz[app][role].grantedTo.filter((grantee) => grantee !== entity);
  }

  #changeOZRoleAdmin(newRoleAdmin: HexStrPrefixed, app: Address, role: HexStrPrefixed) {
    this.#touchOZRole(app, role);
    this.#oz[app][role].roleAdmin = newRoleAdmin;
  }

  process(event: DecodedEvent) {
    if (event.blockNumber < this.#lastProcessedBlockNumber) {
      throw new Error(
        `Invalid events chain. New block number ${event.blockNumber} less than lass processed ${
          this.#lastProcessedBlockNumber
        }`
      );
    } else if (event.blockNumber === this.#lastProcessedBlockNumber) {
      if (event.transactionIndex < this.#lastProcessedTransactionIndex) {
        throw new Error(
          `Invalid events chain. New tx index ${event.transactionIndex} less than lass processed ${
            this.#lastProcessedTransactionIndex
          }`
        );
      } else if (event.transactionIndex === this.#lastProcessedTransactionIndex) {
        if (event.logIndex < this.#lastProcessedLogIndex) {
          throw new Error(
            `Invalid events chain. New log index ${event.logIndex} less than lass processed ${
              this.#lastProcessedLogIndex
            }`
          );
        }
      }
    }

    const eventName = event.name;
    if (eventName === "ChangePermissionManager") {
      const { app, role, manager } = event.args;
      this.#setAragonManager(app, role, manager);
    } else if (eventName === "SetPermission") {
      const { entity, app, role, allowed } = event.args;
      if (allowed) {
        this.#grantAragonPermission(entity, app, role);
      } else {
        this.#revokeAragonPermission(entity, app, role);
      }
    } else if (eventName === "SetPermissionParams") {
      const { entity, app, role, paramsHash } = event.args;
      this.#setAragonPermissionParams(entity, app, role, paramsHash);
    } else if (eventName === "RoleGranted") {
      const { account, role } = event.args;
      this.#grantOZRole(account, event.address, role);
    } else if (eventName === "RoleRevoked") {
      const { account, role } = event.args;
      this.#revokeOZRole(account, event.address, role);
    } else if (eventName === "RoleAdminChanged") {
      const { role, newAdminRole } = event.args;
      this.#changeOZRoleAdmin(newAdminRole, event.address, role);
    } else {
      throw Error(`Unexpected event ${event.name}`);
    }

    this.#lastProcessedBlockNumber = event.blockNumber;
    this.#lastProcessedLogIndex = event.logIndex;
    this.#lastProcessedTransactionIndex = event.transactionIndex;
    this.#lastProcessedTransactionHash = event.transactionHash;
  }

  getSnapshot(): PermissionsSnapshot {
    return {
      lastProcessedBlockNumber: this.#lastProcessedBlockNumber,
      lastProcessedTransactionHash: this.#lastProcessedTransactionHash,
      snapshotBlockNumber: this.#snapshotBlockNumber,
      aragon: { ...this.#aragon },
      oz: { ...this.#oz },
    };
  }
}
