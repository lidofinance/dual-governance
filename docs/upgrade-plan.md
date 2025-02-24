# Role related upgrade plan

## abstract

Dual Governance protects stETH holders from the Lido DAO abusing the smart contract roles and permissions across Lido on Ethereum protocol. In order to achieve that, some / most roles would need to get transitioned "under DG control". The document aims to:
- provide the necessary context;
- outline the transition plan;
- highlight a couple specific details about the plan:
    - edge-cases where the plan enacted would wreak existing operations;
    - specific roles / permissions which need to stay on DAO.

## outline

1. context to how the roles are structured / granted now (prior to DG deployment);
2. what's the plan; what's the alternative options (and why they are worse);
3. what are highlights / exceptions;
4. context and full roles list / things to look up.

## context to how the roles are structured now

Most roles under Lido DAO management are granted to:

1. aragon **Voting** contract;
2. aragon **Agent** contract (actions on behalf of aragon Agent require a role for `Agent.forward`, currently granted only to aragon Voting contract = to do anything on behalf of Agent, the LDO vote is required);
3. **EVMScriptExecutor** — part of Easy Track mechanism, does payments from aragon Agent (=Treasury), has the role to "set limits for curated module", has the role management rights for SDVT and the role to settle penalties for CSM;
4. committees: multisigs and GateSeals, having the roles and permissions necessary to perform day to day functions (directly or through Easy Track).

There are multiple "control mechanics" employed by Lido on Ethereum contracts:

- **aragon's permissions (ACL)**: Managed by the aragon Access Control List (ACL) contract, this system provides a granular permission model within the aragon app. The main role unlocking ACL management is `CREATE_PERMISSIONS_ROLE`, assigned to Voting contract. The entity holding this role has ultimate power over the all unassigned ACL roles in Lido Aragon Apps (i.e. Voting, Agent, Lido, Oracle and other "core" contracts based on Aragon framework). To assign any role one needs to first define role manager address; any actions with the role once the manager is defined can be done only by this manager address;
- **OpenZeppelin's access control**: This is a role-based access control mechanism provided by the OpenZeppelin library. Roles are defined and granted individually on a per-contract basis. Contracts with OZ role model have "role admin" mechanics: the roles are managed by either "role admin" or "default admin" (if there's no admin address assigned as specific role admin). Both default and specific role admins can be queried by calling `getRoleAdmin` method on the contract;
- **unassigned roles**: Some existing roles may intentionally not be assigned to any entity. This means that, by default, no one has the authority to perform actions associated with these roles unless the DAO explicitly grants the permission through a governance proposal;
- **aragon ownerships**: these ownerships are managed through the Kernel contract. The Kernel allows the DAO to setup applications (by calling `setApp`) and keeps them under its control, while access to these apps is managed through the ACL;
- **ownable contracts**: Some contracts within the Lido protocol use the Ownable pattern, where a single owner address has exclusive access to certain administrative functions.
- **EthereumGovernanceExecutor** field on L2 parts employing "governance forwarding" — checked it's set to Aragon Agent everywhere;
- **immutable variables**: There are some contracts that contain immutable variables referring to the DAO contracts. Such as Stonks (contains immutable agent address) and Burner (contains immutable treasury address).

## the transition plan

Goal is to cover the "potentially dangerous for steth" roles and permissions by Dual Governance.

