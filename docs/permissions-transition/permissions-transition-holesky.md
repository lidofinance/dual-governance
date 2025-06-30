# Dual Governance upgrade (permission transitions for Holesky)

Due to the Dual Governance upgrade, some roles need to be reassigned in accordance with the current state of the Lido protocol on Mainnet. You can read more about the upgrade at the following [link](./permissions-transition-mainnet.md).

During active protocol testing in the testnet, some roles were assigned to EOAs or multisigs, as reflected in the table. It was decided not to modify these addresses (i.e., not to revoke or grant roles) but only to transfer the necessary permissions from the voting contract to the agent, following the Mainnet plan.

## Lido Permissions Transition (Holesky)

> - Data was collected at block [`3613513`](https://holesky.etherscan.io//block/3613513)
> - The last permissions change occurred at block [`3567837`](https://holesky.etherscan.io//block/3567837), transaction [`0x7d5baa32dd1ee4f565bc49d6ed28fe059d8f2573d919d648a5e537f915a2fc04`](https://holesky.etherscan.io//tx/0x7d5baa32dd1ee4f565bc49d6ed28fe059d8f2573d919d648a5e537f915a2fc04)

How to read this document:
- If an item is prepended with the "⚠️" icon, it indicates that the item will be changed. The required updates are described in the corresponding "Transition Steps" sections.
- The special symbol "∅" indicates that:
  - a permission or role is not granted to any address
  - revocation of the permission or role is not performed
  - no manager is set for the permission
- The notation "`Old Manager` → `New Manager`" means the current manager is being changed to a new one.
  - A special case is "`∅` → `New Manager`", which means the permission currently has no manager, and the permission should be created before use.

### Aragon Permissions
#### ⚠️ Lido [0x3f1c547b21f65e10480de3ad8e19faac46c95034](https://holesky.etherscan.io//address/0x3f1c547b21f65e10480de3ad8e19faac46c95034)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`STAKING_CONTROL_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_CONTROL_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) [`UnlimitedStake`](https://holesky.etherscan.io//address/0xcfac1357b16218a90639cd17f90226b385a71084) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ |
| ⚠️ [`UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ |
| ⚠️ [`STAKING_PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_PAUSE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ |

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

#### ⚠️ DAOKernel [0x3b03f75ec541ca11a223bb58621a3146246e1644](https://holesky.etherscan.io//address/0x3b03f75ec541ca11a223bb58621a3146246e1644)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`APP_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=APP_MANAGER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ |

##### Transition Steps

```
11. Revoke APP_MANAGER_ROLE permission from Voting on DAOKernel
12. Set APP_MANAGER_ROLE manager to Agent on DAOKernel
```

#### ⚠️ TokenManager [0xfaa1692c6eea8eef534e7819749ad93a1420379a](https://holesky.etherscan.io//address/0xfaa1692c6eea8eef534e7819749ad93a1420379a)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`MINT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MINT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| ⚠️ [`REVOKE_VESTINGS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REVOKE_VESTINGS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| ⚠️ [`BURN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=BURN_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| ⚠️ [`ISSUE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ISSUE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| [`ASSIGN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ASSIGN_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |

##### Transition Steps

```
13. Create MINT_ROLE permission on TokenManager with manager Voting and grant it to Voting
14. Create REVOKE_VESTINGS_ROLE permission on TokenManager with manager Voting and grant it to Voting
15. Create BURN_ROLE permission on TokenManager with manager Voting and grant it to Voting
16. Create ISSUE_ROLE permission on TokenManager with manager Voting and grant it to Voting
```

#### ⚠️ Finance [0xf0f281e5d7fbc54eafce0da225cdbde04173ab16](https://holesky.etherscan.io//address/0xf0f281e5d7fbc54eafce0da225cdbde04173ab16)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`CHANGE_PERIOD_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CHANGE_PERIOD_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| ⚠️ [`CHANGE_BUDGETS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CHANGE_BUDGETS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ ∅ → [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| [`CREATE_PAYMENTS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_PAYMENTS_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) [`EvmScriptExecutor`](https://holesky.etherscan.io//address/0x2819b65021e13ceeb9ac33e77db32c7e64e7520d) |
| [`EXECUTE_PAYMENTS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=EXECUTE_PAYMENTS_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| [`MANAGE_PAYMENTS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_PAYMENTS_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |

##### Transition Steps

```
17. Create CHANGE_PERIOD_ROLE permission on Finance with manager Voting and grant it to Voting
18. Create CHANGE_BUDGETS_ROLE permission on Finance with manager Voting and grant it to Voting
```

#### ⚠️ EVMScriptRegistry [0xe1200ae048163b67d69bc0492bf5fddc3a2899c0](https://holesky.etherscan.io//address/0xe1200ae048163b67d69bc0492bf5fddc3a2899c0)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`REGISTRY_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REGISTRY_MANAGER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ |
| ⚠️ [`REGISTRY_ADD_EXECUTOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REGISTRY_ADD_EXECUTOR_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ |

##### Transition Steps

```
19. Revoke REGISTRY_MANAGER_ROLE permission from Voting on EVMScriptRegistry
20. Set REGISTRY_MANAGER_ROLE manager to Agent on EVMScriptRegistry
21. Revoke REGISTRY_ADD_EXECUTOR_ROLE permission from Voting on EVMScriptRegistry
22. Set REGISTRY_ADD_EXECUTOR_ROLE manager to Agent on EVMScriptRegistry
```

#### ⚠️ CuratedModule [0x595f64ddc3856a3b5ff4f4cc1d1fb4b46cfd2bac](https://holesky.etherscan.io//address/0x595f64ddc3856a3b5ff4f4cc1d1fb4b46cfd2bac)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`MANAGE_NODE_OPERATOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_NODE_OPERATOR_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | [`DevEOA2`](https://holesky.etherscan.io//address/0x66b25cfe6b9f0e61bd80c4847225baf4ee6ba0a2) [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) |
| ⚠️ [`SET_NODE_OPERATOR_LIMIT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_NODE_OPERATOR_LIMIT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) [`DevEOA2`](https://holesky.etherscan.io//address/0x66b25cfe6b9f0e61bd80c4847225baf4ee6ba0a2) [`EvmScriptExecutor`](https://holesky.etherscan.io//address/0x2819b65021e13ceeb9ac33e77db32c7e64e7520d) |
| ⚠️ [`MANAGE_SIGNING_KEYS`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_SIGNING_KEYS&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ |
| ⚠️ [`STAKING_ROUTER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_ROUTER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ∅ | [`StakingRouter`](https://holesky.etherscan.io//address/0xd6ebf043d30a7fe46d1db32ba90a0a51207fe229) [`DevEOA2`](https://holesky.etherscan.io//address/0x66b25cfe6b9f0e61bd80c4847225baf4ee6ba0a2) [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) |

##### Transition Steps

```
23. Set STAKING_ROUTER_ROLE manager to Agent on CuratedModule
24. Revoke MANAGE_NODE_OPERATOR_ROLE permission from Voting on CuratedModule
25. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on CuratedModule
26. Revoke SET_NODE_OPERATOR_LIMIT_ROLE permission from Voting on CuratedModule
27. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on CuratedModule
28. Revoke MANAGE_SIGNING_KEYS permission from Voting on CuratedModule
29. Set MANAGE_SIGNING_KEYS manager to Agent on CuratedModule
```

#### ⚠️ SimpleDVT [0x11a93807078f8bb880c1bd0ee4c387537de4b4b6](https://holesky.etherscan.io//address/0x11a93807078f8bb880c1bd0ee4c387537de4b4b6)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`STAKING_ROUTER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_ROUTER_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ∅ | [`StakingRouter`](https://holesky.etherscan.io//address/0xd6ebf043d30a7fe46d1db32ba90a0a51207fe229) [`EvmScriptExecutor`](https://holesky.etherscan.io//address/0x2819b65021e13ceeb9ac33e77db32c7e64e7520d) [`DevEOA3`](https://holesky.etherscan.io//address/0x2a329e1973217eb3828eb0f2225d1b1c10db72b0) |
| ⚠️ [`MANAGE_NODE_OPERATOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_NODE_OPERATOR_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ∅ | [`EvmScriptExecutor`](https://holesky.etherscan.io//address/0x2819b65021e13ceeb9ac33e77db32c7e64e7520d) [`DevEOA3`](https://holesky.etherscan.io//address/0x2a329e1973217eb3828eb0f2225d1b1c10db72b0) |
| ⚠️ [`SET_NODE_OPERATOR_LIMIT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_NODE_OPERATOR_LIMIT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ∅ | [`EvmScriptExecutor`](https://holesky.etherscan.io//address/0x2819b65021e13ceeb9ac33e77db32c7e64e7520d) [`DevEOA3`](https://holesky.etherscan.io//address/0x2a329e1973217eb3828eb0f2225d1b1c10db72b0) |
| [`MANAGE_SIGNING_KEYS`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_SIGNING_KEYS&input_type=utf-8&output_type=hex) | [`EvmScriptExecutor`](https://holesky.etherscan.io//address/0x2819b65021e13ceeb9ac33e77db32c7e64e7520d) | ∅ | [`EvmScriptExecutor`](https://holesky.etherscan.io//address/0x2819b65021e13ceeb9ac33e77db32c7e64e7520d) [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) [`DevEOA3`](https://holesky.etherscan.io//address/0x2a329e1973217eb3828eb0f2225d1b1c10db72b0) `+74 Simple DVT Operator(s)` |

##### Transition Steps

```
30. Set STAKING_ROUTER_ROLE manager to Agent on SimpleDVT
31. Set MANAGE_NODE_OPERATOR_ROLE manager to Agent on SimpleDVT
32. Set SET_NODE_OPERATOR_LIMIT_ROLE manager to Agent on SimpleDVT
```

#### ⚠️ ACL [0xfd1e42595cec3e83239bf8dfc535250e7f48e0bc](https://holesky.etherscan.io//address/0xfd1e42595cec3e83239bf8dfc535250e7f48e0bc)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`CREATE_PERMISSIONS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_PERMISSIONS_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ⚠️ [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |

##### Transition Steps

```
33. Grant CREATE_PERMISSIONS_ROLE permission to Agent on ACL
34. Revoke CREATE_PERMISSIONS_ROLE permission from Voting on ACL
35. Set CREATE_PERMISSIONS_ROLE manager to Agent on ACL
```

#### ⚠️ Agent [0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`RUN_SCRIPT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RUN_SCRIPT_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ⚠️ [`DGAdminExecutor`](https://holesky.etherscan.io//address/0x) ⚠️ [`DevAgentManager`](https://holesky.etherscan.io//address/0xc807d4036b400de8f6cd2adbd8d9cf9a3a01cc30) |
| ⚠️ [`EXECUTE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=EXECUTE_ROLE&input_type=utf-8&output_type=hex) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) → [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ⚠️ [`DGAdminExecutor`](https://holesky.etherscan.io//address/0x) |
| [`TRANSFER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=TRANSFER_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | [`Finance`](https://holesky.etherscan.io//address/0xf0f281e5d7fbc54eafce0da225cdbde04173ab16) |
| [`SAFE_EXECUTE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SAFE_EXECUTE_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`DESIGNATE_SIGNER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DESIGNATE_SIGNER_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`ADD_PRESIGNED_HASH_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ADD_PRESIGNED_HASH_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`ADD_PROTECTED_TOKEN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ADD_PROTECTED_TOKEN_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |
| [`REMOVE_PROTECTED_TOKEN_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REMOVE_PROTECTED_TOKEN_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

##### Transition Steps

```
36. Grant RUN_SCRIPT_ROLE permission to DGExecutor on Agent
37. Grant RUN_SCRIPT_ROLE permission to DevAgentManager on Agent
// SKIPPED: __. Revoke RUN_SCRIPT_ROLE permission from Voting on Agent - Will be done as 
// the last step of the launch via the Dual Governance proposal
38. Set RUN_SCRIPT_ROLE manager to Agent on Agent
39. Grant EXECUTE_ROLE permission to DGExecutor on Agent
// SKIPPED: __. Revoke EXECUTE_ROLE permission from Voting on Agent - Will be done as 
// the last step of the launch via the Dual Governance proposal
40. Set EXECUTE_ROLE manager to Agent on Agent
```

#### Voting [0xda7d2573df555002503f29aa4003e398d28cc00f](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`UNSAFELY_MODIFY_VOTE_TIME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNSAFELY_MODIFY_VOTE_TIME_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | ∅ |
| [`MODIFY_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MODIFY_QUORUM_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| [`MODIFY_SUPPORT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MODIFY_SUPPORT_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| [`CREATE_VOTES_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VOTES_ROLE&input_type=utf-8&output_type=hex) | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ∅ | [`TokenManager`](https://holesky.etherscan.io//address/0xfaa1692c6eea8eef534e7819749ad93a1420379a) |

#### AragonPM [0xb576a85c310cc7af5c106ab26d2942fa3a5ea94a](https://holesky.etherscan.io//address/0xb576a85c310cc7af5c106ab26d2942fa3a5ea94a)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_REPO_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_REPO_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### VotingRepo [0x2997ea0d07d79038d83cb04b3bb9a2bc512e3fda](https://holesky.etherscan.io//address/0x2997ea0d07d79038d83cb04b3bb9a2bc512e3fda)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### LidoRepo [0xa37fb4c41e7d30af5172618a863bbb0f9042c604](https://holesky.etherscan.io//address/0xa37fb4c41e7d30af5172618a863bbb0f9042c604)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### LegacyOracleRepo [0xb3d74c319c0c792522705ffd3097f873eec71764](https://holesky.etherscan.io//address/0xb3d74c319c0c792522705ffd3097f873eec71764)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### CuratedModuleRepo [0x4e8970d148cb38460be9b6ddaab20ae2a74879af](https://holesky.etherscan.io//address/0x4e8970d148cb38460be9b6ddaab20ae2a74879af)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

#### SimpleDVTRepo [0x889db59baf032e1dfd4fca720e0833c24f1404c6](https://holesky.etherscan.io//address/0x889db59baf032e1dfd4fca720e0833c24f1404c6)
| Role | Role Manager | Revoked | Granted |
| --- | --- | --- | --- |
| [`CREATE_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CREATE_VERSION_ROLE&input_type=utf-8&output_type=hex) | ∅ | ∅ | ∅ |

### OZ Roles
#### ⚠️ WithdrawalQueueERC721 [0xc7cc160b58f8bb0bac94b80847e2cf2800565c50](https://holesky.etherscan.io//address/0xc7cc160b58f8bb0bac94b80847e2cf2800565c50)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://holesky.etherscan.io//address/0x) [`OraclesGateSeal`](https://holesky.etherscan.io//address/0xae6ecd77dcc656c5533c4209454fd56fb46e1778) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://holesky.etherscan.io//address/0x) [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`FINALIZE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=FINALIZE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Lido`](https://holesky.etherscan.io//address/0x3f1c547b21f65e10480de3ad8e19faac46c95034) |
| [`MANAGE_TOKEN_URI_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_TOKEN_URI_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`ORACLE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ORACLE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`AccountingOracle`](https://holesky.etherscan.io//address/0x4e97a3972ce8511d87f334da17a2c332542a5246) |

##### Transition Steps

```
41. Grant PAUSE_ROLE to ResealManager on WithdrawalQueueERC721
42. Grant RESUME_ROLE to ResealManager on WithdrawalQueueERC721
```

#### ⚠️ ValidatorsExitBusOracle [0xffddf7025410412deaa05e3e1ce68fe53208afcb](https://holesky.etherscan.io//address/0xffddf7025410412deaa05e3e1ce68fe53208afcb)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://holesky.etherscan.io//address/0x) [`OraclesGateSeal`](https://holesky.etherscan.io//address/0xae6ecd77dcc656c5533c4209454fd56fb46e1778) |
| ⚠️ [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ⚠️ [`ResealManager`](https://holesky.etherscan.io//address/0x) [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`MANAGE_CONSENSUS_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_VERSION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SUBMIT_DATA_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SUBMIT_DATA_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

##### Transition Steps

```
43. Grant PAUSE_ROLE to ResealManager on ValidatorsExitBusOracle
44. Grant RESUME_ROLE to ResealManager on ValidatorsExitBusOracle
```

#### ⚠️ AllowedTokensRegistry [0x091c0ec8b4d54a9fcb36269b5d5e5af43309e666](https://holesky.etherscan.io//address/0x091c0ec8b4d54a9fcb36269b5d5e5af43309e666)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| ⚠️ `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ⚠️ [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| ⚠️ [`ADD_TOKEN_TO_ALLOWED_LIST_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ADD_TOKEN_TO_ALLOWED_LIST_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ⚠️ [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| ⚠️ [`REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ⚠️ [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | ⚠️ [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |

##### Transition Steps

```
45. Grant DEFAULT_ADMIN_ROLE to Voting on AllowedTokensRegistry
46. Revoke DEFAULT_ADMIN_ROLE from Agent on AllowedTokensRegistry
47. Grant ADD_TOKEN_TO_ALLOWED_LIST_ROLE to Voting on AllowedTokensRegistry
58. Revoke ADD_TOKEN_TO_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry
49. Grant REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE to Voting on AllowedTokensRegistry
50. Revoke REMOVE_TOKEN_FROM_ALLOWED_LIST_ROLE from Agent on AllowedTokensRegistry
```

#### StakingRouter [0xd6ebf043d30a7fe46d1db32ba90a0a51207fe229](https://holesky.etherscan.io//address/0xd6ebf043d30a7fe46d1db32ba90a0a51207fe229)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`MANAGE_WITHDRAWAL_CREDENTIALS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_WITHDRAWAL_CREDENTIALS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REPORT_EXITED_VALIDATORS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REPORT_EXITED_VALIDATORS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`AccountingOracle`](https://holesky.etherscan.io//address/0x4e97a3972ce8511d87f334da17a2c332542a5246) |
| [`REPORT_REWARDS_MINTED_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REPORT_REWARDS_MINTED_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Lido`](https://holesky.etherscan.io//address/0x3f1c547b21f65e10480de3ad8e19faac46c95034) |
| [`STAKING_MODULE_MANAGE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_MODULE_MANAGE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) |
| [`STAKING_MODULE_UNVETTING_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_MODULE_UNVETTING_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DepositSecurityModule`](https://holesky.etherscan.io//address/0x808de3b26be9438f12e9b45528955ea94c17f217) |
| [`UNSAFE_SET_EXITED_VALIDATORS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNSAFE_SET_EXITED_VALIDATORS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### Burner [0x4e46bd7147ccf666e1d73a3a456fc7a68de82eca](https://holesky.etherscan.io//address/0x4e46bd7147ccf666e1d73a3a456fc7a68de82eca)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`REQUEST_BURN_MY_STETH_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REQUEST_BURN_MY_STETH_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REQUEST_BURN_SHARES_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REQUEST_BURN_SHARES_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Lido`](https://holesky.etherscan.io//address/0x3f1c547b21f65e10480de3ad8e19faac46c95034) [`CuratedModule`](https://holesky.etherscan.io//address/0x595f64ddc3856a3b5ff4f4cc1d1fb4b46cfd2bac) [`SimpleDVT`](https://holesky.etherscan.io//address/0x11a93807078f8bb880c1bd0ee4c387537de4b4b6) [`SandboxStakingModule`](https://holesky.etherscan.io//address/0xd6c2ce3bb8bea2832496ac8b5144819719f343ac) [`CSAccounting`](https://holesky.etherscan.io//address/0xc093e53e8f4b55a223c18a2da6fa00e60dd5efe1) |

#### AccountingOracle [0x4e97a3972ce8511d87f334da17a2c332542a5246](https://holesky.etherscan.io//address/0x4e97a3972ce8511d87f334da17a2c332542a5246)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`MANAGE_CONSENSUS_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_VERSION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SUBMIT_DATA_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SUBMIT_DATA_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### AccountingOracleHashConsensus [0xa067fc95c22d51c3bc35fd4be37414ee8cc890d2](https://holesky.etherscan.io//address/0xa067fc95c22d51c3bc35fd4be37414ee8cc890d2)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`DISABLE_CONSENSUS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DISABLE_CONSENSUS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FAST_LANE_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FAST_LANE_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FRAME_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FRAME_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) |
| [`MANAGE_MEMBERS_AND_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_MEMBERS_AND_QUORUM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) |
| [`MANAGE_REPORT_PROCESSOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_REPORT_PROCESSOR_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### ValidatorsExitBusHashConsensus [0xe77cf1a027d7c10ee6bb7ede5e922a181ff40e8f](https://holesky.etherscan.io//address/0xe77cf1a027d7c10ee6bb7ede5e922a181ff40e8f)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`DISABLE_CONSENSUS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DISABLE_CONSENSUS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FAST_LANE_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FAST_LANE_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FRAME_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FRAME_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) |
| [`MANAGE_MEMBERS_AND_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_MEMBERS_AND_QUORUM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) |
| [`MANAGE_REPORT_PROCESSOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_REPORT_PROCESSOR_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### OracleReportSanityChecker [0x80d1b1ff6e84134404aba18a628347960c38cca7](https://holesky.etherscan.io//address/0x80d1b1ff6e84134404aba18a628347960c38cca7)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`ALL_LIMITS_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ALL_LIMITS_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) |
| [`ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`APPEARED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=APPEARED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`EXITED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=EXITED_VALIDATORS_PER_DAY_LIMIT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA4`](https://holesky.etherscan.io//address/0x13de2ff641806da869ad6e438ef0fa0101eefdd6) |
| [`INITIAL_SLASHING_AND_PENALTIES_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=INITIAL_SLASHING_AND_PENALTIES_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MAX_ITEMS_PER_EXTRA_DATA_TRANSACTION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MAX_ITEMS_PER_EXTRA_DATA_TRANSACTION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MAX_NODE_OPERATORS_PER_EXTRA_DATA_ITEM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MAX_NODE_OPERATORS_PER_EXTRA_DATA_ITEM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MAX_POSITIVE_TOKEN_REBASE_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MAX_POSITIVE_TOKEN_REBASE_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MAX_VALIDATOR_EXIT_REQUESTS_PER_REPORT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MAX_VALIDATOR_EXIT_REQUESTS_PER_REPORT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SECOND_OPINION_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SECOND_OPINION_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SHARE_RATE_DEVIATION_LIMIT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SHARE_RATE_DEVIATION_LIMIT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### OracleDaemonConfig [0xc01fc1f2787687bc656eac0356ba9db6e6b7afb7](https://holesky.etherscan.io//address/0xc01fc1f2787687bc656eac0356ba9db6e6b7afb7)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`CONFIG_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CONFIG_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`DevEOA1`](https://holesky.etherscan.io//address/0xda6bee5441f2e6b364f3b25e85d5f3c29bfb669e) |

#### CSModule [0x4562c3e63c2e586cd1651b958c22f88135acad4f](https://holesky.etherscan.io//address/0x4562c3e63c2e586cd1651b958c22f88135acad4f)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) [`CSCommitteeMultisig`](https://holesky.etherscan.io//address/0xc4dab3a3ef68c6dfd8614a870d64d475ba44f164) |
| [`MODULE_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MODULE_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSGateSeal`](https://holesky.etherscan.io//address/0xf1c03536dbc77b1bd493a2d1c0b1831ea78b540a) |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`REPORT_EL_REWARDS_STEALING_PENALTY_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=REPORT_EL_REWARDS_STEALING_PENALTY_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSCommitteeMultisig`](https://holesky.etherscan.io//address/0xc4dab3a3ef68c6dfd8614a870d64d475ba44f164) |
| [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`EvmScriptExecutor`](https://holesky.etherscan.io//address/0x2819b65021e13ceeb9ac33e77db32c7e64e7520d) |
| [`STAKING_ROUTER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=STAKING_ROUTER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`StakingRouter`](https://holesky.etherscan.io//address/0xd6ebf043d30a7fe46d1db32ba90a0a51207fe229) |
| [`VERIFIER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=VERIFIER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSVerifier`](https://holesky.etherscan.io//address/0xc099dfd61f6e5420e0ca7e84d820daad17fc1d44) |

#### CSAccounting [0xc093e53e8f4b55a223c18a2da6fa00e60dd5efe1](https://holesky.etherscan.io//address/0xc093e53e8f4b55a223c18a2da6fa00e60dd5efe1)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) [`CSCommitteeMultisig`](https://holesky.etherscan.io//address/0xc4dab3a3ef68c6dfd8614a870d64d475ba44f164) |
| [`ACCOUNTING_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=ACCOUNTING_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_BOND_CURVES_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_BOND_CURVES_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSGateSeal`](https://holesky.etherscan.io//address/0xf1c03536dbc77b1bd493a2d1c0b1831ea78b540a) |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`RESET_BOND_CURVE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESET_BOND_CURVE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSModule`](https://holesky.etherscan.io//address/0x4562c3e63c2e586cd1651b958c22f88135acad4f) [`CSCommitteeMultisig`](https://holesky.etherscan.io//address/0xc4dab3a3ef68c6dfd8614a870d64d475ba44f164) |
| [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SET_BOND_CURVE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SET_BOND_CURVE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSModule`](https://holesky.etherscan.io//address/0x4562c3e63c2e586cd1651b958c22f88135acad4f) [`CSCommitteeMultisig`](https://holesky.etherscan.io//address/0xc4dab3a3ef68c6dfd8614a870d64d475ba44f164) |

#### CSFeeDistributor [0xd7ba648c8f72669c6ae649648b516ec03d07c8ed](https://holesky.etherscan.io//address/0xd7ba648c8f72669c6ae649648b516ec03d07c8ed)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) [`CSCommitteeMultisig`](https://holesky.etherscan.io//address/0xc4dab3a3ef68c6dfd8614a870d64d475ba44f164) |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### CSFeeOracle [0xaf57326c7d513085051b50912d51809ecc5d98ee](https://holesky.etherscan.io//address/0xaf57326c7d513085051b50912d51809ecc5d98ee)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) [`CSCommitteeMultisig`](https://holesky.etherscan.io//address/0xc4dab3a3ef68c6dfd8614a870d64d475ba44f164) |
| [`CONTRACT_MANAGER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CONTRACT_MANAGER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_CONTRACT_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_CONTRACT_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_CONSENSUS_VERSION_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_CONSENSUS_VERSION_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`CSGateSeal`](https://holesky.etherscan.io//address/0xf1c03536dbc77b1bd493a2d1c0b1831ea78b540a) |
| [`RECOVERER_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RECOVERER_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`RESUME_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=RESUME_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`SUBMIT_DATA_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=SUBMIT_DATA_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### CSHashConsensus [0xbf38618ea09b503c1ded867156a0ea276ca1ae37](https://holesky.etherscan.io//address/0xbf38618ea09b503c1ded867156a0ea276ca1ae37)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) [`CSCommitteeMultisig`](https://holesky.etherscan.io//address/0xc4dab3a3ef68c6dfd8614a870d64d475ba44f164) |
| [`DISABLE_CONSENSUS_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=DISABLE_CONSENSUS_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FAST_LANE_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FAST_LANE_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_FRAME_CONFIG_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_FRAME_CONFIG_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`MANAGE_MEMBERS_AND_QUORUM_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_MEMBERS_AND_QUORUM_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`MANAGE_REPORT_PROCESSOR_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=MANAGE_REPORT_PROCESSOR_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

#### EasyTrack [0x1763b9ed3586b08ae796c7787811a2e1bc16163a](https://holesky.etherscan.io//address/0x1763b9ed3586b08ae796c7787811a2e1bc16163a)
| Role | Role Admin | Revoked | Granted |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | ∅ | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) |
| [`CANCEL_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=CANCEL_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`PAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=PAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |
| [`UNPAUSE_ROLE`](https://emn178.github.io/online-tools/keccak_256.html?input=UNPAUSE_ROLE&input_type=utf-8&output_type=hex) | `DEFAULT_ADMIN_ROLE` | ∅ | ∅ |

### Contracts Ownership
| Contract | Property | Old Owner | New Owner |
| --- | --- | --- | --- |
| ⚠️ [`WithdrawalVault`](https://holesky.etherscan.io//address/0xf0179dec45a37423ead4fad5fcb136197872ead9) | `proxy_getAdmin` | [`Voting`](https://holesky.etherscan.io//address/0xda7d2573df555002503f29aa4003e398d28cc00f) | ⚠️ [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`DepositSecurityModule`](https://holesky.etherscan.io//address/0x808de3b26be9438f12e9b45528955ea94c17f217) | `getOwner` | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`LidoLocator`](https://holesky.etherscan.io//address/0x28fab2059c713a7f9d8c86db49f9bb0e96af1ef8) | `proxy__getAdmin` | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`StakingRouter`](https://holesky.etherscan.io//address/0xd6ebf043d30a7fe46d1db32ba90a0a51207fe229) | `proxy__getAdmin` | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`WithdrawalQueueERC721`](https://holesky.etherscan.io//address/0xc7cc160b58f8bb0bac94b80847e2cf2800565c50) | `proxy__getAdmin` | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`AccountingOracle`](https://holesky.etherscan.io//address/0x4e97a3972ce8511d87f334da17a2c332542a5246) | `proxy__getAdmin` | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
| [`ValidatorsExitBusOracle`](https://holesky.etherscan.io//address/0xffddf7025410412deaa05e3e1ce68fe53208afcb) | `proxy__getAdmin` | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) | [`Agent`](https://holesky.etherscan.io//address/0xe92329ec7ddb11d25e25b3c21eebf11f15eb325d) |
```
51. Set admin to Agent on WithdrawalVault
```
