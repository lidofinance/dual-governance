# Protocol permissions transition due to Dual Governance upgrade

## Abstract

Dual Governance protects stETH holders from the Lido DAO abusing the smart contract roles and permissions across Lido on Ethereum protocol. In order to achieve that, some / most roles would need to get transitioned "under DG control". The document aims to:
- provide the necessary context;
- outline the transition plan;
- highlight a couple specific details about the plan:
    - edge-cases where the plan enacted would wreak existing operations;
    - specific roles / permissions which need to stay on DAO.

## Context to how the roles are structured now

Most roles under Lido DAO management are granted to:

1. Aragon **Voting** contract;
2. Aragon **Agent** contract (actions on behalf of Aragon Agent require a role for `Agent.forward`, currently granted only to Aragon Voting contract, actions from that requires the LDO vote);
3. **EVMScriptExecutor** — part of Easy Track mechanism, does payments from Aragon Agent (i.e. Treasury), has the role to "set limits for curated module", has the role management rights for SDVT and the role to settle penalties for CSM;
4. committees: multisigs and GateSeals, having the roles and permissions necessary to perform day to day functions (directly or through Easy Track).

There are multiple "control mechanics" employed by Lido on Ethereum contracts:

- **Aragon's permissions (ACL)**: Managed by the Aragon Access Control List (ACL) contract, this system provides a granular permission model within the Aragon app. The main role unlocking ACL management is `CREATE_PERMISSIONS_ROLE`, assigned to Voting contract. The entity holding this role has ultimate power over the all unassigned ACL roles in Lido Aragon Apps (i.e. Voting, Agent, Lido, Oracle and other "core" contracts based on Aragon framework). To assign any role one needs to first define role manager address; any actions with the role once the manager is defined can be done only by this manager address;
- **OpenZeppelin's access control**: This is a role-based access control mechanism provided by the OpenZeppelin library. Roles are defined and granted individually on a per-contract basis. Contracts with OZ role model have "role admin" mechanics: the roles are managed by "role admin" ("default admin" if there's no admin address assigned as specific role admin). Role admin can be queried by calling `getRoleAdmin` method on the contract;
- **Unassigned roles**: Some existing roles may intentionally not be assigned to any entity. This means that, by default, no one has the authority to perform actions associated with these roles unless the DAO explicitly grants the permission through a governance proposal;
- **Aragon ownerships**: these ownerships are managed through the Kernel contract. The Kernel allows the DAO to setup/update applications (by calling `setApp`) and keeps them under its control, while access to these apps is managed through the ACL;
- **Ownable contracts**: Some contracts within the Lido protocol use the Ownable pattern, where a single owner address has exclusive access to certain administrative functions;
- **EthereumGovernanceExecutor** field on L2 parts employing "governance forwarding" — checked it's set to Aragon Agent everywhere;
- **Immutable variables**: There are some contracts that contain immutable variables referring to the DAO contracts. Such as Stonks (contains immutable agent address) and Burner (contains immutable treasury address).

## The transition plan

Goal is to protect the "potentially dangerous for steth" roles and permissions by Dual Governance.