The requirements / constraints / "plan design goals" are:
- do a transition in sane, graspable way;
- maintain business continuity (don't break the flows necessary for day to day protocol and DAO operations);
- have a way to check for completeness.

Thus, the plan goes like this:
1. aragon Voting passes all the roles (except treasury management, insurance fund and all roles related to Voting and TokenManager contracts) and ownerships to aragon Agent;
2. aragon Agent:
    1. revokes a role for `Agent.forward` from Voting;
    2. grants a role for `Agent.forward` to Dual Governance Executor contract;
3. EVMScriptExecutor/EasyTrack remains as-is (Voting is owner of EVMScriptExecutor and holder of `DEFAULT_ADMIN_ROLE` for EasyTrack, but given Voting isn't role manager / admin on things which need to be under DG — Voting can't grant permissions necessary to breach "DG protection");
4. committees remain as-is to maintain business continuity;
5. immutable variables remain as-is until future updates;
6. all EasyTrack factories remain as-is until future updates.

The role-by-role list of actions to be taken is outlined [below](#role-listing-script-output).

Note: If there are problems with upgrade or DG functioning, the right to call `Agent.forward` can be returned back to the Voting contract without needing to transfer all the roles back.

## highlights and exceptions

- EasyTrack "parts" (`AllowedRecipientsRegistry` and `AllowedTokensRegistry` ownership) is proposed to stay on Agent to not to overcomplicate the DG "switch on" vote (can be managed outside of DG deployment, if operationally possible; that's ~32-actions-worth vote);
- roles necessary for EasyTrack motions for Curated NOs to add keys remain without changes;
- roles necessary for EasyTrack motions for SDVT management remain without changes;
- roles necessary for EasyTrack motions for CSM penalty management remains without changes;
- all the roles across Lido on Ethereum contracts are managed by `DEFAULT_ADMIN` (Agent); only EasyTrack has `DEFAULT_ADMIN` set to Voting contract;
- roles necessary for pausing for critical contracts (such as `PAUSE_ROLE` for Lido/stETH contract) are also considered to be moved so it might lead to slower decision making in critical situations;
- at the moment Aragon app does have additional ACL and Kernel contracts for repos (PM repo, Oracle repo, etc.) to support Aragon UI. It is decided to drop support of these contracts (leave as are);
- all L2 bridges refer to Agent contract as a manager/owner so it remains without changes.

### impact of the rights getting transferred to DG

Practical effect of moving the role under DG is
1) in general, activating / performing any action requiring this role takes longer (LDO governance time + DG default timelock (about 3-4 days per the current proposed params));
2) if DG veto escrow crosses the first threshold (veto signalling, ~1.5% steth TVL opposes the motion), the timelock becomes dynamic (= the action will be taking an undefined long time).

Another important thing to consider: some mechanics in the protocol rely upon "LDO governance reaction time"; the obvious examples are GateSeals (have specific treatment under DG), non-obvious is `FINALIZATION_MAX_NEGATIVE_REBASE_EPOCH_SHIFT` OracleReportSanityChecker param. To the best of value stream tech teams' knowledge, those are the only two examples with implicit dependancy on DAO's reaction time.

## context and full roles list / things to look up

In order to collect the full roles and permissions list, the team has created the [script](https://github.com/lidofinance/dual-governance/pull/226) based on acceptance tests being run on every vote.

The script: 1) collects the roles set as-is; 2) compares the status with the "desired" one set in config; 3) prints the `.md` file based on comparison.

Note: there's a full-blown ["role model research"](https://github.com/lidofinance/audits/blob/main/Statemind%20Lido%20roles%20analysis%2010-2023.pdf) brought up by Statemind. It doesn't account for the latest changes from SR+CSM upgrade, new Multichain deployments and multisigs/committees, but list most of the roles with deeper context.

"Action items" for the "DG switching on" vote based on the outlined plan are listed below.

### role listing script output

Note: If a role is highlighted in bold, it means that this role will either be granted or revoked. The ⚠️ icon means that an operation will be performed on this role.

### ACL (22 roles modified)

#### Lido

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **STAKING_CONTROL_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | ∅ |
| ⚠️ **RESUME_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | ∅ |
| ⚠️ **PAUSE_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | ∅ |
| ⚠️ **STAKING_PAUSE_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | ∅ |
| UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE | ``∅`` | ∅ | ∅ |


#### DAOKernel

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **APP_MANAGER_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | ∅ |


#### TokenManager

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **MINT_ROLE** | **`∅` -> `Voting`** | ∅ | ∅ |
| ⚠️ **REVOKE_VESTINGS_ROLE** | **`∅` -> `Voting`** | ∅ | ∅ |
| ISSUE_ROLE | ``Voting`` | ∅ | ∅ |
| ASSIGN_ROLE | ``Voting`` | ∅ | `Voting` |
| BURN_ROLE | ``Voting`` | ∅ | ∅ |


#### Finance

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **CHANGE_PERIOD_ROLE** | **`∅` -> `Voting`** | ∅ | ∅ |
| ⚠️ **CHANGE_BUDGETS_ROLE** | **`∅` -> `Voting`** | ∅ | ∅ |
| CREATE_PAYMENTS_ROLE | ``Voting`` | ∅ | `Voting`, `ET :: EVMScriptExecutor` |
| EXECUTE_PAYMENTS_ROLE | ``Voting`` | ∅ | `Voting` |
| MANAGE_PAYMENTS_ROLE | ``Voting`` | ∅ | `Voting` |


