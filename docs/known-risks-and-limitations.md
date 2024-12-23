# Dual Governance: Known Risks & Limitations

While the [Dual Governance (DG) system](specification.md) is designed to protect stETH holders from malicious DAO actions, certain protocol specifics and implementation details can reduce its effectiveness in certain situations. This document outlines key risks, limitations, and potential mitigation strategies.


## 1. Malicious Oracle Sets

DG relies heavily on the Lido protocol’s [withdrawals mechanics](https://docs.lido.fi/guides/lido-tokens-integration-guide#withdrawals-unsteth), which in turn depend on the performance of the [accounting](https://docs.lido.fi/guides/oracle-spec/accounting-oracle) and [validators exit bus](https://docs.lido.fi/guides/oracle-spec/validator-exit-bus) oracles.

A malicious set of oracle members could completely halt the withdrawal process. Combined with an ongoing RageQuit, this scenario could lock user funds in the Escrow contract and effectively paralyze governance.

**Possible Mitigation:**

If the Lido DAO acts in good faith, the Tiebreaker Committee can execute a proposal to remove malicious oracle members, thereby restoring the withdrawal finalization process.

If the DAO itself is hostile, the only remaining solution will be the implementation of fully permissionless oracles or withdrawal processes. Early efforts toward this goal are already underway, including [negative rebase sanity checks with a second opinion](https://github.com/lidofinance/lido-improvement-proposals/blob/develop/LIPS/lip-23.md) and [triggerable exits](https://eips.ethereum.org/EIPS/eip-7002).


## 2. L2 & Side-Chains Bridges Pause

The wstETH token is widely available on [many L2s and side-chains] (https://docs.lido.fi/deployed-contracts/#lido-multichain).

One recommended practice for these bridges is to implement [pausable deposits and withdrawals](https://docs.lido.fi/token-guides/wsteth-bridging-guide#r-7-pausable-deposits-and-withdrawals).

Although the suggested approach is to combine [`GateSeals`](https://github.com/lidofinance/gate-seals) with a [`PausableUntil`](https://github.com/lidofinance/core/blob/master/contracts/0.8.9/utils/PausableUntil.sol) interface, most current bridges rely on a standard `Pausable` interface, which can pause contracts indefinitely by default.

The proposed Dual Governance configuration assumes that pausing bridge deposits and withdrawals is protected by the Dual Governance mechanism, with the [Emergency Brakes multisigs](https://docs.lido.fi/multisigs/emergency-brakes) retaining the right to pause these bridges.

Under the current pausability implementation, a malicious Emergency Brakes multisig could pause withdrawals indefinitely, preventing L2 wstETH holders from locking their funds in the Signalling escrow.

**Possible Mitigation:**

Adopting `GateSeal`-based pausing mechanisms would prevent an infinite pause by a single Emergency Brakes multisig. Such an attack would then require collusion with the Reseal Committee, significantly increasing the complexity of executing it.


## 3. stETH Availability & Thresholds Configuration

The implementation of Dual Governance assumes that the first seal RageQuit threshold can be reached relatively quickly. If this threshold cannot be met during the VetoSignalling state (for example, because stETH is locked in L2s, CEXes, or other DeFi protocols), a malicious proposal might be executed before stETH holders can respond.

**Possible Mitigation:**

The initial Dual Governance parameters were chosen based on a several analytical researches. The choosen parameter values should be periodically recalibrated to reflect current market realities, guided by high-level models derived from these analyses.


## 4. Low TVL Periods

When the protocol’s TVL is low, a malicious actor (for example, hostile LDO holders) controlling more than `100% - secondSealThreshold` of stETH TVL could prevent the initiation of RageQuit after submitting a harmful proposal. This scenario is more likely during later RageQuits, when a significant portion of stETH has already been withdrawn.

**Possible Mitigation:**

Users should be guided to exit earlier in the RageQuit sequence, when withdrawals are subject to shorter delays and the risk of losing funds due to the described attack is lower.


## 5. Misuse of the Signalling Escrow

One of the main purposes of the Dual Governance mechanism in the Lido protocol is to:

> Give stakers a say by allowing them to block DAO decisions and providing a negotiation device between stakers and the DAO.

To ensure this feature is as accessible as possible for stETH holders, the current design **does not impose any penalties or reduce rewards for users who lock their stETH or wstETH in the Signalling Escrow**.

The reasoning behind this decision is that expressing disagreement with a DAO proposal—without intending to leave the protocol—should not be punished. Penalizing dissent would discourage the active minority of stETH holders from participating in negotiations with the DAO.

While this penalty-free approach encourages participation, it also allows for two potential misuse scenarios:

1. **Unintentional Misuse:** Users might lock tokens indefinitely due to misunderstanding.
2. **Deliberate Misuse:** Malicious actors may lock tokens purely to stall DAO operations.

These scenarios could keep Dual Governance perpetually cycling through `VetoSignalling`, `VetoSignallingDeactivation`, and `VetoCooldown` states.

**Possible Mitigation:**

Although both scenarios are possible, reaching the first seal threshold requires a substantial stETH commitment, resulting in high opportunity costs (lost yield opportunities for the locked tokens). This naturally deters casual misuse.

The main mitigation lies in educating users about the Signalling Escrow’s intended purpose and ensuring that the user interface provides clear guidance.

For deliberate misuse, no absolute protection exists. However, even in such cases, the DAO remains functional and can still operate, albeit more slowly.


## 6. The Undertermined Proposals Launch Time

Due to variable Veto Signalling durations, DAO proposal execution times may vary, complicating time-sensitive actions.

**Possible Mitigation:**

Proposals can include time-validation check calls. See the [example `TimeConstraints` contract](https://github.com/lidofinance/dual-governance/blob/main/test/utils/time-constraints.sol) and its [usage example](https://github.com/lidofinance/dual-governance/blob/main/test/scenario/time-sensitive-proposal-execution.t.sol).