The requirements / constraints / "plan design goals" are:
- do a transition in sane, graspable way;
- maintain business continuity (don't break the flows necessary for day to day protocol and DAO operations);
- have a way to check for completeness.

Thus, the plan goes like this:
1. Aragon Voting passes all the roles (except treasury management, insurance fund and all roles related to Voting and TokenManager contracts) and ownerships to Aragon Agent;
2. Aragon Agent:
    1. Grants a role for `Agent.forward` to Dual Governance Executor contract;
    2. Revokes a role for `Agent.forward` from Voting;
3. EVMScriptExecutor/EasyTrack remains as-is (Voting is owner of EVMScriptExecutor and holder of `DEFAULT_ADMIN_ROLE` for EasyTrack, but given Voting isn't role manager / admin on things which need to be under DG — Voting can't grant permissions necessary to breach "DG protection");
4. Committees remain as-is to maintain business continuity;
5. Immutable variables remain as-is until future updates;
6. All EasyTrack factories remain as-is until future updates.

The role-by-role list of actions to be taken is outlined [below](#role-listing-script-output).

## Highlights and exceptions

- ACL's `CREATE_PERMISSION_ROLE` goes to Agent, that means **creating new roles** should go through the Dual Governance what **will take longer to execute**;
- roles necessary for **pausing** for critical contracts (particularly `PAUSE_ROLE` for Lido/stETH contract) are **considered to be moved to Agent** so it leads to slower decision making in critical situations. Sealable roles with no time limitation remain on the Agent and ResealManager;
- EasyTrack "parts" (`AllowedRecipientsRegistry` ownership) are proposed to stay on Agent to not to overcomplicate the DG "switch on" vote (can be managed outside of DG deployment, if operationally possible; that's ~32-actions-worth vote);
- roles necessary for EasyTrack motions for Curated NOs to add keys remain without changes;
- roles necessary for EasyTrack motions for SDVT management remain without changes;
- roles necessary for EasyTrack motions for CSM penalty management remains without changes;
- all the roles across Lido on Ethereum contracts are managed by `DEFAULT_ADMIN` (Agent); only EasyTrack has `DEFAULT_ADMIN` set to Voting contract;
- at the moment Aragon app does have additional ACL and Kernel contracts for repos (PM repo, Oracle repo, etc.) to support Aragon UI. It is [decided](https://research.lido.fi/t/discontinuation-of-aragon-ui-use/7992) to drop support of these contracts (leave them as is);
- all L2 bridges refer to Agent contract as a manager/owner so it remains without changes.

### Impact of the rights getting transferred to DG

Practical effect of moving the role under DG is
1) in general, activating / performing any action requiring this role takes longer (LDO governance time + DG default timelock (about 3-4 days per the current proposed params));
2) if DG veto escrow crosses the first threshold (veto signalling, 1% steth TVL opposes the motion), the timelock becomes dynamic (it's [limited](https://github.com/lidofinance/dual-governance/blob/831ad62bca6913dbfbb56bb341feb8588b349ebe/docs/mechanism.md#veto-signalling-state) during the VetoSignalling state, and [unpredictably long](https://github.com/lidofinance/dual-governance/blob/831ad62bca6913dbfbb56bb341feb8588b349ebe/docs/mechanism.md#rage-quit-state) during the RageQuit state).

Another important thing to consider: some mechanics in the protocol rely upon "LDO governance reaction time"; the obvious examples are GateSeals (have specific treatment under DG), non-obvious is [`FINALIZATION_MAX_NEGATIVE_REBASE_EPOCH_SHIFT`](https://docs.lido.fi/guides/oracle-spec/accounting-oracle/#negative-rebase-border) OracleReportSanityChecker param. To the best of value stream tech teams' knowledge, those are the only two examples with implicit dependancy on DAO's reaction time.

## Context and full roles list / things to look up

In order to collect the full roles and permissions list, the team has created the [script](https://github.com/lidofinance/dual-governance/pull/226) based on acceptance tests being run on every vote.

The script: 1) collects the roles set as-is; 2) compares the status with the "desired" one set in config; 3) prints the `.md` file based on comparison.

Note: there's a full-blown ["role model research"](https://github.com/lidofinance/audits/blob/main/Statemind%20Lido%20roles%20analysis%2010-2023.pdf) brought up by Statemind. It doesn't account for the latest changes from SR+CSM upgrade, new Multichain deployments and multisigs/committees, but list most of the roles with deeper context.

"Action items" for the "DG switching on" vote based on the outlined plan are listed below.

### Role listing script output

Note: If an item is highlighted in bold with ⚠️ icon, it means that this item will be performed.

### Aragon roles (21 roles modified)

#### [ACL](https://etherscan.io/address/0x9895f0f17cc1d1891b6f18ee0b483b6f221b37bb)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **`CREATE_PERMISSIONS_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ⚠️ **`Agent`** |

#### [DAOKernel](https://etherscan.io/address/0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **`APP_MANAGER_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ∅ |

#### [Lido](https://etherscan.io/address/0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **`STAKING_CONTROL_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ∅ |
| ⚠️ **`RESUME_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ∅ |
| ⚠️ **`PAUSE_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ∅ |
| ⚠️ **`STAKING_PAUSE_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ∅ |
| UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE | ∅ | ∅ | ∅ |

#### [Agent](https://etherscan.io/address/0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **`RUN_SCRIPT_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ⚠️ **`DualGovernanceExecutor`** |
| ⚠️ **`EXECUTE_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ⚠️ **`DualGovernanceExecutor`** |
| TRANSFER_ROLE | Voting | ∅ | Finance |
| SAFE_EXECUTE_ROLE | ∅ | ∅ | ∅ |
| DESIGNATE_SIGNER_ROLE | ∅ | ∅ | ∅ |
| ADD_PRESIGNED_HASH_ROLE | ∅ | ∅ | ∅ |
| ADD_PROTECTED_TOKEN_ROLE | ∅ | ∅ | ∅ |
| REMOVE_PROTECTED_TOKEN_ROLE | ∅ | ∅ | ∅ |

#### [CuratedModule](https://etherscan.io/address/0x55032650b14df07b85bF18A3a3eC8E0Af2e028d5)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **`STAKING_ROUTER_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ∅ | StakingRouter |
| ⚠️ **`MANAGE_NODE_OPERATOR_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ∅ | Agent |
| ⚠️ **`SET_NODE_OPERATOR_LIMIT_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | EasyTrackEvmScriptExecutor |
| ⚠️ **`MANAGE_SIGNING_KEYS`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ∅ |

#### [SimpleDVT](https://etherscan.io/address/0xaE7B191A31f627b4eB1d4DaC64eaB9976995b433)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **`STAKING_ROUTER_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ∅ | StakingRouter, EasyTrackEvmScriptExecutor |
| ⚠️ **`MANAGE_NODE_OPERATOR_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ∅ | EasyTrackEvmScriptExecutor |
| ⚠️ **`SET_NODE_OPERATOR_LIMIT_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ∅ | EasyTrackEvmScriptExecutor |
| MANAGE_SIGNING_KEYS | EasyTrackEvmScriptExecutor | ∅ | EasyTrackEvmScriptExecutor, +67 SDVT holders |

#### [Finance](https://etherscan.io/address/0xB9E5CBB9CA5b0d659238807E84D0176930753d86)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **`CHANGE_PERIOD_ROLE`** | ⚠️ **`∅ ➡️ Voting`** | ∅ | ∅ |
| ⚠️ **`CHANGE_BUDGETS_ROLE`** | ⚠️ **`∅ ➡️ Voting`** | ∅ | ∅ |
| CREATE_PAYMENTS_ROLE | Voting | ∅ | Voting, EasyTrackEvmScriptExecutor |
| EXECUTE_PAYMENTS_ROLE | Voting | ∅ | Voting |
| MANAGE_PAYMENTS_ROLE | Voting | ∅ | Voting |

#### [TokenManager](https://etherscan.io/address/0xf73a1260d222f447210581DDf212D915c09a3249)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **`MINT_ROLE`** | ⚠️ **`∅ ➡️ Voting`** | ∅ | ∅ |
| ⚠️ **`REVOKE_VESTINGS_ROLE`** | ⚠️ **`∅ ➡️ Voting`** | ∅ | ∅ |
| ISSUE_ROLE | Voting | ∅ | ∅ |
| ASSIGN_ROLE | Voting | ∅ | Voting |
| BURN_ROLE | Voting | ∅ | ∅ |

#### [EVMScriptRegistry](https://etherscan.io/address/0x853cc0D5917f49B57B8e9F89e491F5E18919093A)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **`REGISTRY_ADD_EXECUTOR_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ∅ |
| ⚠️ **`REGISTRY_MANAGER_ROLE`** | ⚠️ **`Voting ➡️ Agent`** | ⚠️ **`Voting`** | ∅ |

### Not affected contracts

<details>

#### [Voting](https://etherscan.io/address/0x2e59A20f205bB85a89C53f1936454680651E618e)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| UNSAFELY_MODIFY_VOTE_TIME_ROLE | Voting | ∅ | ∅ |
| MODIFY_QUORUM_ROLE | Voting | ∅ | Voting |
| MODIFY_SUPPORT_ROLE | Voting | ∅ | Voting |
| CREATE_VOTES_ROLE | Voting | ∅ | TokenManager |</details>

#### [VotingRepo](https://etherscan.io/address/0x4ee3118e3858e8d7164a634825bfe0f73d99c792)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ∅ | ∅ | ∅ |


#### [LidoRepo](https://etherscan.io/address/0xF5Dc67E54FC96F993CD06073f71ca732C1E654B1)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ∅ | ∅ | ∅ |


#### [LegacyOracleRepo](https://etherscan.io/address/0xF9339DE629973c60c4d2b76749c81E6F40960E3A)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ∅ | ∅ | ∅ |


#### [CuratedModuleRepo](https://etherscan.io/address/0x0D97E876ad14DB2b183CFeEB8aa1A5C788eB1831)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ∅ | ∅ | ∅ |


#### [SimpleDVTRepo](https://etherscan.io/address/0x2325b0a607808dE42D918DB07F925FFcCfBb2968)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ∅ | ∅ | ∅ |

#### [AragonPM](https://etherscan.io/address/0x0cb113890b04b49455dfe06554e2d784598a29c9)

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_REPO_ROLE | ∅ | ∅ | ∅ |

</details>

### OpenZeppelin (3 roles modified)

#### [AllowedTokensRegistry](https://etherscan.io/address/0x4AC40c34f8992bb1e5E856A448792158022551ca)

| Role | Revoked | Granted |
| --- | --- | --- |
| ⚠️ **`DEFAULT_ADMIN_ROLE`** | ⚠️ **`Agent`** | ⚠️ **`Voting`** |
| ⚠️ **`ADD_TOKEN_TO_ALLOWED_LIST_ROLE`** | ⚠️ **`Agent`** | ⚠️ **`Voting`** |
| ⚠️ **`REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE`** | ⚠️ **`Agent`** | ⚠️ **`Voting`** |

### Not affected contracts

<details>

#### [StakingRouter](https://etherscan.io/address/0xFdDf38947aFB03C621C71b06C9C70bce73f12999)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| MANAGE_WITHDRAWAL_CREDENTIALS_ROLE | ∅ | ∅ |
| REPORT_EXITED_VALIDATORS_ROLE | ∅ | AccountingOracle |
| REPORT_REWARDS_MINTED_ROLE | ∅ | Lido |
| STAKING_MODULE_MANAGE_ROLE | ∅ | Agent |
| STAKING_MODULE_UNVETTING_ROLE | ∅ | DepositSecurityModule |
| UNSAFE_SET_EXITED_VALIDATORS_ROLE | ∅ | ∅ |

#### [WithdrawalQueueERC721](https://etherscan.io/address/0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| FINALIZE_ROLE | ∅ | Lido |
| MANAGE_TOKEN_URI_ROLE | ∅ | ∅ |
| ORACLE_ROLE | ∅ | AccountingOracle |
| PAUSE_ROLE | ∅ | OraclesGateSeal |
| RESUME_ROLE | ∅ | ∅ |

#### [Burner](https://etherscan.io/address/0xD15a672319Cf0352560eE76d9e89eAB0889046D3)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| REQUEST_BURN_MY_STETH_ROLE | ∅ | Agent |
| REQUEST_BURN_SHARES_ROLE | ∅ | Lido, CuratedModule, SimpleDVT, CSAccounting |

#### [AccountingOracle](https://etherscan.io/address/0x852deD011285fe67063a08005c71a85690503Cee)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| MANAGE_CONSENSUS_CONTRACT_ROLE | ∅ | ∅ |
| MANAGE_CONSENSUS_VERSION_ROLE | ∅ | ∅ |
| SUBMIT_DATA_ROLE | ∅ | ∅ |

#### [AccountingOracleHashConsensus](https://etherscan.io/address/0xD624B08C83bAECF0807Dd2c6880C3154a5F0B288)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DISABLE_CONSENSUS_ROLE | ∅ | ∅ |
| MANAGE_FAST_LANE_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_FRAME_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_MEMBERS_AND_QUORUM_ROLE | ∅ | Agent |
| MANAGE_REPORT_PROCESSOR_ROLE | ∅ | ∅ |

#### [ValidatorExitBusOracle](https://etherscan.io/address/0x0De4Ea0184c2ad0BacA7183356Aea5B8d5Bf5c6e)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| MANAGE_CONSENSUS_CONTRACT_ROLE | ∅ | ∅ |
| MANAGE_CONSENSUS_VERSION_ROLE | ∅ | ∅ |
| PAUSE_ROLE | ∅ | OraclesGateSeal |
| RESUME_ROLE | ∅ | ∅ |
| SUBMIT_DATA_ROLE | ∅ | ∅ |

#### [ValidatorExitBusHashConsensus](https://etherscan.io/address/0x7FaDB6358950c5fAA66Cb5EB8eE5147De3df355a)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DISABLE_CONSENSUS_ROLE | ∅ | ∅ |
| MANAGE_FAST_LANE_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_FRAME_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_MEMBERS_AND_QUORUM_ROLE | ∅ | Agent |
| MANAGE_REPORT_PROCESSOR_ROLE | ∅ | ∅ |

#### [OracleReportSanityChecker](https://etherscan.io/address/0x6232397ebac4f5772e53285B26c47914E9461E75)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| ALL_LIMITS_MANAGER_ROLE | ∅ | ∅ |
| ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE | ∅ | ∅ |
| APPEARED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE | ∅ | ∅ |
| EXITED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE | ∅ | ∅ |
| INITIAL_SLASHING_AND_PENALTIES_MANAGER_ROLE | ∅ | ∅ |
| MAX_ITEMS_PER_EXTRA_DATA_TRANSACTION_ROLE | ∅ | ∅ |
| MAX_NODE_OPERATORS_PER_EXTRA_DATA_ITEM_ROLE | ∅ | ∅ |
| MAX_POSITIVE_TOKEN_REBASE_MANAGER_ROLE | ∅ | ∅ |
| MAX_VALIDATOR_EXIT_REQUESTS_PER_REPORT_ROLE | ∅ | ∅ |
| REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE | ∅ | ∅ |
| SECOND_OPINION_MANAGER_ROLE | ∅ | ∅ |
| SHARE_RATE_DEVIATION_LIMIT_MANAGER_ROLE | ∅ | ∅ |

#### [OracleDaemonConfig](https://etherscan.io/address/0xbf05A929c3D7885a6aeAd833a992dA6E5ac23b09)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| CONFIG_MANAGER_ROLE | ∅ | ∅ |

#### [CSModule](https://etherscan.io/address/0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| MODULE_MANAGER_ROLE | ∅ | ∅ |
| PAUSE_ROLE | ∅ | CSGateSeal |
| RECOVERER_ROLE | ∅ | ∅ |
| REPORT_EL_REWARDS_STEALING_PENALTY_ROLE | ∅ | CSCommitteeMultisig |
| RESUME_ROLE | ∅ | ∅ |
| SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE | ∅ | EasyTrackEvmScriptExecutor |
| STAKING_ROUTER_ROLE | ∅ | StakingRouter |
| VERIFIER_ROLE | ∅ | CSVerifier |

#### [CSAccounting](https://etherscan.io/address/0x4d72BFF1BeaC69925F8Bd12526a39BAAb069e5Da)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| ACCOUNTING_MANAGER_ROLE | ∅ | ∅ |
| MANAGE_BOND_CURVES_ROLE | ∅ | ∅ |
| PAUSE_ROLE | ∅ | CSGateSeal |
| RECOVERER_ROLE | ∅ | ∅ |
| RESET_BOND_CURVE_ROLE | ∅ | CSModule, CSCommitteeMultisig |
| RESUME_ROLE | ∅ | ∅ |
| SET_BOND_CURVE_ROLE | ∅ | CSModule, CSCommitteeMultisig |

#### [CSFeeDistributor](https://etherscan.io/address/0xD99CC66fEC647E68294C6477B40fC7E0F6F618D0)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| RECOVERER_ROLE | ∅ | ∅ |

#### [CSFeeOracle](https://etherscan.io/address/0x4D4074628678Bd302921c20573EEa1ed38DdF7FB)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| CONTRACT_MANAGER_ROLE | ∅ | ∅ |
| MANAGE_CONSENSUS_CONTRACT_ROLE | ∅ | ∅ |
| MANAGE_CONSENSUS_VERSION_ROLE | ∅ | ∅ |
| PAUSE_ROLE | ∅ | CSGateSeal |
| RECOVERER_ROLE | ∅ | ∅ |
| RESUME_ROLE | ∅ | ∅ |
| SUBMIT_DATA_ROLE | ∅ | ∅ |

#### [CSHashConsensus](https://etherscan.io/address/0x71093efF8D8599b5fA340D665Ad60fA7C80688e4)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DISABLE_CONSENSUS_ROLE | ∅ | ∅ |
| MANAGE_FAST_LANE_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_FRAME_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_MEMBERS_AND_QUORUM_ROLE | ∅ | Agent |
| MANAGE_REPORT_PROCESSOR_ROLE | ∅ | ∅ |

#### [EasyTrack](https://etherscan.io/address/0xF0211b7660680B49De1A7E9f25C65660F0a13Fea)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Voting |
| CANCEL_ROLE | ∅ | Voting |
| PAUSE_ROLE | ∅ | Voting, EmergencyBrakesMultisig |
| UNPAUSE_ROLE | ∅ | Voting |

#### [L1ERC20TokenGateway_Arbitrum](https://etherscan.io/address/0x0F25c1DC2a9922304f2eac71DCa9B07E310e8E5a)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DEPOSITS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| DEPOSITS_ENABLER_ROLE | ∅ | Agent |
| WITHDRAWALS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| WITHDRAWALS_ENABLER_ROLE | ∅ | Agent |

#### [L1TokensBridge_Optimism](https://etherscan.io/address/0x76943C0D61395d8F2edF9060e1533529cAe05dE6)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DEPOSITS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| DEPOSITS_ENABLER_ROLE | ∅ | Agent |
| WITHDRAWALS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| WITHDRAWALS_ENABLER_ROLE | ∅ | Agent |

#### [ERC20Predicate_Polygon](https://etherscan.io/address/0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | ∅ |
| MANAGER_ROLE | ∅ | ∅ |

#### [L1ERC20TokenBridge_Base](https://etherscan.io/address/0x9de443AdC5A411E83F1878Ef24C3F52C61571e72)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DEPOSITS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| DEPOSITS_ENABLER_ROLE | ∅ | Agent |
| WITHDRAWALS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| WITHDRAWALS_ENABLER_ROLE | ∅ | Agent |

#### [L1ERC20Bridge_zkSync](https://etherscan.io/address/0x41527B2d03844dB6b0945f25702cB958b6d55989)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DEPOSITS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| DEPOSITS_ENABLER_ROLE | ∅ | Agent |
| WITHDRAWALS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| WITHDRAWALS_ENABLER_ROLE | ∅ | Agent |

#### [L1ERC20TokenBridge_Mantle](https://etherscan.io/address/0x2D001d79E5aF5F65a939781FE228B267a8Ed468B)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DEPOSITS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| DEPOSITS_ENABLER_ROLE | ∅ | Agent |
| WITHDRAWALS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| WITHDRAWALS_ENABLER_ROLE | ∅ | Agent |

#### [L1LidoGateway_Scroll](https://etherscan.io/address/0x6625c6332c9f91f2d27c304e729b86db87a3f504)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEPOSITS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| DEPOSITS_ENABLER_ROLE | ∅ | Agent |
| WITHDRAWALS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| WITHDRAWALS_ENABLER_ROLE | ∅ | Agent |

#### [L1ERC20TokenBridge_Mode](https://etherscan.io/address/0xD0DeA0a3bd8E4D55170943129c025d3fe0493F2A)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DEPOSITS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| DEPOSITS_ENABLER_ROLE | ∅ | Agent |
| WITHDRAWALS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| WITHDRAWALS_ENABLER_ROLE | ∅ | Agent |

#### [L1ERC20TokenBridge_Zircuit](https://etherscan.io/address/0x912C7271a6A3622dfb8B218eb46a6122aB046C79)

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | Agent |
| DEPOSITS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| DEPOSITS_ENABLER_ROLE | ∅ | Agent |
| WITHDRAWALS_DISABLER_ROLE | ∅ | Agent, EmergencyBrakesMultisig |
| WITHDRAWALS_ENABLER_ROLE | ∅ | Agent |

</details>

### Managed Contracts Updates (2 owners modified)

| Contract | Property | Old Manager | New Manager |
| --- | --- | --- | --- |
| DSM | getOwner() | Agent | Agent |
| LidoLocator :: Proxy | proxy__getAdmin() | Agent | Agent |
| StakingRouter :: Proxy | proxy__getAdmin() | Agent | Agent |
| WithdrawalQueue :: Proxy | proxy__getAdmin() | Agent | Agent |
| ⚠️ **`WithdrawalVault :: Proxy`** | proxy_getAdmin() | ⚠️ **`Voting`** | ⚠️ **`Agent`** |
| AccountingOracle :: Proxy | proxy__getAdmin() | Agent | Agent |
| ValidatorsExitBusOracle :: Proxy | proxy__getAdmin() | Agent | Agent |
| ScrollL1LidoGateway | owner() | Agent | Agent |
| ScrollProxyAdmin | owner() | Agent | Agent |
| ⚠️ **`InsuranceFund`** | owner() | ⚠️ **`Agent`** | ⚠️ **`Voting`** |
| ZKSync_L1Executor | owner() | Agent | Agent |


### Omnibus items (44 items)

#### Lido (8 items)
```
setPermissionManager('STAKING_CONTROL_ROLE', Agent)
revokePermission('STAKING_CONTROL_ROLE', Voting)
setPermissionManager('RESUME_ROLE', Agent)
revokePermission('RESUME_ROLE', Voting)
setPermissionManager('PAUSE_ROLE', Agent)
revokePermission('PAUSE_ROLE', Voting)
setPermissionManager('STAKING_PAUSE_ROLE', Agent)
revokePermission('STAKING_PAUSE_ROLE', Voting)
```

#### DAOKernel (2 items)
```
setPermissionManager('APP_MANAGER_ROLE', Agent)
revokePermission('APP_MANAGER_ROLE', Voting)
```

#### TokenManager (2 items)
```
setPermissionManager('MINT_ROLE', Voting)
setPermissionManager('REVOKE_VESTINGS_ROLE', Voting)
```

#### Finance (2 items)
```
setPermissionManager('CHANGE_PERIOD_ROLE', Voting)
setPermissionManager('CHANGE_BUDGETS_ROLE', Voting)
```

#### Agent (6 items)
```
setPermissionManager('RUN_SCRIPT_ROLE', Agent)
revokePermission('RUN_SCRIPT_ROLE', Voting)
grantPermission('RUN_SCRIPT_ROLE', DualGovernanceExecutor)
setPermissionManager('EXECUTE_ROLE', Agent)
revokePermission('EXECUTE_ROLE', Voting)
grantPermission('EXECUTE_ROLE', DualGovernanceExecutor)
```

#### ACL (3 items)
```
setPermissionManager('CREATE_PERMISSIONS_ROLE', Agent)
revokePermission('CREATE_PERMISSIONS_ROLE', Voting)
grantPermission('CREATE_PERMISSIONS_ROLE', Agent)
```

#### EVMScriptRegistry (4 items)
```
setPermissionManager('REGISTRY_ADD_EXECUTOR_ROLE', Agent)
revokePermission('REGISTRY_ADD_EXECUTOR_ROLE', Voting)
setPermissionManager('REGISTRY_MANAGER_ROLE', Agent)
revokePermission('REGISTRY_MANAGER_ROLE', Voting)
```

#### CuratedModule (6 items)
```
setPermissionManager('STAKING_ROUTER_ROLE', Agent)
setPermissionManager('MANAGE_NODE_OPERATOR_ROLE', Agent)
setPermissionManager('SET_NODE_OPERATOR_LIMIT_ROLE', Agent)
revokePermission('SET_NODE_OPERATOR_LIMIT_ROLE', Voting)
setPermissionManager('MANAGE_SIGNING_KEYS', Agent)
revokePermission('MANAGE_SIGNING_KEYS', Voting)
```

#### SimpleDVT (3 items)
```
setPermissionManager('STAKING_ROUTER_ROLE', Agent)
setPermissionManager('MANAGE_NODE_OPERATOR_ROLE', Agent)
setPermissionManager('SET_NODE_OPERATOR_LIMIT_ROLE', Agent)
```

#### AllowedTokensRegistry (6 items)
```
revokeRole('DEFAULT_ADMIN_ROLE', Agent)
grantRole('DEFAULT_ADMIN_ROLE', Voting)
revokeRole('ADD_TOKEN_TO_ALLOWED_LIST_ROLE', Agent)
grantRole('ADD_TOKEN_TO_ALLOWED_LIST_ROLE', Voting)
revokeRole('REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE', Agent)
grantRole('REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE', Voting)
```

#### WithdrawalVault (1 item)
```
setAdmin(Agent)
```

#### InsuranceFund (1 item)
```
setOwner(Voting)
```