#### Agent

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **RUN_SCRIPT_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | **`DualGovernance`** |
| ⚠️ **EXECUTE_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | **`DualGovernance`** |
| TRANSFER_ROLE | ``Voting`` | ∅ | `Finance` |
| SAFE_EXECUTE_ROLE | ``∅`` | ∅ | ∅ |
| DESIGNATE_SIGNER_ROLE | ``∅`` | ∅ | ∅ |
| ADD_PRESIGNED_HASH_ROLE | ``∅`` | ∅ | ∅ |
| ADD_PROTECTED_TOKEN_ROLE | ``∅`` | ∅ | ∅ |
| REMOVE_PROTECTED_TOKEN_ROLE | ``∅`` | ∅ | ∅ |


#### ACL

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **CREATE_PERMISSIONS_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | **`Agent`** |


#### CuratedModule

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **STAKING_ROUTER_ROLE** | **`Voting` -> `Agent`** | ∅ | `StakingRouter` |
| ⚠️ **MANAGE_NODE_OPERATOR_ROLE** | **`Voting` -> `Agent`** | ∅ | `Agent` |
| ⚠️ **SET_NODE_OPERATOR_LIMIT_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | `ET :: EVMScriptExecutor` |
| ⚠️ **MANAGE_SIGNING_KEYS** | **`Voting` -> `Agent`** | **`Voting`** | ∅ |


#### SimpleDVT

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **STAKING_ROUTER_ROLE** | **`Voting` -> `Agent`** | ∅ | `StakingRouter`, `ET :: EVMScriptExecutor` |
| ⚠️ **MANAGE_NODE_OPERATOR_ROLE** | **`Voting` -> `Agent`** | ∅ | `ET :: EVMScriptExecutor` |
| ⚠️ **SET_NODE_OPERATOR_LIMIT_ROLE** | **`Voting` -> `Agent`** | ∅ | `ET :: EVMScriptExecutor` |
| ⚠️ **MANAGE_SIGNING_KEYS** | ``EasyTrackEvmScriptExecutor`` | `+67 **UNKNOWN** holders` | `ET :: EVMScriptExecutor` |


#### EVMScriptRegistry

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ **REGISTRY_ADD_EXECUTOR_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | ∅ |
| ⚠️ **REGISTRY_MANAGER_ROLE** | **`Voting` -> `Agent`** | **`Voting`** | ∅ |

<details>
<summary>Not affected contracts</summary>

#### Voting

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| UNSAFELY_MODIFY_VOTE_TIME_ROLE | ``Voting`` | ∅ | ∅ |
| MODIFY_QUORUM_ROLE | ``Voting`` | ∅ | `Voting` |
| MODIFY_SUPPORT_ROLE | ``Voting`` | ∅ | `Voting` |
| CREATE_VOTES_ROLE | ``Voting`` | ∅ | `TokenManager` |


#### VotingRepo

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ``∅`` | ∅ | ∅ |


#### LidoRepo

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ``∅`` | ∅ | ∅ |


#### LegacyOracleRepo

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ``∅`` | ∅ | ∅ |


#### CuratedModuleRepo

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ``∅`` | ∅ | ∅ |


#### SimpleDVTRepo

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_VERSION_ROLE | ``∅`` | ∅ | ∅ |


#### AragonPM

| Role | Manager | Revoked | Granted |
| --- | --- | --- | --- |
| CREATE_REPO_ROLE | ``∅`` | ∅ | ∅ |

</details>

### OpenZeppelin (3 roles modified)

#### StakingRouter

#### AllowedTokensRegistry

| Role | Revoked | Granted |
| --- | --- | --- |
| ⚠️ **DEFAULT_ADMIN_ROLE** | **`Agent`** | **`Voting`** |
| ⚠️ **ADD_TOKEN_TO_ALLOWED_LIST_ROLE** | **`Agent`** | **`Voting`** |
| ⚠️ **REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE** | **`Agent`** | **`Voting`** |

<details>
<summary>Not affected contracts</summary>

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| MANAGE_WITHDRAWAL_CREDENTIALS_ROLE | ∅ | ∅ |
| REPORT_EXITED_VALIDATORS_ROLE | ∅ | `AccountingOracle` |
| REPORT_REWARDS_MINTED_ROLE | ∅ | `Lido` |
| STAKING_MODULE_MANAGE_ROLE | ∅ | `Agent` |
| STAKING_MODULE_UNVETTING_ROLE | ∅ | `DepositSecurityModule` |
| UNSAFE_SET_EXITED_VALIDATORS_ROLE | ∅ | ∅ |


