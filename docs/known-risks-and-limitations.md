# Dual Governance: Known Risks & Limitations

While the [Dual Governance (DG) system](specification.md) is designed to protect stETH holders from malicious DAO actions, certain protocol specifics and implementation details can reduce its effectiveness in certain situations. This document outlines key risks, limitations, and potential mitigation strategies.

## 1. Malicious Oracle Sets

DG relies heavily on the Lido protocol’s [withdrawals mechanics](https://docs.lido.fi/guides/lido-tokens-integration-guide#withdrawals-unsteth), which in turn depend on the performance of the [accounting](https://docs.lido.fi/guides/oracle-spec/accounting-oracle) and [validators exit bus](https://docs.lido.fi/guides/oracle-spec/validator-exit-bus) oracles.

A malicious set of oracle members could completely halt the withdrawal process. Combined with an ongoing RageQuit, this scenario could lock user funds in the Escrow contract and effectively paralyze governance.

### Possible Mitigation:

If the Lido DAO acts in good faith, the Tiebreaker Committee can execute a proposal to remove malicious oracle members, thereby restoring the withdrawal finalization process.

If the DAO itself is hostile, the only remaining solution will be the implementation of fully permissionless oracles or withdrawal processes. Early efforts toward this goal are already underway, including [negative rebase sanity checks with a second opinion](https://github.com/lidofinance/lido-improvement-proposals/blob/develop/LIPS/lip-23.md) and [triggerable exits](https://eips.ethereum.org/EIPS/eip-7002).

---

## 2. L2 & Side-Chains Bridges Pause

The wstETH token is widely available on [many L2s and side-chains](https://docs.lido.fi/deployed-contracts/#lido-multichain).

One recommended practice for these bridges is to implement [pausable deposits and withdrawals](https://docs.lido.fi/token-guides/wsteth-bridging-guide#r-7-pausable-deposits-and-withdrawals).

Although the suggested approach is to combine [`GateSeals`](https://github.com/lidofinance/gate-seals) with a [`PausableUntil`](https://github.com/lidofinance/core/blob/master/contracts/0.8.9/utils/PausableUntil.sol) interface, most current bridges rely on a standard `Pausable` interface, which can pause contracts indefinitely by default.

The proposed Dual Governance configuration assumes that pausing bridge deposits and withdrawals is protected by the Dual Governance mechanism, with the [Emergency Brakes multisigs](https://docs.lido.fi/multisigs/emergency-brakes) retaining the right to pause these bridges.

Under the current pausability implementation, a malicious Emergency Brakes multisig could pause withdrawals indefinitely, preventing L2 wstETH holders from locking their funds in the Signalling Escrow.

### Possible Mitigation:

Adopting `GateSeal`-based pausing mechanisms would prevent an infinite pause by a single Emergency Brakes multisig. Such an attack would then require collusion with the Reseal Committee, significantly increasing the complexity of executing it.

Another possible mitigation would be to completely revoke the rights of Emergency Brakes multisigs to pause withdrawals from battle-tested bridge implementations, while restricting their control to pausing only deposits.

---

## 3. stETH Availability & Thresholds Configuration

The implementation of Dual Governance assumes that the first seal RageQuit threshold can be reached relatively quickly. If this threshold cannot be met during the VetoSignalling state (for example, because stETH is locked in L2s, CEXes, or other DeFi protocols), a malicious proposal might be executed before stETH holders can respond.

### Possible Mitigation:

The initial Dual Governance parameters were chosen based on a several analytical researches. The chosen parameter values should be periodically recalibrated to reflect current market realities, guided by high-level models derived from these analyses.

---

## 4. Low TVL Periods

When the protocol’s TVL is low, a malicious actor (for example, hostile LDO holders) controlling more than `100% - secondSealThreshold` of stETH TVL could prevent the initiation of RageQuit after submitting a harmful proposal. This scenario is more likely during later RageQuits, when a significant portion of stETH has already been withdrawn.

### Possible Mitigation:

Users should be guided to exit earlier in the RageQuit sequence, when withdrawals are subject to shorter delays and the risk of losing funds due to the described attack is lower.

---

## 5. Misuse of the Signalling Escrow

One of the main purposes of the Dual Governance mechanism in the Lido protocol is to:

> Give stakers a say by allowing them to block DAO decisions and providing a negotiation device between stakers and the DAO.

To ensure this feature is as accessible as possible for stETH holders, the current design **does not impose any penalties or reduce rewards for users who lock their stETH or wstETH in the Signalling Escrow**.

The reasoning behind this decision is that expressing disagreement with a DAO proposal—without intending to leave the protocol—should not be punished. Penalizing dissent would discourage the active minority of stETH holders from participating in negotiations with the DAO.

While this penalty-free approach encourages participation, it also allows for two potential misuse scenarios:

1. **Unintentional Misuse:** Users might lock tokens indefinitely due to misunderstanding.
2. **Deliberate Misuse:** Malicious actors may lock tokens purely to stall DAO operations.

These scenarios could keep Dual Governance perpetually cycling through `VetoSignalling`, `VetoSignallingDeactivation`, and `VetoCooldown` states.

### Possible Mitigation:

Although both scenarios are possible, reaching the first seal threshold requires a substantial stETH commitment, resulting in high opportunity costs (lost yield opportunities for the locked tokens). This naturally deters casual misuse.

The main mitigation lies in educating users about the Signalling Escrow’s intended purpose and ensuring that the user interface provides clear guidance.

For deliberate misuse, no absolute protection exists. However, even in such cases, the DAO remains functional and can still operate, albeit more slowly.

---

## 6. The VetoSignalling Flash Loans Abuse

The Signalling Escrow enables stETH holders to lock funds in opposition to the DAO. While locking and unlocking funds require adhering to the `minAssetsLockDuration` delay, preventing direct flash loan-based unlocking within the same transaction, flash loans can still be used to temporarily amplify veto power.

The overall strategy involves:

1. Locking X tokens from address A.
2. Waiting until the `minAssetsLockDuration` has passed.
3. Taking a flash loan of X tokens from address B.
4. Unlocking funds from address A.
5. Using the withdrawn funds to repay the flash loan.

During this short window, the veto power is artificially doubled, forcing Dual Governance into the `VetoSignalling` and subsequently `VetoSignallingDeactivation` states.

The feasibility of this attack is constrained by significant financial requirements, including the initial capital needed to enter the `VetoSignalling` state and the ongoing costs of flash loans. Moreover, the impact remains limited to delaying DAO proposals execution, as initiating a `RageQuit` still requires locking the full `secondSealRageQuitSupport` amount in the Signalling Eescrow.

### Possible Mitigation:

In case of flash loan abuse, an option to set `minAssetsLockDuration` greater than `VetoSignallingDeactivation` may be considered. This ensures that the system transitions into the `VetoCooldown` state before tokens become eligible for withdrawal from the Signalling Escrow in step 1, effectively preventing the execution of the described strategy.

---

## 7. Admin Executor Misconfiguration

When updating the admin executor, there is a risk of misconfiguration if the new executor address is not assigned to the proposer within Dual Governance. In such a case, the DAO risks losing administrative control over critical components of Lido.

### Possible Mitigation:

To eliminate the risk of misconfiguration, any proposal to update the admin executor MUST include a validation check as the final action, ensuring that the new admin executor is properly assigned to a Dual Governance proposer (see the [`DualGovernance.isExecutor`](specification.md#function-dualgovernanceisexecutor) method). If the validation fails, the transaction MUST be reverted.

---

## 8. The Undetermined Proposals Launch Time

Due to variable Veto Signalling durations, DAO proposal execution times may vary, complicating time-sensitive actions.

### Possible Mitigation:

Proposals can include time-validation check calls. See the [example `TimeConstraints` contract](https://github.com/lidofinance/dual-governance/blob/main/test/utils/time-constraints.sol) and its [usage example](https://github.com/lidofinance/dual-governance/blob/main/test/scenario/time-sensitive-proposal-execution.t.sol).

---

## 9. The EasyTrack Permissions Risks
According to the [permissions transition plan](./permissions-transition/permissions-transition-mainnet.md) for the DG launch, EasyTrack’s ownership remains with the `Voting` contract. As the vehicle for “optimistic” decision-making widely used in DAO operations, this choice seems logical. However, it introduces a potential risk that a malicious DAO could abuse the permissions granted to EasyTrack’s `EVMScriptExecutor`.

In the current setup, the `EVMScriptExecutor` is set as the manager for the `SimpleDVT.MANAGE_SIGNING_KEYS` permission and has been granted the following staking modules roles: `SimpleDVT.STAKING_ROUTER_ROLE`, `SimpleDVT.MANAGE_NODE_OPERATOR_ROLE`, `SimpleDVT.SET_NODE_OPERATOR_LIMIT_ROLE` and, `CuratedModule.SET_NODE_OPERATOR_LIMIT_ROLE`.

While these permissions do not pose direct risks to the DG mechanics, they could potentially be abused by a malicious DAO to slow down regular validator exit operations within the SimpleDVT staking module. Additionally, future enhancements of EasyTrack within DAO operations could require granting the `EVMScriptExecutor` even more sensitive permissions.

### Possible Mitigation:

This risk can be mitigated by registering the `EVMScriptExecutor` as a proposer in the DualGovernance system. In this setup, any actions affecting the protocol would need to be submitted as a Dual Governance proposal, giving stETH holders the opportunity to react to potential malicious actions by the DAO.
