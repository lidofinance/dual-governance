# Protocol permissions transition due to Dual Governance upgrade

## Abstract

Dual Governance protects stETH holders from the Lido DAO abusing the smart contract roles and permissions across Lido on Ethereum protocol. In order to achieve that, some / most roles would need to get transitioned "under DG control". The document aims to:

- Provide the necessary context.
- Outline the transition plan.
- Highlight a couple specific details about the plan:
  - Edge-cases where the plan enacted would wreak existing operations.
  - Specific roles / permissions which need to stay on DAO.

## Context to how the roles are structured now

Most roles under Lido DAO management are granted to:

1. Aragon **Voting** contract.
2. Aragon **Agent** contract (actions on behalf of Aragon Agent require a role for `Agent.forward`, currently granted only to Aragon Voting contract, actions from that requires the LDO vote).
3. **EVMScriptExecutor** — part of Easy Track mechanism, does payments from Aragon Agent (i.e. Treasury), has the role to "set limits for curated module", has the role management rights for SDVT and the role to settle penalties for CSM.
4. Committees: multisigs and GateSeals, having the roles and permissions necessary to perform day to day functions (directly or through Easy Track).

There are multiple "control mechanics" employed by Lido on Ethereum contracts:

- **Aragon's permissions (ACL)**: managed by the Aragon Access Control List (ACL) contract, this system provides a granular permission model within the Aragon app. The main role unlocking ACL management is `CREATE_PERMISSIONS_ROLE`, assigned to Voting contract. The entity holding this role has ultimate power over the all unassigned ACL roles in Lido Aragon Apps (i.e. Voting, Agent, Lido, Oracle and other "core" contracts based on Aragon framework). To assign any role one needs to first define role manager address; any actions with the role once the manager is defined can be done only by this manager address.
- **OpenZeppelin's access control**: this is a role-based access control mechanism provided by the OpenZeppelin library. Roles are defined and granted individually on a per-contract basis. Contracts with OZ role model have "role admin" mechanics: the roles are managed by "role admin" ("default admin" if there's no admin address assigned as specific role admin). Role admin can be queried by calling `getRoleAdmin` method on the contract.
- **Unassigned roles**: some existing roles may intentionally not be assigned to any entity. This means that, by default, no one has the authority to perform actions associated with these roles unless the DAO explicitly grants the permission through a governance proposal.
- **Aragon ownerships**: these ownerships are managed through the Kernel contract. The Kernel allows the DAO to setup/update applications (by calling `setApp`) and keeps them under its control, while access to these apps is managed through the ACL.
- **Ownable contracts**: some contracts within the Lido protocol use the Ownable pattern, where a single owner address has exclusive access to certain administrative functions.
- **EthereumGovernanceExecutor** field on L2 parts employing "governance forwarding" — checked it's set to Aragon Agent everywhere.
- **Immutable variables**: there are some contracts that contain immutable variables referring to the DAO contracts. Such as Stonks (contains immutable agent address) and Burner (contains immutable treasury address).

## The transition plan

Goal is to protect the "potentially dangerous for steth" roles and permissions by Dual Governance.

The requirements / constraints / "plan design goals" are:

- Do a transition in sane, graspable way.
- Maintain business continuity (don't break the flows necessary for day to day protocol and DAO operations).
- Have a way to check for completeness.

Thus, the plan goes like this:

1. Aragon Voting passes all the roles (except treasury management, insurance fund and all roles related to Voting and TokenManager contracts) and ownerships to Aragon Agent.
2. Aragon Agent:
   1. Grants a role for `Agent.forward` to Dual Governance Executor contract.
   2. Revokes a role for `Agent.forward` from Voting.
3. EVMScriptExecutor/EasyTrack remains as-is (Voting is owner of EVMScriptExecutor and holder of `DEFAULT_ADMIN_ROLE` for EasyTrack, but given Voting isn't role manager / admin on things which need to be under DG — Voting can't grant permissions necessary to breach "DG protection").
4. Committees remain as-is to maintain business continuity.
5. Immutable variables remain as-is until future updates.
6. All EasyTrack factories remain as-is until future updates.

The role-by-role list of actions to be taken is outlined [below](#transition-plan).

## Highlights and exceptions

- ACL's `CREATE_PERMISSION_ROLE` goes to Agent, that means **creating new roles** should go through the Dual Governance what **will take longer to execute**.
- Roles necessary for **pausing** for critical contracts (particularly `PAUSE_ROLE` for Lido/stETH contract) are **considered to be moved to Agent** so it leads to slower decision making in critical situations. Sealable roles with no time limitation remain on the Agent and ResealManager.
- EasyTrack "parts" (`AllowedRecipientsRegistry` ownership) are proposed to stay on Agent to not to overcomplicate the DG "switch on" vote (can be managed outside of DG deployment, if operationally possible; that's ~32-actions-worth vote).
- Roles necessary for EasyTrack motions for Curated NOs to add keys remain without changes.
- Roles necessary for EasyTrack motions for SDVT management remain without changes.
- Roles necessary for EasyTrack motions for CSM penalty management remains without changes.
- All the roles across Lido on Ethereum contracts are managed by `DEFAULT_ADMIN` (Agent); only EasyTrack has `DEFAULT_ADMIN` set to Voting contract.
- At the moment Aragon app does have additional ACL and Kernel contracts for repos (PM repo, Oracle repo, etc.) to support Aragon UI. It is [decided](https://research.lido.fi/t/discontinuation-of-aragon-ui-use/7992) to drop support of these contracts (leave them as is).
- All L2 bridges (except for [Polygon](#erc20predicate_polygon0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf) and [Linea](#l1tokenbridge_linea0x051f1d88f0af5763fb888ec4378b4d8b29ea3319), which are not under the direct control of the DAO) refer to the Agent contract as a manager/owner and thus remain unchanged.
- [AragonPM](https://etherscan.io/address/0x0cb113890b04b49455dfe06554e2d784598a29c9#code) and all Aragon Apps Repo contracts ([Voting Repo](https://etherscan.io/address/0x4ee3118e3858e8d7164a634825bfe0f73d99c792), [Lido App Repo](https://etherscan.io/address/0xF5Dc67E54FC96F993CD06073f71ca732C1E654B1), etc.) remain under the control of the Voting contract. These contracts were necessary for the proper functioning of the Aragon UI, [which is now deprecated](https://research.lido.fi/t/discontinuation-of-aragon-ui-use/7992).

### Impact of the rights getting transferred to DG

Practical effect of moving the role under DG is

1. In general, activating / performing any action requiring this role takes longer (LDO governance time + DG default timelock (about 3-4 days per the current proposed params)).
2. If DG veto escrow crosses the first threshold (veto signalling, 1% steth TVL opposes the motion), the timelock becomes dynamic (it's [limited](https://github.com/lidofinance/dual-governance/blob/831ad62bca6913dbfbb56bb341feb8588b349ebe/docs/mechanism.md#veto-signalling-state) during the VetoSignalling state, and [unpredictably long](https://github.com/lidofinance/dual-governance/blob/831ad62bca6913dbfbb56bb341feb8588b349ebe/docs/mechanism.md#rage-quit-state) during the RageQuit state).

Another important thing to consider: some mechanics in the protocol rely upon "LDO governance reaction time"; the obvious examples are GateSeals (have specific treatment under DG), non-obvious is [`FINALIZATION_MAX_NEGATIVE_REBASE_EPOCH_SHIFT`](https://docs.lido.fi/guides/oracle-spec/accounting-oracle/#negative-rebase-border) [`OracleDaemonConfig`](https://etherscan.io/address/0xbf05A929c3D7885a6aeAd833a992dA6E5ac23b09) param. To the best of value stream tech teams' knowledge, those are the only two examples with implicit dependancy on DAO's reaction time.

## Context and full roles list / things to look up

In order to collect the full roles and permissions list, the team has created the [script](https://github.com/lidofinance/dual-governance/pull/226) based on acceptance tests being run on every vote.

The script:

1. Collects the roles set as-is
2. Compares the status with the "desired" one set in config
3. Prints the `.md` file based on comparison

Note: there's a full-blown ["role model research"](https://github.com/lidofinance/audits/blob/main/Statemind%20Lido%20roles%20analysis%2010-2023.pdf) brought up by Statemind. It doesn't account for the latest changes from SR+CSM upgrade, new Multichain deployments and multisigs/committees, but list most of the roles with deeper context.

"Action items" for the "DG switching on" vote based on the outlined plan are listed below.

## Transition Plan

> - Data was collected at block [`22669442`](https://etherscan.io/block/22669442)
> - The last permissions change occurred at block [`22623238`](https://etherscan.io/block/22623238), transaction [`0x4e8b33eee6600b8cea3597a828c4462529d8ff7fe17c66be4cc986fc75d72aec`](https://etherscan.io/tx/0x4e8b33eee6600b8cea3597a828c4462529d8ff7fe17c66be4cc986fc75d72aec)

How to read this document:
- If an item is prepended with the "⚠️" icon, it indicates that the item will be changed. The required updates are described in the corresponding "Transition Steps" sections.
- The special symbol "∅" indicates that:
  - a permission or role is not granted to any address
  - revocation of the permission or role is not performed
  - no manager is set for the permission
- The notation "`Old Manager` → `New Manager`" means the current manager is being changed to a new one.
  - A special case is "`∅` → `New Manager`", which means the permission currently has no manager, and the permission should be created before use.

> [!NOTE]
> Due to the specifics of the [`Aragon ACL`](https://etherscan.io/address/0x9895f0f17cc1d1891b6f18ee0b483b6f221b37bb) implementation, when a permission is created for the first time, it must be granted to an address. To minimize the number of actions in the transition plan, these newly created permissions remain granted to the permission manager contract. For example, the `MINT_ROLE` of the [`TokenManager`](https://etherscan.io/address/0xf73a1260d222f447210581DDf212D915c09a3249) contract remains granted to the [`Voting`](https://etherscan.io/address/0x2e59A20f205bB85a89C53f1936454680651E618e) contract.

### Aragon Permissions
#### ⚠️ Lido [0xae7ab96520de3a18e5e111b5eaab095312d7fe84](https://etherscan.io/address/0xae7ab96520de3a18e5e111b5eaab095312d7fe84)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`STAKING_CONTROL_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_CONTROL_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ |
| ⚠️ [`STAKING_PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_PAUSE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ |
| [`UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

##### Transition Steps

```
1. Revoke STAKING_CONTROL_ROLE permission from Voting on Lido
2. Set STAKING_CONTROL_ROLE manager to Agent on Lido
3. Revoke RESUME_ROLE permission from Voting on Lido
4. Set RESUME_ROLE manager to Agent on Lido
5. Revoke PAUSE_ROLE permission from Voting on Lido
6. Set PAUSE_ROLE manager to Agent on Lido
7. Revoke STAKING_PAUSE_ROLE permission from Voting on Lido
8. Set STAKING_PAUSE_ROLE manager to Agent on Lido
```

#### ⚠️ DAOKernel [0xb8ffc3cd6e7cf5a098a1c92f48009765b24088dc](https://etherscan.io/address/0xb8ffc3cd6e7cf5a098a1c92f48009765b24088dc)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`APP_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=APP_MANAGER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ |

##### Transition Steps

```
9. Revoke APP_MANAGER_ROLE permission from Voting on DAOKernel
10. Set APP_MANAGER_ROLE manager to Agent on DAOKernel
```

#### ⚠️ TokenManager [0xf73a1260d222f447210581ddf212d915c09a3249](https://etherscan.io/address/0xf73a1260d222f447210581ddf212d915c09a3249)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`MINT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MINT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| ⚠️ [`REVOKE_VESTINGS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REVOKE_VESTINGS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| [`ISSUE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ISSUE_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | ∅ |
| [`ASSIGN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ASSIGN_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| [`BURN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=BURN_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | ∅ |

##### Transition Steps

```
11. Create MINT_ROLE permission on TokenManager with manager Voting and grant it to Voting
12. Create REVOKE_VESTINGS_ROLE permission on TokenManager with manager Voting and grant it to Voting
```

#### ⚠️ Finance [0xb9e5cbb9ca5b0d659238807e84d0176930753d86](https://etherscan.io/address/0xb9e5cbb9ca5b0d659238807e84d0176930753d86)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`CHANGE_PERIOD_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CHANGE_PERIOD_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| ⚠️ [`CHANGE_BUDGETS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CHANGE_BUDGETS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| [`CREATE_PAYMENTS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_PAYMENTS_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) [`EvmScriptExecutor`](https://etherscan.io/address/0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977) |
| [`EXECUTE_PAYMENTS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=EXECUTE_PAYMENTS_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| [`MANAGE_PAYMENTS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_PAYMENTS_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |

##### Transition Steps

```
13. Create CHANGE_PERIOD_ROLE permission on Finance with manager Voting and grant it to Voting
14. Create CHANGE_BUDGETS_ROLE permission on Finance with manager Voting and grant it to Voting
```

#### ⚠️ EVMScriptRegistry [0x853cc0d5917f49b57b8e9f89e491f5e18919093a](https://etherscan.io/address/0x853cc0d5917f49b57b8e9f89e491f5e18919093a)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`REGISTRY_ADD_EXECUTOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REGISTRY_ADD_EXECUTOR_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ |
| ⚠️ [`REGISTRY_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REGISTRY_MANAGER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ |

##### Transition Steps

```
15. Revoke REGISTRY_ADD_EXECUTOR_ROLE permission from Voting on EVMScriptRegistry
16. Set REGISTRY_ADD_EXECUTOR_ROLE manager to Agent on EVMScriptRegistry
17. Revoke REGISTRY_MANAGER_ROLE permission from Voting on EVMScriptRegistry
18. Set REGISTRY_MANAGER_ROLE manager to Agent on EVMScriptRegistry
```

#### ⚠️ CuratedModule [0x55032650b14df07b85bf18a3a3ec8e0af2e028d5](https://etherscan.io/address/0x55032650b14df07b85bf18a3a3ec8e0af2e028d5)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`STAKING_ROUTER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_ROUTER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ∅ | [`StakingRouter`](https://etherscan.io/address/0xfddf38947afb03c621c71b06c9c70bce73f12999) |
| ⚠️ [`MANAGE_NODE_OPERATOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_NODE_OPERATOR_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| ⚠️ [`SET_NODE_OPERATOR_LIMIT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_NODE_OPERATOR_LIMIT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | [`EvmScriptExecutor`](https://etherscan.io/address/0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977) |
| ⚠️ [`MANAGE_SIGNING_KEYS`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_SIGNING_KEYS&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ |

##### Transition Steps

```
19. Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule
20. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on CuratedModule
21. Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on CuratedModule
22. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on CuratedModule
23. Revoke MANAGE_SIGNING_KEYS permission from Voting on CuratedModule
24. Set MANAGE_SIGNING_KEYS manager to Agent on CuratedModule
```

#### ⚠️ SimpleDVT [0xae7b191a31f627b4eb1d4dac64eab9976995b433](https://etherscan.io/address/0xae7b191a31f627b4eb1d4dac64eab9976995b433)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`STAKING_ROUTER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_ROUTER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ∅ | [`StakingRouter`](https://etherscan.io/address/0xfddf38947afb03c621c71b06c9c70bce73f12999) [`EvmScriptExecutor`](https://etherscan.io/address/0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977) |
| ⚠️ [`MANAGE_NODE_OPERATOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_NODE_OPERATOR_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ∅ | [`EvmScriptExecutor`](https://etherscan.io/address/0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977) |
| ⚠️ [`SET_NODE_OPERATOR_LIMIT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_NODE_OPERATOR_LIMIT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ∅ | [`EvmScriptExecutor`](https://etherscan.io/address/0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977) |
| [`MANAGE_SIGNING_KEYS`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_SIGNING_KEYS&input_type=utf-8&output_type=hex) | [`EvmScriptExecutor`](https://etherscan.io/address/0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977) | ∅ | [`EvmScriptExecutor`](https://etherscan.io/address/0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977) `+82 Simple DVT Operator(s)` |

##### Transition Steps

```
25. Set STAKING_ROUTER_ROLE manager to Agent on SimpleDVT
26. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on SimpleDVT
27. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on SimpleDVT
```

#### ⚠️ ACL [0x9895f0f17cc1d1891b6f18ee0b483b6f221b37bb](https://etherscan.io/address/0x9895f0f17cc1d1891b6f18ee0b483b6f221b37bb)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`CREATE_PERMISSIONS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_PERMISSIONS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ⚠️ [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

##### Transition Steps

```
28. Grant CREATE_PERMISSIONS_ROLE permission to Agent on ACL
29. Revoke CREATE_PERMISSIONS_ROLE permission from Voting on ACL
30. Set CREATE_PERMISSIONS_ROLE manager to Agent on ACL
```

#### ⚠️ Agent [0x3e40d73eb977dc6a537af587d48316fee66e9c8c](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`RUN_SCRIPT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RUN_SCRIPT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ⚠️ [`DGAdminExecutor`](https://etherscan.io/address/0x23e0b465633ff5178808f4a75186e2f2f9537021) |
| ⚠️ [`EXECUTE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=EXECUTE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) → [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ⚠️ [`DGAdminExecutor`](https://etherscan.io/address/0x23e0b465633ff5178808f4a75186e2f2f9537021) |
| [`TRANSFER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=TRANSFER_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | [`Finance`](https://etherscan.io/address/0xb9e5cbb9ca5b0d659238807e84d0176930753d86) |
| [`SAFE_EXECUTE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SAFE_EXECUTE_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`DESIGNATE_SIGNER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DESIGNATE_SIGNER_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`ADD_PRESIGNED_HASH_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ADD_PRESIGNED_HASH_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`ADD_PROTECTED_TOKEN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ADD_PROTECTED_TOKEN_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`REMOVE_PROTECTED_TOKEN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REMOVE_PROTECTED_TOKEN_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

##### Transition Steps

```
31. Grant RUN_SCRIPT_ROLE permission to DGAdminExecutor on Agent
// DONE VIA DG PROPOSAL: __. Revoke RUN_SCRIPT_ROLE permission from Voting on Agent - Will be done as 
//      the last step of the launch via the Dual Governance proposal
32. Set RUN_SCRIPT_ROLE manager to Agent on Agent
33. Grant EXECUTE_ROLE permission to DGAdminExecutor on Agent
// DONE VIA DG PROPOSAL: __. Revoke EXECUTE_ROLE permission from Voting on Agent - Will be done as 
//      the last step of the launch via the Dual Governance proposal
34. Set EXECUTE_ROLE manager to Agent on Agent
```

#### Voting [0x2e59a20f205bb85a89c53f1936454680651e618e](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e)
| Permission | Permission Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`UNSAFELY_MODIFY_VOTE_TIME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNSAFELY_MODIFY_VOTE_TIME_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | ∅ |
| [`MODIFY_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MODIFY_QUORUM_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| [`MODIFY_SUPPORT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MODIFY_SUPPORT_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| [`CREATE_VOTES_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VOTES_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ∅ | [`TokenManager`](https://etherscan.io/address/0xf73a1260d222f447210581ddf212d915c09a3249) |

### OZ Roles
#### ⚠️ WithdrawalQueueERC721 [0x889edc2edab5f40e902b864ad4d7ade8e412f9b1](https://etherscan.io/address/0x889edc2edab5f40e902b864ad4d7ade8e412f9b1)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) [`OraclesGateSeal`](https://etherscan.io/address/0xf9c9fdb4a5d2aa1d836d5370ab9b28bc1847e178) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`FINALIZE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=FINALIZE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Lido`](https://etherscan.io/address/0xae7ab96520de3a18e5e111b5eaab095312d7fe84) |
| [`MANAGE_TOKEN_URI_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_TOKEN_URI_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`ORACLE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ORACLE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`AccountingOracle`](https://etherscan.io/address/0x852ded011285fe67063a08005c71a85690503cee) |

##### Transition Steps

```
35. Grant PAUSE_ROLE to ResealManager on WithdrawalQueueERC721
36. Grant RESUME_ROLE to ResealManager on WithdrawalQueueERC721
```

#### ⚠️ ValidatorsExitBusOracle [0x0de4ea0184c2ad0baca7183356aea5b8d5bf5c6e](https://etherscan.io/address/0x0de4ea0184c2ad0baca7183356aea5b8d5bf5c6e)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) [`OraclesGateSeal`](https://etherscan.io/address/0xf9c9fdb4a5d2aa1d836d5370ab9b28bc1847e178) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`MANAGE_CONSENSUS_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_VERSION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SUBMIT_DATA_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SUBMIT_DATA_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

##### Transition Steps

```
37. Grant PAUSE_ROLE to ResealManager on ValidatorsExitBusOracle
38. Grant RESUME_ROLE to ResealManager on ValidatorsExitBusOracle
```

#### ⚠️ CSModule [0xda7de2ecddfccc6c3af10108db212acbbf9ea83f](https://etherscan.io/address/0xda7de2ecddfccc6c3af10108db212acbbf9ea83f)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) [`CSGateSeal`](https://etherscan.io/address/0x16dbd4b85a448be564f1742d5c8ccdd2bb3185d0) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`MODULE_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MODULE_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REPORT_EL_REWARDS_STEALING_PENALTY_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REPORT_EL_REWARDS_STEALING_PENALTY_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSCommitteeMultisig`](https://etherscan.io/address/0xc52fc3081123073078698f1eac2f1dc7bd71880f) |
| [`SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`EvmScriptExecutor`](https://etherscan.io/address/0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977) |
| [`STAKING_ROUTER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_ROUTER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`StakingRouter`](https://etherscan.io/address/0xfddf38947afb03c621c71b06c9c70bce73f12999) |
| [`VERIFIER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=VERIFIER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSVerifier`](https://etherscan.io/address/0x0c345dfa318f9f4977cdd4f33d80f9d0ffa38e8b) |

##### Transition Steps

```
39. Grant PAUSE_ROLE to ResealManager on CSModule
40. Grant RESUME_ROLE to ResealManager on CSModule
```

#### ⚠️ CSAccounting [0x4d72bff1beac69925f8bd12526a39baab069e5da](https://etherscan.io/address/0x4d72bff1beac69925f8bd12526a39baab069e5da)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) [`CSGateSeal`](https://etherscan.io/address/0x16dbd4b85a448be564f1742d5c8ccdd2bb3185d0) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`ACCOUNTING_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ACCOUNTING_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_BOND_CURVES_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_BOND_CURVES_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`RESET_BOND_CURVE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESET_BOND_CURVE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSModule`](https://etherscan.io/address/0xda7de2ecddfccc6c3af10108db212acbbf9ea83f) [`CSCommitteeMultisig`](https://etherscan.io/address/0xc52fc3081123073078698f1eac2f1dc7bd71880f) |
| [`SET_BOND_CURVE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_BOND_CURVE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSModule`](https://etherscan.io/address/0xda7de2ecddfccc6c3af10108db212acbbf9ea83f) [`CSCommitteeMultisig`](https://etherscan.io/address/0xc52fc3081123073078698f1eac2f1dc7bd71880f) |

##### Transition Steps

```
41. Grant PAUSE_ROLE to ResealManager on CSAccounting
42. Grant RESUME_ROLE to ResealManager on CSAccounting
```

#### ⚠️ CSFeeOracle [0x4d4074628678bd302921c20573eea1ed38ddf7fb](https://etherscan.io/address/0x4d4074628678bd302921c20573eea1ed38ddf7fb)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) [`CSGateSeal`](https://etherscan.io/address/0x16dbd4b85a448be564f1742d5c8ccdd2bb3185d0) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://etherscan.io/address/0x7914b5a1539b97bd0bbd155757f25fd79a522d24) |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`CONTRACT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CONTRACT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_VERSION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SUBMIT_DATA_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SUBMIT_DATA_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

##### Transition Steps

```
43. Grant PAUSE_ROLE to ResealManager on CSFeeOracle
44. Grant RESUME_ROLE to ResealManager on CSFeeOracle
```

#### ⚠️ AllowedTokensRegistry [0x4ac40c34f8992bb1e5e856a448792158022551ca](https://etherscan.io/address/0x4ac40c34f8992bb1e5e856a448792158022551ca)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ⚠️ [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| ⚠️ [`ADD_TOKEN_TO_ALLOWED_LIST_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ADD_TOKEN_TO_ALLOWED_LIST_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ⚠️ [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ∅ |
| ⚠️ [`REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ⚠️ [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ∅ |

##### Transition Steps

```
45. Grant DEFAULT_ADMIN_ROLE to Voting on AllowedTokensRegistry
46. Revoke DEFAULT_ADMIN_ROLE from Agent on AllowedTokensRegistry
47. Revoke ADD_TOKEN_TO_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry
48. Revoke REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry
```

#### StakingRouter [0xfddf38947afb03c621c71b06c9c70bce73f12999](https://etherscan.io/address/0xfddf38947afb03c621c71b06c9c70bce73f12999)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`MANAGE_WITHDRAWAL_CREDENTIALS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_WITHDRAWAL_CREDENTIALS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REPORT_EXITED_VALIDATORS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REPORT_EXITED_VALIDATORS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`AccountingOracle`](https://etherscan.io/address/0x852ded011285fe67063a08005c71a85690503cee) |
| [`REPORT_REWARDS_MINTED_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REPORT_REWARDS_MINTED_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Lido`](https://etherscan.io/address/0xae7ab96520de3a18e5e111b5eaab095312d7fe84) |
| [`STAKING_MODULE_MANAGE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_MODULE_MANAGE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`STAKING_MODULE_UNVETTING_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_MODULE_UNVETTING_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DepositSecurityModule`](https://etherscan.io/address/0xffa96d84def2ea035c7ab153d8b991128e3d72fd) |
| [`UNSAFE_SET_EXITED_VALIDATORS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNSAFE_SET_EXITED_VALIDATORS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### Burner [0xd15a672319cf0352560ee76d9e89eab0889046d3](https://etherscan.io/address/0xd15a672319cf0352560ee76d9e89eab0889046d3)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`REQUEST_BURN_MY_STETH_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REQUEST_BURN_MY_STETH_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`REQUEST_BURN_SHARES_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REQUEST_BURN_SHARES_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Lido`](https://etherscan.io/address/0xae7ab96520de3a18e5e111b5eaab095312d7fe84) [`CuratedModule`](https://etherscan.io/address/0x55032650b14df07b85bf18a3a3ec8e0af2e028d5) [`SimpleDVT`](https://etherscan.io/address/0xae7b191a31f627b4eb1d4dac64eab9976995b433) [`CSAccounting`](https://etherscan.io/address/0x4d72bff1beac69925f8bd12526a39baab069e5da) |

#### AccountingOracle [0x852ded011285fe67063a08005c71a85690503cee](https://etherscan.io/address/0x852ded011285fe67063a08005c71a85690503cee)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`MANAGE_CONSENSUS_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_VERSION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SUBMIT_DATA_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SUBMIT_DATA_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### AccountingOracleHashConsensus [0xd624b08c83baecf0807dd2c6880c3154a5f0b288](https://etherscan.io/address/0xd624b08c83baecf0807dd2c6880c3154a5f0b288)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DISABLE_CONSENSUS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DISABLE_CONSENSUS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FAST_LANE_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FAST_LANE_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FRAME_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FRAME_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_MEMBERS_AND_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_MEMBERS_AND_QUORUM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`MANAGE_REPORT_PROCESSOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_REPORT_PROCESSOR_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### ValidatorsExitBusHashConsensus [0x7fadb6358950c5faa66cb5eb8ee5147de3df355a](https://etherscan.io/address/0x7fadb6358950c5faa66cb5eb8ee5147de3df355a)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DISABLE_CONSENSUS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DISABLE_CONSENSUS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FAST_LANE_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FAST_LANE_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FRAME_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FRAME_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_MEMBERS_AND_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_MEMBERS_AND_QUORUM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`MANAGE_REPORT_PROCESSOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_REPORT_PROCESSOR_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### OracleReportSanityChecker [0x6232397ebac4f5772e53285b26c47914e9461e75](https://etherscan.io/address/0x6232397ebac4f5772e53285b26c47914e9461e75)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`ALL_LIMITS_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ALL_LIMITS_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`APPEARED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=APPEARED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`EXITED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=EXITED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`INITIAL_SLASHING_AND_PENALTIES_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=INITIAL_SLASHING_AND_PENALTIES_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MAX_ITEMS_PER_EXTRA_DATA_TRANSACTION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MAX_ITEMS_PER_EXTRA_DATA_TRANSACTION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MAX_NODE_OPERATORS_PER_EXTRA_DATA_ITEM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MAX_NODE_OPERATORS_PER_EXTRA_DATA_ITEM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MAX_POSITIVE_TOKEN_REBASE_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MAX_POSITIVE_TOKEN_REBASE_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MAX_VALIDATOR_EXIT_REQUESTS_PER_REPORT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MAX_VALIDATOR_EXIT_REQUESTS_PER_REPORT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SECOND_OPINION_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SECOND_OPINION_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SHARE_RATE_DEVIATION_LIMIT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SHARE_RATE_DEVIATION_LIMIT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### OracleDaemonConfig [0xbf05a929c3d7885a6aead833a992da6e5ac23b09](https://etherscan.io/address/0xbf05a929c3d7885a6aead833a992da6e5ac23b09)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`CONFIG_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CONFIG_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### CSFeeDistributor [0xd99cc66fec647e68294c6477b40fc7e0f6f618d0](https://etherscan.io/address/0xd99cc66fec647e68294c6477b40fc7e0f6f618d0)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### CSHashConsensus [0x71093eff8d8599b5fa340d665ad60fa7c80688e4](https://etherscan.io/address/0x71093eff8d8599b5fa340d665ad60fa7c80688e4)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DISABLE_CONSENSUS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DISABLE_CONSENSUS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FAST_LANE_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FAST_LANE_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FRAME_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FRAME_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_MEMBERS_AND_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_MEMBERS_AND_QUORUM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`MANAGE_REPORT_PROCESSOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_REPORT_PROCESSOR_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### EasyTrack [0xf0211b7660680b49de1a7e9f25c65660f0a13fea](https://etherscan.io/address/0xf0211b7660680b49de1a7e9f25c65660f0a13fea)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| [`CANCEL_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CANCEL_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |
| [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`UNPAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNPAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |

#### L1ERC20TokenGateway_Arbitrum [0x0f25c1dc2a9922304f2eac71dca9b07e310e8e5a](https://etherscan.io/address/0x0f25c1dc2a9922304f2eac71dca9b07e310e8e5a)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Optimism [0x76943c0d61395d8f2edf9060e1533529cae05de6](https://etherscan.io/address/0x76943c0d61395d8f2edf9060e1533529cae05de6)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### ERC20Predicate_Polygon [0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf](https://etherscan.io/address/0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`ManagerMultisig_Polygon`](https://etherscan.io/address/0xfa7d2a996ac6350f4b56c043112da0366a59b74c) |
| [`MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`RootChainManagerProxy_Polygon`](https://etherscan.io/address/0xa0c68c638235ee32657e8f720a23cec1bfc77c77) |

#### L1ERC20TokenBridge_Base [0x9de443adc5a411e83f1878ef24c3f52c61571e72](https://etherscan.io/address/0x9de443adc5a411e83f1878ef24c3f52c61571e72)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1ERC20Bridge_zkSync [0x41527b2d03844db6b0945f25702cb958b6d55989](https://etherscan.io/address/0x41527b2d03844db6b0945f25702cb958b6d55989)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1ERC20TokenBridge_Mantle [0x2d001d79e5af5f65a939781fe228b267a8ed468b](https://etherscan.io/address/0x2d001d79e5af5f65a939781fe228b267a8ed468b)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1TokenBridge_Linea [0x051f1d88f0af5763fb888ec4378b4d8b29ea3319](https://etherscan.io/address/0x051f1d88f0af5763fb888ec4378b4d8b29ea3319)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) |
| [`PAUSE_ALL_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ALL_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) |
| [`PAUSE_COMPLETE_TOKEN_BRIDGING_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_COMPLETE_TOKEN_BRIDGING_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) |
| [`PAUSE_INITIATE_TOKEN_BRIDGING_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_INITIATE_TOKEN_BRIDGING_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) |
| [`REMOVE_RESERVED_TOKEN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REMOVE_RESERVED_TOKEN_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) [`L1TokenBridgeManagerMultisig_Linea`](https://etherscan.io/address/0xb8f5524d73f549cf14a0587a3c7810723f9c0051) |
| [`SET_CUSTOM_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_CUSTOM_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) [`L1TokenBridgeManagerMultisig_Linea`](https://etherscan.io/address/0xb8f5524d73f549cf14a0587a3c7810723f9c0051) |
| [`SET_MESSAGE_SERVICE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_MESSAGE_SERVICE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) |
| [`SET_REMOTE_TOKENBRIDGE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_REMOTE_TOKENBRIDGE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) |
| [`SET_RESERVED_TOKEN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_RESERVED_TOKEN_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) [`L1TokenBridgeManagerMultisig_Linea`](https://etherscan.io/address/0xb8f5524d73f549cf14a0587a3c7810723f9c0051) |
| [`UNPAUSE_ALL_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNPAUSE_ALL_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) |
| [`UNPAUSE_COMPLETE_TOKEN_BRIDGING_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNPAUSE_COMPLETE_TOKEN_BRIDGING_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) |
| [`UNPAUSE_INITIATE_TOKEN_BRIDGING_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNPAUSE_INITIATE_TOKEN_BRIDGING_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`LineaSecurityCouncil_Linea`](https://etherscan.io/address/0x892bb7eed71efb060ab90140e7825d8127991dd3) |

#### L1LidoGateway_Scroll [0x6625c6332c9f91f2d27c304e729b86db87a3f504](https://etherscan.io/address/0x6625c6332c9f91f2d27c304e729b86db87a3f504)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `owner` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `owner` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `owner` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `owner` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

> [!NOTE]
> The Scroll implementation of `L1LidoGateway` uses a custom Access Control mechanism in which the granting of all roles is managed by a dedicated `owner` address.

#### L1ERC20TokenBridge_Mode [0xd0dea0a3bd8e4d55170943129c025d3fe0493f2a](https://etherscan.io/address/0xd0dea0a3bd8e4d55170943129c025d3fe0493f2a)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1ERC20TokenBridge_Zircuit [0x912c7271a6a3622dfb8b218eb46a6122ab046c79](https://etherscan.io/address/0x912c7271a6a3622dfb8b218eb46a6122ab046c79)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Soneium [0x2f543a7c9cc80cc2427c892b96263098d23ee55a](https://etherscan.io/address/0x2f543a7c9cc80cc2427c892b96263098d23ee55a)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Unichain [0x755610f5be536ad7afbaa7c10f3e938ea3aa1877](https://etherscan.io/address/0x755610f5be536ad7afbaa7c10f3e938ea3aa1877)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Lisk [0x9348af23b01f2b517afe8f29b3183d2bb7d69fcf](https://etherscan.io/address/0x9348af23b01f2b517afe8f29b3183d2bb7d69fcf)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Swellchain [0xecf3376512edaca4fbb63d2c67d12a0397d24121](https://etherscan.io/address/0xecf3376512edaca4fbb63d2c67d12a0397d24121)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`DEPOSITS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`DEPOSITS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DEPOSITS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| [`WITHDRAWALS_DISABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_DISABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) [`EmergencyBrakesMultisig`](https://etherscan.io/address/0x73b047fe6337183a454c5217241d780a932777bd) |
| [`WITHDRAWALS_ENABLER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=WITHDRAWALS_ENABLER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

### Contracts Ownership
#### ⚠️ WithdrawalVault [0xb9d7934878b5fb9610b3fe8a5e441e8fad7e293f](https://etherscan.io/address/0xb9d7934878b5fb9610b3fe8a5e441e8fad7e293f)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| ⚠️ `proxy_getAdmin` | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | ⚠️ [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

##### Transition Steps

```
49. Set admin to Agent on WithdrawalVault
```

#### ⚠️ InsuranceFund [0x8b3f33234abd88493c0cd28de33d583b70bede35](https://etherscan.io/address/0x8b3f33234abd88493c0cd28de33d583b70bede35)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| ⚠️ `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | ⚠️ [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |

##### Transition Steps

```
50. Set owner to Voting on InsuranceFund
```

#### DepositSecurityModule [0xffa96d84def2ea035c7ab153d8b991128e3d72fd](https://etherscan.io/address/0xffa96d84def2ea035c7ab153d8b991128e3d72fd)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `getOwner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### LidoLocator [0xc1d0b3de6792bf6b4b37eccdcc24e45978cfd2eb](https://etherscan.io/address/0xc1d0b3de6792bf6b4b37eccdcc24e45978cfd2eb)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### StakingRouter [0xfddf38947afb03c621c71b06c9c70bce73f12999](https://etherscan.io/address/0xfddf38947afb03c621c71b06c9c70bce73f12999)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### WithdrawalQueueERC721 [0x889edc2edab5f40e902b864ad4d7ade8e412f9b1](https://etherscan.io/address/0x889edc2edab5f40e902b864ad4d7ade8e412f9b1)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### AccountingOracle [0x852ded011285fe67063a08005c71a85690503cee](https://etherscan.io/address/0x852ded011285fe67063a08005c71a85690503cee)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### ValidatorsExitBusOracle [0x0de4ea0184c2ad0baca7183356aea5b8d5bf5c6e](https://etherscan.io/address/0x0de4ea0184c2ad0baca7183356aea5b8d5bf5c6e)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### MEVBoostRelayAllowedList [0xf95f069f9ad107938f6ba802a3da87892298610e](https://etherscan.io/address/0xf95f069f9ad107938f6ba802a3da87892298610e)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `get_owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### CSModule [0xda7de2ecddfccc6c3af10108db212acbbf9ea83f](https://etherscan.io/address/0xda7de2ecddfccc6c3af10108db212acbbf9ea83f)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### CSAccounting [0x4d72bff1beac69925f8bd12526a39baab069e5da](https://etherscan.io/address/0x4d72bff1beac69925f8bd12526a39baab069e5da)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### CSFeeDistributor [0xd99cc66fec647e68294c6477b40fc7e0f6f618d0](https://etherscan.io/address/0xd99cc66fec647e68294c6477b40fc7e0f6f618d0)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### CSFeeOracle [0x4d4074628678bd302921c20573eea1ed38ddf7fb](https://etherscan.io/address/0x4d4074628678bd302921c20573eea1ed38ddf7fb)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### AnchorVault [0xa2f987a546d4cd1c607ee8141276876c26b72bdf](https://etherscan.io/address/0xa2f987a546d4cd1c607ee8141276876c26b72bdf)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `admin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| `proxy_getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### bETH [0x707f9118e33a9b8998bea41dd0d46f38bb963fc8](https://etherscan.io/address/0x707f9118e33a9b8998bea41dd0d46f38bb963fc8)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `admin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### VestingEscrowFactory [0xda1df6442afd2ec36abea91029794b9b2156add0](https://etherscan.io/address/0xda1df6442afd2ec36abea91029794b9b2156add0)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### EvmScriptExecutor [0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977](https://etherscan.io/address/0xfe5986e06210ac1ecc1adcafc0cc7f8d63b3f977)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) | [`Voting`](https://etherscan.io/address/0x2e59a20f205bb85a89c53f1936454680651e618e) |

#### L1ERC20TokenGateway_Arbitrum [0x0f25c1dc2a9922304f2eac71dca9b07e310e8e5a](https://etherscan.io/address/0x0f25c1dc2a9922304f2eac71dca9b07e310e8e5a)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Optimism [0x76943c0d61395d8f2edf9060e1533529cae05de6](https://etherscan.io/address/0x76943c0d61395d8f2edf9060e1533529cae05de6)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### TokenRateNotifier_Optimism [0xe6793b9e4fba7de0ee833f9d02bba7db5eb27823](https://etherscan.io/address/0xe6793b9e4fba7de0ee833f9d02bba7db5eb27823)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### ERC20Predicate_Polygon [0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf](https://etherscan.io/address/0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxyOwner` | [`Timelock_Polygon`](https://etherscan.io/address/0xcaf0aa768a3ae1297df20072419db8bb8b5c8cef) | [`Timelock_Polygon`](https://etherscan.io/address/0xcaf0aa768a3ae1297df20072419db8bb8b5c8cef) |

#### RootChainManagerProxy_Polygon [0xa0c68c638235ee32657e8f720a23cec1bfc77c77](https://etherscan.io/address/0xa0c68c638235ee32657e8f720a23cec1bfc77c77)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxyOwner` | [`Timelock_Polygon`](https://etherscan.io/address/0xcaf0aa768a3ae1297df20072419db8bb8b5c8cef) | [`Timelock_Polygon`](https://etherscan.io/address/0xcaf0aa768a3ae1297df20072419db8bb8b5c8cef) |

#### L1ERC20TokenBridge_Base [0x9de443adc5a411e83f1878ef24c3f52c61571e72](https://etherscan.io/address/0x9de443adc5a411e83f1878ef24c3f52c61571e72)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1Executor_zkSync [0xff7f4d05e3247374e86a3f7231a2ed1ca63647f2](https://etherscan.io/address/0xff7f4d05e3247374e86a3f7231a2ed1ca63647f2)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1ERC20Bridge_zkSync [0x41527b2d03844db6b0945f25702cb958b6d55989](https://etherscan.io/address/0x41527b2d03844db6b0945f25702cb958b6d55989)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1ERC20TokenBridge_Mantle [0x2d001d79e5af5f65a939781fe228b267a8ed468b](https://etherscan.io/address/0x2d001d79e5af5f65a939781fe228b267a8ed468b)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1TokenBridgeProxyAdmin_Linea [0xf5058616517c068c7b8c7ebc69ff636ade9066d6](https://etherscan.io/address/0xf5058616517c068c7b8c7ebc69ff636ade9066d6)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`ProxyAdminTimelock_Linea`](https://etherscan.io/address/0xd6b95c960779c72b8c6752119849318e5d550574) | [`ProxyAdminTimelock_Linea`](https://etherscan.io/address/0xd6b95c960779c72b8c6752119849318e5d550574) |

#### L1LidoGateway_Scroll [0x6625c6332c9f91f2d27c304e729b86db87a3f504](https://etherscan.io/address/0x6625c6332c9f91f2d27c304e729b86db87a3f504)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoGatewayProxyAdmin_Scroll [0xcc2c53556bc75217cf698721b29071d6f12628a9](https://etherscan.io/address/0xcc2c53556bc75217cf698721b29071d6f12628a9)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1ERC20TokenBridge_Mode [0xd0dea0a3bd8e4d55170943129c025d3fe0493f2a](https://etherscan.io/address/0xd0dea0a3bd8e4d55170943129c025d3fe0493f2a)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### CrossChainController_BSC [0x93559892d3c7f66de4570132d68b69bd3c369a7c](https://etherscan.io/address/0x93559892d3c7f66de4570132d68b69bd3c369a7c)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### CrossChainControllerProxyAdmin_BSC [0xadd673dc6a655afd6f38fb88301028fa31a6fdee](https://etherscan.io/address/0xadd673dc6a655afd6f38fb88301028fa31a6fdee)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### AxelarTransceiver_BSC [0x723aead29acee7e9281c32d11ea4ed0070c41b13](https://etherscan.io/address/0x723aead29acee7e9281c32d11ea4ed0070c41b13)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### WormholeTransceiver_BSC [0xa1acc1e6edab281febd91e3515093f1de81f25c0](https://etherscan.io/address/0xa1acc1e6edab281febd91e3515093f1de81f25c0)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### NTTManager_BSC [0xb948a93827d68a82f6513ad178964da487fe2bd9](https://etherscan.io/address/0xb948a93827d68a82f6513ad178964da487fe2bd9)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `owner` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1ERC20TokenBridge_Zircuit [0x912c7271a6a3622dfb8b218eb46a6122ab046c79](https://etherscan.io/address/0x912c7271a6a3622dfb8b218eb46a6122ab046c79)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Soneium [0x2f543a7c9cc80cc2427c892b96263098d23ee55a](https://etherscan.io/address/0x2f543a7c9cc80cc2427c892b96263098d23ee55a)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Unichain [0x755610f5be536ad7afbaa7c10f3e938ea3aa1877](https://etherscan.io/address/0x755610f5be536ad7afbaa7c10f3e938ea3aa1877)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Lisk [0x9348af23b01f2b517afe8f29b3183d2bb7d69fcf](https://etherscan.io/address/0x9348af23b01f2b517afe8f29b3183d2bb7d69fcf)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

#### L1LidoTokensBridge_Swellchain [0xecf3376512edaca4fbb63d2c67d12a0397d24121](https://etherscan.io/address/0xecf3376512edaca4fbb63d2c67d12a0397d24121)
| Getter | Actual Value | Expected Value |
| --- | --- | --- |
| `proxy__getAdmin` | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) | [`Agent`](https://etherscan.io/address/0x3e40d73eb977dc6a537af587d48316fee66e9c8c) |