#### WithdrawalQueueERC721

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| FINALIZE_ROLE | ∅ | `Lido` |
| MANAGE_TOKEN_URI_ROLE | ∅ | ∅ |
| ORACLE_ROLE | ∅ | `AccountingOracle` |
| PAUSE_ROLE | ∅ | `OraclesGateSeal` |
| RESUME_ROLE | ∅ | ∅ |


#### Burner

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| REQUEST_BURN_MY_STETH_ROLE | ∅ | `Agent` |
| REQUEST_BURN_SHARES_ROLE | ∅ | `Lido`, `CuratedModule`, `SimpleDVT`, `CSAccounting` |


#### AccountingOracle

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| MANAGE_CONSENSUS_CONTRACT_ROLE | ∅ | ∅ |
| MANAGE_CONSENSUS_VERSION_ROLE | ∅ | ∅ |
| SUBMIT_DATA_ROLE | ∅ | ∅ |


#### AccountingOracleHashConsensus

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DISABLE_CONSENSUS_ROLE | ∅ | ∅ |
| MANAGE_FAST_LANE_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_FRAME_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_MEMBERS_AND_QUORUM_ROLE | ∅ | `Agent` |
| MANAGE_REPORT_PROCESSOR_ROLE | ∅ | ∅ |


#### ValidatorExitBusOracle

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| MANAGE_CONSENSUS_CONTRACT_ROLE | ∅ | ∅ |
| MANAGE_CONSENSUS_VERSION_ROLE | ∅ | ∅ |
| PAUSE_ROLE | ∅ | `OraclesGateSeal` |
| RESUME_ROLE | ∅ | ∅ |
| SUBMIT_DATA_ROLE | ∅ | ∅ |


#### ValidatorExitBusHashConsensus

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DISABLE_CONSENSUS_ROLE | ∅ | ∅ |
| MANAGE_FAST_LANE_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_FRAME_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_MEMBERS_AND_QUORUM_ROLE | ∅ | `Agent` |
| MANAGE_REPORT_PROCESSOR_ROLE | ∅ | ∅ |


#### OracleReportSanityChecker

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
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


#### OracleDaemonConfig

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| CONFIG_MANAGER_ROLE | ∅ | ∅ |


#### CSModule

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| MODULE_MANAGER_ROLE | ∅ | ∅ |
| PAUSE_ROLE | ∅ | `CSGateSeal` |
| RECOVERER_ROLE | ∅ | ∅ |
| REPORT_EL_REWARDS_STEALING_PENALTY_ROLE | ∅ | `CSCommitteeMultisig` |
| RESUME_ROLE | ∅ | ∅ |
| SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE | ∅ | `ET :: EVMScriptExecutor` |
| STAKING_ROUTER_ROLE | ∅ | `StakingRouter` |
| VERIFIER_ROLE | ∅ | `CSVerifier` |


#### CSAccounting

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| ACCOUNTING_MANAGER_ROLE | ∅ | ∅ |
| MANAGE_BOND_CURVES_ROLE | ∅ | ∅ |
| PAUSE_ROLE | ∅ | `CSGateSeal` |
| RECOVERER_ROLE | ∅ | ∅ |
| RESET_BOND_CURVE_ROLE | ∅ | `CSModule`, `CSCommitteeMultisig` |
| RESUME_ROLE | ∅ | ∅ |
| SET_BOND_CURVE_ROLE | ∅ | `CSModule`, `CSCommitteeMultisig` |


#### CSFeeDistributor

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| RECOVERER_ROLE | ∅ | ∅ |


#### CSFeeOracle

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| CONTRACT_MANAGER_ROLE | ∅ | ∅ |
| MANAGE_CONSENSUS_CONTRACT_ROLE | ∅ | ∅ |
| MANAGE_CONSENSUS_VERSION_ROLE | ∅ | ∅ |
| PAUSE_ROLE | ∅ | `CSGateSeal` |
| RECOVERER_ROLE | ∅ | ∅ |
| RESUME_ROLE | ∅ | ∅ |
| SUBMIT_DATA_ROLE | ∅ | ∅ |


