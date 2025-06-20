# Dual Governance upgrade (permission transitions for Hoodi)

Due to the Dual Governance upgrade, some roles need to be reassigned in accordance with the current state of the Lido protocol on Mainnet. You can read more about the upgrade at the following [link](./permissions-transition-mainnet.md).

During active protocol testing in the testnet, some roles were assigned to EOAs or multisigs, as reflected in the table. It was decided not to modify these addresses (i.e., not to revoke or grant roles) but only to transfer the necessary permissions from the voting contract to the agent, following the Mainnet plan.

## Permissions Transition Plan (Hoodi)

> - Data was collected at block [`328437`](https://hoodi.etherscan.io//block/328437)
> - The last permissions change occurred at block [`303487`](https://hoodi.etherscan.io//block/303487), transaction [`0xc14fab41be2e07b7c0e0320c3750c466db88db0a01214228e62e6ae9422bdba3`](https://hoodi.etherscan.io//tx/0xc14fab41be2e07b7c0e0320c3750c466db88db0a01214228e62e6ae9422bdba3)

How to read this document:
- If an item is prepended with the "⚠️" icon, it indicates that the item will be changed. The required updates are described in the corresponding "Transition Steps" sections.
- The special symbol "∅" indicates that:
  - a permission or role is not granted to any address
  - revocation of the permission or role is not performed
  - no manager is set for the permission
- The notation "`Old Manager` → `New Manager`" means the current manager is being changed to a new one.
  - A special case is "`∅` → `New Manager`", which means the permission currently has no manager, and the permission should be created before use.

### Aragon Permissions
#### ⚠️ Lido [0x3508a952176b3c15387c97be809eaffb1982176a](https://hoodi.etherscan.io//address/0x3508a952176b3c15387c97be809eaffb1982176a)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`STAKING_CONTROL_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_CONTROL_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | [`UnlimitedStake`](https://hoodi.etherscan.io//address/0x064a4d64040bfd52d0d1dc7f42ea799cb0a8ac40) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ |
| ⚠️ [`UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ |
| ⚠️ [`STAKING_PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_PAUSE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ |

##### Transition Steps

```
1. Revoke STAKING_CONTROL_ROLE permission from Voting on Lido
2. Set STAKING_CONTROL_ROLE manager to Agent on Lido
3. Revoke RESUME_ROLE permission from Voting on Lido
4. Set RESUME_ROLE manager to Agent on Lido
5. Revoke PAUSE_ROLE permission from Voting on Lido
6. Set PAUSE_ROLE manager to Agent on Lido
7. Revoke UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE permission from Voting on Lido
8. Set UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE manager to Agent on Lido
9. Revoke STAKING_PAUSE_ROLE permission from Voting on Lido
10. Set STAKING_PAUSE_ROLE manager to Agent on Lido
```

#### ⚠️ DAOKernel [0xa48df029fd2e5fcecb3886c5c2f60e3625a1e87d](https://hoodi.etherscan.io//address/0xa48df029fd2e5fcecb3886c5c2f60e3625a1e87d)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`APP_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=APP_MANAGER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ |

##### Transition Steps

```
11. Revoke APP_MANAGER_ROLE permission from Voting on DAOKernel
12. Set APP_MANAGER_ROLE manager to Agent on DAOKernel
```

#### ⚠️ Voting [0x49b3512c44891bef83f8967d075121bd1b07a01b](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`UNSAFELY_MODIFY_VOTE_TIME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNSAFELY_MODIFY_VOTE_TIME_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| [`MODIFY_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MODIFY_QUORUM_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| [`MODIFY_SUPPORT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MODIFY_SUPPORT_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| [`CREATE_VOTES_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VOTES_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | [`TokenManager`](https://hoodi.etherscan.io//address/0x8ab4a56721ad8e68c6ad86f9d9929782a78e39e5) |

##### Transition Steps

```
13. Create UNSAFELY_MODIFY_VOTE_TIME_ROLE permission on Voting with manager Voting and grant it to Voting
```

#### ⚠️ TokenManager [0x8ab4a56721ad8e68c6ad86f9d9929782a78e39e5](https://hoodi.etherscan.io//address/0x8ab4a56721ad8e68c6ad86f9d9929782a78e39e5)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`MINT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MINT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| ⚠️ [`REVOKE_VESTINGS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REVOKE_VESTINGS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| ⚠️ [`BURN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=BURN_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| ⚠️ [`ISSUE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ISSUE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| [`ASSIGN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ASSIGN_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |

##### Transition Steps

```
14. Create MINT_ROLE permission on TokenManager with manager Voting and grant it to Voting
15. Create REVOKE_VESTINGS_ROLE permission on TokenManager with manager Voting and grant it to Voting
16. Create BURN_ROLE permission on TokenManager with manager Voting and grant it to Voting
17. Create ISSUE_ROLE permission on TokenManager with manager Voting and grant it to Voting
```

#### ⚠️ Finance [0x254ae22beeba64127f0e59fe8593082f3cd13f6b](https://hoodi.etherscan.io//address/0x254ae22beeba64127f0e59fe8593082f3cd13f6b)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`CHANGE_PERIOD_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CHANGE_PERIOD_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| ⚠️ [`CHANGE_BUDGETS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CHANGE_BUDGETS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| [`CREATE_PAYMENTS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_PAYMENTS_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) [`EvmScriptExecutor`](https://hoodi.etherscan.io//address/0x79a20fd0fa36453b2f45eabab19bfef43575ba9e) |
| [`EXECUTE_PAYMENTS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=EXECUTE_PAYMENTS_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| [`MANAGE_PAYMENTS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_PAYMENTS_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |

##### Transition Steps

```
18. Create CHANGE_PERIOD_ROLE permission on Finance with manager Voting and grant it to Voting
19. Create CHANGE_BUDGETS_ROLE permission on Finance with manager Voting and grant it to Voting
```

#### ⚠️ EVMScriptRegistry [0xe4d32427b1f9b12ab89b142ed3714dcaabb3f38c](https://hoodi.etherscan.io//address/0xe4d32427b1f9b12ab89b142ed3714dcaabb3f38c)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`REGISTRY_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REGISTRY_MANAGER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ |
| ⚠️ [`REGISTRY_ADD_EXECUTOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REGISTRY_ADD_EXECUTOR_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ |

##### Transition Steps

```
20. Revoke REGISTRY_MANAGER_ROLE permission from Voting on EVMScriptRegistry
21. Set REGISTRY_MANAGER_ROLE manager to Agent on EVMScriptRegistry
22. Revoke REGISTRY_ADD_EXECUTOR_ROLE permission from Voting on EVMScriptRegistry
23. Set REGISTRY_ADD_EXECUTOR_ROLE manager to Agent on EVMScriptRegistry
```

#### ⚠️ CuratedModule [0x5cdbe1590c083b5a2a64427faa63a7cfdb91fbb5](https://hoodi.etherscan.io//address/0x5cdbe1590c083b5a2a64427faa63a7cfdb91fbb5)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`STAKING_ROUTER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_ROUTER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ∅ | [`StakingRouter`](https://hoodi.etherscan.io//address/0xcc820558b39ee15c7c45b59390b503b83fb499a8) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA2`](https://hoodi.etherscan.io//address/0xf865a1d43d36c713b4da085f32b7d1e9739b9275) |
| ⚠️ [`MANAGE_NODE_OPERATOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_NODE_OPERATOR_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA2`](https://hoodi.etherscan.io//address/0xf865a1d43d36c713b4da085f32b7d1e9739b9275) |
| ⚠️ [`SET_NODE_OPERATOR_LIMIT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_NODE_OPERATOR_LIMIT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA2`](https://hoodi.etherscan.io//address/0xf865a1d43d36c713b4da085f32b7d1e9739b9275) [`EvmScriptExecutor`](https://hoodi.etherscan.io//address/0x79a20fd0fa36453b2f45eabab19bfef43575ba9e) |
| ⚠️ [`MANAGE_SIGNING_KEYS`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_SIGNING_KEYS&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA2`](https://hoodi.etherscan.io//address/0xf865a1d43d36c713b4da085f32b7d1e9739b9275) |

##### Transition Steps

```
24. Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule
25. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on CuratedModule
26. Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on CuratedModule
27. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on CuratedModule
28. Revoke MANAGE_SIGNING_KEYS permission from Voting on CuratedModule
29. Set MANAGE_SIGNING_KEYS manager to Agent on CuratedModule
```

#### ⚠️ SimpleDVT [0x0b5236beca68004db89434462dfc3bb074d2c830](https://hoodi.etherscan.io//address/0x0b5236beca68004db89434462dfc3bb074d2c830)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`STAKING_ROUTER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_ROUTER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | [`StakingRouter`](https://hoodi.etherscan.io//address/0xcc820558b39ee15c7c45b59390b503b83fb499a8) [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) [`DevEOA2`](https://hoodi.etherscan.io//address/0xf865a1d43d36c713b4da085f32b7d1e9739b9275) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`EvmScriptExecutor`](https://hoodi.etherscan.io//address/0x79a20fd0fa36453b2f45eabab19bfef43575ba9e) |
| ⚠️ [`MANAGE_NODE_OPERATOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_NODE_OPERATOR_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | [`DevEOA2`](https://hoodi.etherscan.io//address/0xf865a1d43d36c713b4da085f32b7d1e9739b9275) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`EvmScriptExecutor`](https://hoodi.etherscan.io//address/0x79a20fd0fa36453b2f45eabab19bfef43575ba9e) |
| ⚠️ [`SET_NODE_OPERATOR_LIMIT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_NODE_OPERATOR_LIMIT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | [`DevEOA2`](https://hoodi.etherscan.io//address/0xf865a1d43d36c713b4da085f32b7d1e9739b9275) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`EvmScriptExecutor`](https://hoodi.etherscan.io//address/0x79a20fd0fa36453b2f45eabab19bfef43575ba9e) |
| [`MANAGE_SIGNING_KEYS`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_SIGNING_KEYS&input_type=utf-8&output_type=hex) | [`EvmScriptExecutor`](https://hoodi.etherscan.io//address/0x79a20fd0fa36453b2f45eabab19bfef43575ba9e) | ∅ | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) [`DevEOA2`](https://hoodi.etherscan.io//address/0xf865a1d43d36c713b4da085f32b7d1e9739b9275) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) |

##### Transition Steps

```
30. Revoke STAKING_ROUTER_ROLE permission from Voting on SimpleDVT
31. Set STAKING_ROUTER_ROLE manager to Agent on SimpleDVT
32. Revoke MANAGE_NODE_OPERATOR_ROLE permission from Voting on SimpleDVT
33. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on SimpleDVT
34. Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on SimpleDVT
35. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on SimpleDVT
```

#### ⚠️ ACL [0x78780e70eae33e2935814a327f7db6c01136cc62](https://hoodi.etherscan.io//address/0x78780e70eae33e2935814a327f7db6c01136cc62)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`CREATE_PERMISSIONS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_PERMISSIONS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ⚠️ [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |

##### Transition Steps

```
36. Grant CREATE_PERMISSIONS_ROLE permission to Agent on ACL
37. Revoke CREATE_PERMISSIONS_ROLE permission from Voting on ACL
38. Set CREATE_PERMISSIONS_ROLE manager to Agent on ACL
```

#### ⚠️ Agent [0x0534aa41907c9631fae990960bcc72d75fa7cfed](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`RUN_SCRIPT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RUN_SCRIPT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ⚠️ [`DGAdminExecutor`](https://hoodi.etherscan.io//address/0x) ⚠️ [`DevAgentManager`](https://hoodi.etherscan.io//address/0xd500a8adb182f55741e267730dfbfb4f1944c205) |
| ⚠️ [`EXECUTE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=EXECUTE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) → [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ⚠️ [`DGAdminExecutor`](https://hoodi.etherscan.io//address/0x) |
| [`TRANSFER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=TRANSFER_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ∅ | [`Finance`](https://hoodi.etherscan.io//address/0x254ae22beeba64127f0e59fe8593082f3cd13f6b) |
| [`SAFE_EXECUTE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SAFE_EXECUTE_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`DESIGNATE_SIGNER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DESIGNATE_SIGNER_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`ADD_PRESIGNED_HASH_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ADD_PRESIGNED_HASH_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`ADD_PROTECTED_TOKEN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ADD_PROTECTED_TOKEN_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`REMOVE_PROTECTED_TOKEN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REMOVE_PROTECTED_TOKEN_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

##### Transition Steps

```
39. Grant RUN_SCRIPT_ROLE permission to DGAdminExecutor on Agent
40. Grant RUN_SCRIPT_ROLE permission to DevAgentManager on Agent
// SKIPPED: __. Revoke RUN_SCRIPT_ROLE permission from Voting on Agent - Will be done as 
//      the last step of the launch via the Dual Governance proposal
41. Set RUN_SCRIPT_ROLE manager to Agent on Agent
42. Grant EXECUTE_ROLE permission to DGAdminExecutor on Agent
// SKIPPED: __. Revoke EXECUTE_ROLE permission from Voting on Agent - Will be done as 
//      the last step of the launch via the Dual Governance proposal
43. Set EXECUTE_ROLE manager to Agent on Agent
```

#### AragonPM [0x948ffb5fda2961c60ed3eb84c7a31aae42ebedcc](https://hoodi.etherscan.io//address/0x948ffb5fda2961c60ed3eb84c7a31aae42ebedcc)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_REPO_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_REPO_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### VotingRepo [0xc972cdea5956482ef35bf5852601dd458353cebd](https://hoodi.etherscan.io//address/0xc972cdea5956482ef35bf5852601dd458353cebd)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### LidoRepo [0xd3545ac0286a94970bacc41d3af676b89606204f](https://hoodi.etherscan.io//address/0xd3545ac0286a94970bacc41d3af676b89606204f)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### LegacyOracleRepo [0x5b70b650b7e14136eb141b5bf46a52f962885752](https://hoodi.etherscan.io//address/0x5b70b650b7e14136eb141b5bf46a52f962885752)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### CuratedModuleRepo [0x5cdbe1590c083b5a2a64427faa63a7cfdb91fbb5](https://hoodi.etherscan.io//address/0x5cdbe1590c083b5a2a64427faa63a7cfdb91fbb5)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### SimpleDVTRepo [0x0b5236beca68004db89434462dfc3bb074d2c830](https://hoodi.etherscan.io//address/0x0b5236beca68004db89434462dfc3bb074d2c830)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

### OZ Roles
#### ⚠️ WithdrawalQueueERC721 [0xfe56573178f1bcdf53f01a6e9977670dcbbd9186](https://hoodi.etherscan.io//address/0xfe56573178f1bcdf53f01a6e9977670dcbbd9186)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://hoodi.etherscan.io//address/0x) [`OraclesGateSeal`](https://hoodi.etherscan.io//address/0x2168ea6d948ab49c3d34c667a7e02f92369f3a9c) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://hoodi.etherscan.io//address/0x) [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`FINALIZE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=FINALIZE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Lido`](https://hoodi.etherscan.io//address/0x3508a952176b3c15387c97be809eaffb1982176a) |
| [`MANAGE_TOKEN_URI_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_TOKEN_URI_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`ORACLE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ORACLE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`AccountingOracle`](https://hoodi.etherscan.io//address/0xcb883b1bd0a41512b42d2db267f2a2cd919fb216) |

##### Transition Steps

```
44. Grant PAUSE_ROLE to ResealManager on WithdrawalQueueERC721
45. Grant RESUME_ROLE to ResealManager on WithdrawalQueueERC721
```

#### ⚠️ ValidatorsExitBusOracle [0x8664d394c2b3278f26a1b44b967aef99707eeab2](https://hoodi.etherscan.io//address/0x8664d394c2b3278f26a1b44b967aef99707eeab2)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://hoodi.etherscan.io//address/0x) [`OraclesGateSeal`](https://hoodi.etherscan.io//address/0x2168ea6d948ab49c3d34c667a7e02f92369f3a9c) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://hoodi.etherscan.io//address/0x) [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`MANAGE_CONSENSUS_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_VERSION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SUBMIT_DATA_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SUBMIT_DATA_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

##### Transition Steps

```
46. Grant PAUSE_ROLE to ResealManager on ValidatorsExitBusOracle
47. Grant RESUME_ROLE to ResealManager on ValidatorsExitBusOracle
```

#### ⚠️ AllowedTokensRegistry [0x40db7e8047c487bd8359289272c717ea3c34d1d3](https://hoodi.etherscan.io//address/0x40db7e8047c487bd8359289272c717ea3c34d1d3)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ⚠️ [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ⚠️ [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| ⚠️ [`ADD_TOKEN_TO_ALLOWED_LIST_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ADD_TOKEN_TO_ALLOWED_LIST_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ⚠️ [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ∅ |
| ⚠️ [`REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ⚠️ [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | ∅ |

##### Transition Steps

```
48. Grant DEFAULT_ADMIN_ROLE to Voting on AllowedTokensRegistry
49. Revoke DEFAULT_ADMIN_ROLE from Agent on AllowedTokensRegistry
50. Revoke ADD_TOKEN_TO_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry
51. Revoke REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry
```

#### StakingRouter [0xcc820558b39ee15c7c45b59390b503b83fb499a8](https://hoodi.etherscan.io//address/0xcc820558b39ee15c7c45b59390b503b83fb499a8)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`MANAGE_WITHDRAWAL_CREDENTIALS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_WITHDRAWAL_CREDENTIALS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REPORT_EXITED_VALIDATORS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REPORT_EXITED_VALIDATORS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`AccountingOracle`](https://hoodi.etherscan.io//address/0xcb883b1bd0a41512b42d2db267f2a2cd919fb216) |
| [`REPORT_REWARDS_MINTED_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REPORT_REWARDS_MINTED_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Lido`](https://hoodi.etherscan.io//address/0x3508a952176b3c15387c97be809eaffb1982176a) |
| [`STAKING_MODULE_MANAGE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_MODULE_MANAGE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) |
| [`STAKING_MODULE_UNVETTING_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_MODULE_UNVETTING_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DepositSecurityModule`](https://hoodi.etherscan.io//address/0x2f0303f20e0795e6ccd17bd5efe791a586f28e03) |
| [`UNSAFE_SET_EXITED_VALIDATORS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNSAFE_SET_EXITED_VALIDATORS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### Burner [0x4e9a9ea2f154ba34be919cd16a4a953dcd888165](https://hoodi.etherscan.io//address/0x4e9a9ea2f154ba34be919cd16a4a953dcd888165)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`REQUEST_BURN_MY_STETH_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REQUEST_BURN_MY_STETH_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REQUEST_BURN_SHARES_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REQUEST_BURN_SHARES_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Lido`](https://hoodi.etherscan.io//address/0x3508a952176b3c15387c97be809eaffb1982176a) [`CuratedModuleRepo`](https://hoodi.etherscan.io//address/0x5cdbe1590c083b5a2a64427faa63a7cfdb91fbb5) [`SimpleDVTRepo`](https://hoodi.etherscan.io//address/0x0b5236beca68004db89434462dfc3bb074d2c830) [`SandboxStakingModule`](https://hoodi.etherscan.io//address/0x682e94d2630846a503bdee8b6810df71c9806891) [`CSAccounting`](https://hoodi.etherscan.io//address/0xa54b90ba34c5f326bc1485054080994e38fb4c60) |

#### AccountingOracle [0xcb883b1bd0a41512b42d2db267f2a2cd919fb216](https://hoodi.etherscan.io//address/0xcb883b1bd0a41512b42d2db267f2a2cd919fb216)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`MANAGE_CONSENSUS_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_VERSION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SUBMIT_DATA_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SUBMIT_DATA_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### AccountingOracleHashConsensus [0x32ec59a78abaca3f91527aeb2008925d5aac1efc](https://hoodi.etherscan.io//address/0x32ec59a78abaca3f91527aeb2008925d5aac1efc)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`DISABLE_CONSENSUS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DISABLE_CONSENSUS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FAST_LANE_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FAST_LANE_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA3`](https://hoodi.etherscan.io//address/0x4022e0754d0cb6905b54306105d3346d1547988b) |
| [`MANAGE_FRAME_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FRAME_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA3`](https://hoodi.etherscan.io//address/0x4022e0754d0cb6905b54306105d3346d1547988b) |
| [`MANAGE_MEMBERS_AND_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_MEMBERS_AND_QUORUM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA3`](https://hoodi.etherscan.io//address/0x4022e0754d0cb6905b54306105d3346d1547988b) |
| [`MANAGE_REPORT_PROCESSOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_REPORT_PROCESSOR_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### ValidatorsExitBusHashConsensus [0x30308cd8844fb2db3ec4d056f1d475a802dca07c](https://hoodi.etherscan.io//address/0x30308cd8844fb2db3ec4d056f1d475a802dca07c)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`DISABLE_CONSENSUS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DISABLE_CONSENSUS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FAST_LANE_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FAST_LANE_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA3`](https://hoodi.etherscan.io//address/0x4022e0754d0cb6905b54306105d3346d1547988b) |
| [`MANAGE_FRAME_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FRAME_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA3`](https://hoodi.etherscan.io//address/0x4022e0754d0cb6905b54306105d3346d1547988b) |
| [`MANAGE_MEMBERS_AND_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_MEMBERS_AND_QUORUM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`DevEOA3`](https://hoodi.etherscan.io//address/0x4022e0754d0cb6905b54306105d3346d1547988b) |
| [`MANAGE_REPORT_PROCESSOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_REPORT_PROCESSOR_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### OracleReportSanityChecker [0x26aed10459e1096d242abf251ff55f8deaf52348](https://hoodi.etherscan.io//address/0x26aed10459e1096d242abf251ff55f8deaf52348)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`ALL_LIMITS_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ALL_LIMITS_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) |
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

#### OracleDaemonConfig [0x2a833402e3f46ffc1ecab3598c599147a78731a9](https://hoodi.etherscan.io//address/0x2a833402e3f46ffc1ecab3598c599147a78731a9)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`CONFIG_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CONFIG_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) |

#### CSModule [0x79cef36d84743222f37765204bec41e92a93e59d](https://hoodi.etherscan.io//address/0x79cef36d84743222f37765204bec41e92a93e59d)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSMDevEOA`](https://hoodi.etherscan.io//address/0x4af43ee34a6fcd1feca1e1f832124c763561da53) [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`MODULE_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MODULE_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSGateSeal`](https://hoodi.etherscan.io//address/0xee1f7f0ebb5900f348f2cfbcc641fb1681359b8a) |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REPORT_EL_REWARDS_STEALING_PENALTY_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REPORT_EL_REWARDS_STEALING_PENALTY_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSMDevEOA`](https://hoodi.etherscan.io//address/0x4af43ee34a6fcd1feca1e1f832124c763561da53) |
| [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`EvmScriptExecutor`](https://hoodi.etherscan.io//address/0x79a20fd0fa36453b2f45eabab19bfef43575ba9e) |
| [`STAKING_ROUTER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_ROUTER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`StakingRouter`](https://hoodi.etherscan.io//address/0xcc820558b39ee15c7c45b59390b503b83fb499a8) |
| [`VERIFIER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=VERIFIER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSVerifier`](https://hoodi.etherscan.io//address/0xb6bafbd970a4537077de59cebe33081d794513d6) |

#### CSAccounting [0xa54b90ba34c5f326bc1485054080994e38fb4c60](https://hoodi.etherscan.io//address/0xa54b90ba34c5f326bc1485054080994e38fb4c60)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSMDevEOA`](https://hoodi.etherscan.io//address/0x4af43ee34a6fcd1feca1e1f832124c763561da53) [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`ACCOUNTING_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ACCOUNTING_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_BOND_CURVES_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_BOND_CURVES_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSGateSeal`](https://hoodi.etherscan.io//address/0xee1f7f0ebb5900f348f2cfbcc641fb1681359b8a) |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`RESET_BOND_CURVE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESET_BOND_CURVE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSModule`](https://hoodi.etherscan.io//address/0x79cef36d84743222f37765204bec41e92a93e59d) [`CSMDevEOA`](https://hoodi.etherscan.io//address/0x4af43ee34a6fcd1feca1e1f832124c763561da53) |
| [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SET_BOND_CURVE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_BOND_CURVE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSModule`](https://hoodi.etherscan.io//address/0x79cef36d84743222f37765204bec41e92a93e59d) [`CSMDevEOA`](https://hoodi.etherscan.io//address/0x4af43ee34a6fcd1feca1e1f832124c763561da53) |

#### CSFeeDistributor [0xacd9820b0a2229a82dc1a0770307ce5522ff3582](https://hoodi.etherscan.io//address/0xacd9820b0a2229a82dc1a0770307ce5522ff3582)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSMDevEOA`](https://hoodi.etherscan.io//address/0x4af43ee34a6fcd1feca1e1f832124c763561da53) [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### CSFeeOracle [0xe7314f561b2e72f9543f1004e741bab6fc51028b](https://hoodi.etherscan.io//address/0xe7314f561b2e72f9543f1004e741bab6fc51028b)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSMDevEOA`](https://hoodi.etherscan.io//address/0x4af43ee34a6fcd1feca1e1f832124c763561da53) [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`CONTRACT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CONTRACT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_VERSION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSGateSeal`](https://hoodi.etherscan.io//address/0xee1f7f0ebb5900f348f2cfbcc641fb1681359b8a) |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SUBMIT_DATA_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SUBMIT_DATA_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### CSHashConsensus [0x54f74a10e4397ddef85c4854d9dfca129d72c637](https://hoodi.etherscan.io//address/0x54f74a10e4397ddef85c4854d9dfca129d72c637)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSMDevEOA`](https://hoodi.etherscan.io//address/0x4af43ee34a6fcd1feca1e1f832124c763561da53) [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`DISABLE_CONSENSUS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DISABLE_CONSENSUS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FAST_LANE_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FAST_LANE_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA3`](https://hoodi.etherscan.io//address/0x4022e0754d0cb6905b54306105d3346d1547988b) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) |
| [`MANAGE_FRAME_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FRAME_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA3`](https://hoodi.etherscan.io//address/0x4022e0754d0cb6905b54306105d3346d1547988b) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) |
| [`MANAGE_MEMBERS_AND_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_MEMBERS_AND_QUORUM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA3`](https://hoodi.etherscan.io//address/0x4022e0754d0cb6905b54306105d3346d1547988b) [`DevEOA1`](https://hoodi.etherscan.io//address/0xe28f573b732632fde03bd5507a7d475383e8512e) [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`MANAGE_REPORT_PROCESSOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_REPORT_PROCESSOR_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### EasyTrack [0x284d91a7d47850d21a6deaac6e538ac7e5e6fc2a](https://hoodi.etherscan.io//address/0x284d91a7d47850d21a6deaac6e538ac7e5e6fc2a)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| [`CANCEL_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CANCEL_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`EasyTrackManagerEOA`](https://hoodi.etherscan.io//address/0xbe2fd5a6ce6460eb5e9acc5d486697ae6402fdd2) [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`EasyTrackManagerEOA`](https://hoodi.etherscan.io//address/0xbe2fd5a6ce6460eb5e9acc5d486697ae6402fdd2) [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |
| [`UNPAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNPAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`EasyTrackManagerEOA`](https://hoodi.etherscan.io//address/0xbe2fd5a6ce6460eb5e9acc5d486697ae6402fdd2) [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) |

### Contracts Ownership
| Contract | Property | Old Owner | New Owner |
| --- | --- | --- | --- |
| ⚠️ [`WithdrawalVault`](https://hoodi.etherscan.io//address/0x4473dcddbf77679a643bdb654dbd86d67f8d32f2) | `proxy_getAdmin` | [`Voting`](https://hoodi.etherscan.io//address/0x49b3512c44891bef83f8967d075121bd1b07a01b) | ⚠️ [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`DepositSecurityModule`](https://hoodi.etherscan.io//address/0x2f0303f20e0795e6ccd17bd5efe791a586f28e03) | `getOwner` | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`LidoLocator`](https://hoodi.etherscan.io//address/0xe2ef9536daaaebff5b1c130957ab3e80056b06d8) | `proxy__getAdmin` | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`StakingRouter`](https://hoodi.etherscan.io//address/0xcc820558b39ee15c7c45b59390b503b83fb499a8) | `proxy__getAdmin` | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`WithdrawalQueueERC721`](https://hoodi.etherscan.io//address/0xfe56573178f1bcdf53f01a6e9977670dcbbd9186) | `proxy__getAdmin` | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`AccountingOracle`](https://hoodi.etherscan.io//address/0xcb883b1bd0a41512b42d2db267f2a2cd919fb216) | `proxy__getAdmin` | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |
| [`ValidatorsExitBusOracle`](https://hoodi.etherscan.io//address/0x8664d394c2b3278f26a1b44b967aef99707eeab2) | `proxy__getAdmin` | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) | [`Agent`](https://hoodi.etherscan.io//address/0x0534aa41907c9631fae990960bcc72d75fa7cfed) |

##### Transition Steps

```
52. Set admin to Agent on WithdrawalVault
```