#### CSHashConsensus

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DISABLE_CONSENSUS_ROLE | ∅ | ∅ |
| MANAGE_FAST_LANE_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_FRAME_CONFIG_ROLE | ∅ | ∅ |
| MANAGE_MEMBERS_AND_QUORUM_ROLE | ∅ | `Agent` |
| MANAGE_REPORT_PROCESSOR_ROLE | ∅ | ∅ |


#### EasyTrack

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Voting` |
| CANCEL_ROLE | ∅ | `Voting` |
| PAUSE_ROLE | ∅ | `Voting`, `EmergencyBrakesMultisig` |
| UNPAUSE_ROLE | ∅ | `Voting` |


#### L1ERC20TokenGateway_Arbitrum

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DEPOSITS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| DEPOSITS_ENABLER_ROLE | ∅ | `Agent` |
| WITHDRAWALS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| WITHDRAWALS_ENABLER_ROLE | ∅ | `Agent` |


#### L1TokensBridge_Optimism

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DEPOSITS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| DEPOSITS_ENABLER_ROLE | ∅ | `Agent` |
| WITHDRAWALS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| WITHDRAWALS_ENABLER_ROLE | ∅ | `Agent` |


#### ERC20Predicate_Polygon

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | ∅ |
| MANAGER_ROLE | ∅ | ∅ |


#### L1ERC20TokenBridge_Base

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DEPOSITS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| DEPOSITS_ENABLER_ROLE | ∅ | `Agent` |
| WITHDRAWALS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| WITHDRAWALS_ENABLER_ROLE | ∅ | `Agent` |


#### L1ERC20Bridge_zkSync

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DEPOSITS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| DEPOSITS_ENABLER_ROLE | ∅ | `Agent` |
| WITHDRAWALS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| WITHDRAWALS_ENABLER_ROLE | ∅ | `Agent` |


#### L1ERC20TokenBridge_Mantle

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DEPOSITS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| DEPOSITS_ENABLER_ROLE | ∅ | `Agent` |
| WITHDRAWALS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| WITHDRAWALS_ENABLER_ROLE | ∅ | `Agent` |


#### L1LidoGateway_Scroll

| Role | Revoked | Granted |
| --- | --- | --- |
| DEPOSITS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| DEPOSITS_ENABLER_ROLE | ∅ | `Agent` |
| WITHDRAWALS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| WITHDRAWALS_ENABLER_ROLE | ∅ | `Agent` |


#### L1ERC20TokenBridge_Mode

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DEPOSITS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| DEPOSITS_ENABLER_ROLE | ∅ | `Agent` |
| WITHDRAWALS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| WITHDRAWALS_ENABLER_ROLE | ∅ | `Agent` |


#### L1ERC20TokenBridge_Zircuit

| Role | Revoked | Granted |
| --- | --- | --- |
| DEFAULT_ADMIN_ROLE | ∅ | `Agent` |
| DEPOSITS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| DEPOSITS_ENABLER_ROLE | ∅ | `Agent` |
| WITHDRAWALS_DISABLER_ROLE | ∅ | `Agent`, `EmergencyBrakesMultisig` |
| WITHDRAWALS_ENABLER_ROLE | ∅ | `Agent` |

</details>

### Managed Contracts Updates (2 owners modified)

| Contract | Property | Old Manager | New Manager |
| --- | --- | --- | --- |
| DSM | `getOwner()` | `Agent` | `Agent` |
| LidoLocator :: Proxy | `proxy__getAdmin()` | `Agent` | `Agent` |
| StakingRouter :: Proxy | `proxy__getAdmin()` | `Agent` | `Agent` |
| WithdrawalQueue :: Proxy | `proxy__getAdmin()` | `Agent` | `Agent` |
| **⚠️ **WithdrawalVault :: Proxy**** | `proxy_getAdmin()` | `Voting` | **`Agent`** |
| AccountingOracle :: Proxy | `proxy__getAdmin()` | `Agent` | `Agent` |
| ValidatorsExitBusOracle :: Proxy | `proxy__getAdmin()` | `Agent` | `Agent` |
| ScrollL1LidoGateway | `owner()` | `Agent` | `Agent` |
| ScrollProxyAdmin | `owner()` | `Agent` | `Agent` |
| **⚠️ **InsuranceFund**** | `owner()` | `Agent` | **`Voting`** |
| ZKSync_L1Executor | `owner()` | `Agent` | `Agent` |