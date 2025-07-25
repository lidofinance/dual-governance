# Dual Governance specification

Dual Governance (DG) is a governance subsystem that sits between the Lido DAO, represented by various voting systems, and the protocol contracts it manages. It protects protocol users from hostile actions by the DAO by allowing to cooperate and block any in-scope governance decision until either the DAO cancels this decision or users' (w)stETH is completely withdrawn to ETH.

This document provides the system description on the code architecture level. A detailed description on the mechanism level can be found in the [Dual Governance mechanism design overview][mech design] document which should be considered an integral part of this specification.

[mech design]: mechanism.md
[mech design - tiebreaker]: mechanism.md#Tiebreaker-Committee


## Navigation

- [System overview](#system-overview)
- [Proposal flow](#proposal-flow)
  - [Dynamic timelock](#dynamic-timelock)
  - [Proposal execution and deployment modes](#proposal-execution-and-deployment-modes)
- [Governance state](#governance-state)
- [Rage quit](#rage-quit)
- [Tiebreaker committee](#tiebreaker-committee)
- [Administrative actions](#administrative-actions)
- [Common types](#common-types)
- Core Contracts:
  - [Contract: `DualGovernance`](#contract-dualgovernance)
  - [Contract: `EmergencyProtectedTimelock`](#contract-emergencyprotectedtimelock)
  - [Contract: `Executor`](#contract-executor)
  - [Contract: `Escrow`](#contract-escrow)
  - [Contract: `ImmutableDualGovernanceConfigProvider`](#contract-immutabledualgovernanceconfigprovider)
  - [Contract: ResealManager](#contract-resealmanager)
- Committees:
  - [Contract: `ProposalsList`](#contract-proposalslist)
  - [Contract: `HashConsensus`](#contract-hashconsensus)
  - [Contract: `TiebreakerCoreCommittee`](#contract-tiebreakercorecommittee)
  - [Contract: `TiebreakerSubCommittee`](#contract-tiebreakersubcommittee)
- [Upgrade flow description](#upgrade-flow-description)
- [Known risks and limitations](#known-risks-and-limitations)


## System overview

![image](https://github.com/lidofinance/dual-governance/assets/14151334/b7498050-e04c-415e-9f45-3ed9c24f1417)

The system is composed of the following main contracts:

- [`DualGovernance`](#contract-dualgovernance) is a singleton that provides an interface for submitting governance proposals and scheduling their execution, as well as managing the list of supported proposers (DAO voting systems). Implements a state machine tracking the current global governance state which, in turn, determines whether proposal submission and execution is currently allowed.
- [`EmergencyProtectedTimelock`](#contract-emergencyprotectedtimelock) is a singleton that stores submitted proposals and provides an interface for their execution. In addition, it implements an optional temporary protection from a zero-day vulnerability in the Dual Governance contracts following the initial deployment or upgrade of the system. The protection is implemented as a timelock on proposal execution combined with two emergency committees that have the right to cooperate and disable the Dual Governance.
- [`Executor`](#contract-executor) contract instances make calls resulting from governance proposals' execution. Each `Executor` instance is owned by the `EmergencyProtectedTimelock` singleton. All protocol permissions or roles protected by the Dual Governance must be exclusively controlled by one of the `Executor` instance, rather than being assigned directly to a DAO voting system. A specific `Executor` instance is designated as the admin executor, with the authority to manage the Dual Governance system.
- [`Escrow`](#contract-escrow) is a contract that can hold stETH, wstETH, withdrawal NFTs, and plain ETH. It can exist in two states, each serving a different purpose: either an oracle for users' opposition to DAO proposals or an immutable and ungoverned accumulator for the ETH withdrawn as a result of the [rage quit](#rage-quit).
- [`ImmutableDualGovernanceConfigProvider`](#contract-immutabledualgovernanceconfigprovider) is a singleton contract that stores the configurable parameters of the Dual Governance in an immutable manner.
- [`ResealManager`](#contract-resealmanager) is a singleton contract responsible for extending or resuming sealable contracts paused by the [GateSeal emergency protection mechanism](https://github.com/lidofinance/gate-seals). This contract is essential due to the dynamic timelock of the Dual Governance, which may prevent the DAO from extending the pause in time. It holds the authority to manage the pausing and resuming of specific protocol components protected by GateSeal.

Additionally, the system incorporates several committee contracts that enable members to achieve quorum and execute a limited set of actions, while ensuring that the management of these committees is safeguarded by the Dual Governance mechanism.

Additionally, the system uses several committee contracts that allow members to  execute, acquiring quorum, a narrow set of actions while protecting management of the committees by the Dual Governance mechanism:

- [`TiebreakerCoreCommittee`](#contract-tiebreakercorecommittee) is a committee contract designed to approve proposals for execution in extreme situations where the Dual Governance is deadlocked. This includes scenarios such as the inability to finalize user withdrawal requests during ongoing `RageQuit` or when the system is held in a locked state for an extended period. The `TiebreakerCoreCommittee` consists of multiple `TiebreakerSubCommittee` contracts appointed by the DAO.
- [`TiebreakerSubCommittee`](#contract-tiebreakersubcommittee) is a committee contracts that provides ability to participate in `TiebreakerCoreCommittee` for external actors.


## Proposal flow

The system supports multiple DAO voting systems, represented in the dual governance as proposers. A **proposer** is an address that has the right to submit sets of EVM calls (**proposals**) to be made by a dual governance's **executor contract**. Each proposer has a single associated executor, though multiple proposers can share the same executor, so the system supports multiple executors and the relation between proposers and executors is many-to-one.

![image](https://github.com/lidofinance/dual-governance/assets/1699593/dc4b2a7c-8092-4195-bd68-f5581850fc6c)

The general proposal flow is the following:

1. A proposer submits a proposal, i.e. a set of EVM calls (represented by an array of [`ExternalCall`](#Struct-ExternalCall) structs) to be issued by the proposer's associated [executor contract](#Contract-Executor), by calling the [`DualGovernance.submitProposal`](#Function-DualGovernancesubmitProposal) function.
2. This starts a [dynamic timelock period](#Dynamic-timelock) that allows stakers to oppose the DAO, potentially leaving the protocol before the timelock elapses.
3. By the end of the dynamic timelock period, the proposal is either cancelled by the DAO or executable.
    * If it's cancelled, it cannot be scheduled for execution. However, any proposer is free to submit a new proposal with the same set of calls.
    * Otherwise, anyone can schedule the proposal for execution by calling the [`DualGovernance.scheduleProposal`](#Function-DualGovernancescheduleProposal) function, with the execution flow that follows being dependent on the [deployment mode](#Proposal-execution-and-deployment-modes).
4. The proposal's execution results in the proposal's EVM calls being issued by the executor contract associated with the proposer.


### Dynamic timelock

Each submitted proposal requires a minimum timelock before it can be scheduled for execution.

At any time, including while a proposal's timelock is lasting, stakers can signal their opposition to the DAO by locking their (w)stETH or stETH withdrawal NFTs (unstETH) into the [signalling escrow contract](#Contract-Escrow). If the opposition reaches some minimum threshold, the [global governance state](#Governance-state) gets changed, blocking any DAO execution and thus effectively extending the timelock of all pending (i.e. submitted but not scheduled for execution) proposals.

![image](https://github.com/lidofinance/dual-governance/assets/1699593/98273df0-f3fd-4149-929d-3315a8e81aa8)

While the Dual Governance is in the `VetoSignalling` or `VetoSignallingDeactivation` states, the DAO has the ability to cancel all pending proposals by invoking the [`DualGovernance.cancelAllPendingProposals`](#Function-DualGovernancecancelAllPendingProposals) function.

By the time the dynamic timelock described above elapses, one of the following outcomes is possible:

- The DAO was not opposed by stakers (the **happy path** scenario).
- The DAO was opposed by stakers and cancelled all pending proposals (the **two-sided de-escalation** scenario).
- The DAO was opposed by stakers and didn't cancel pending proposals, forcing the stakers to leave via the rage quit process, or cancelled the proposals but some stakers still left (the **rage quit** scenario).
- The DAO was opposed by stakers and didn't cancel pending proposals but the total stake opposing the DAO was too small to trigger the rage quit (the **failed escalation** scenario).


### Proposal execution and deployment modes

The proposal execution flow comes after the dynamic timelock elapses and the proposal is scheduled for execution. The system can function in two deployment modes which affect the flow.

![image](https://github.com/lidofinance/dual-governance/assets/1699593/7a0f0330-6ef5-4985-8fd4-ac8f1f95d229)

#### Regular deployment mode

In the regular deployment mode, the **emergency protection delay** is set to zero and all calls from scheduled proposals are immediately executable by anyone via calling the [`EmergencyProtectedTimelock.execute`](#Function-EmergencyProtectedTimelockexecute) function.

#### Protected deployment mode

The protected deployment mode is a temporary mode designed to be active during an initial period after the deployment or upgrade of the DG contracts. In this mode, scheduled proposals cannot be executed immediately; instead, before calling [`EmergencyProtectedTimelock.execute`](#Funtion-EmergencyProtectedTimelockexecute), one has to wait until an emergency protection delay elapses since the proposal scheduling time.

![image](https://github.com/lidofinance/dual-governance/assets/1699593/38cb2371-bdb0-4681-9dfd-356fa1ed7959)

In this mode, an **emergency activation committee** has the one-off and time-limited right to activate an adversarial **emergency mode** if they see a scheduled proposal that was created or altered due to a vulnerability in the DG contracts or if governance execution is prevented by such a vulnerability. Once the emergency mode is activated, the emergency activation committee is disabled, i.e. loses the ability to activate the emergency mode again. If the emergency activation committee doesn't activate the emergency mode within the duration of the **emergency protection duration** since the committee was configured by the DAO, it gets automatically disabled as well.

The emergency mode lasts up to the **emergency mode max duration** counting from the moment of its activation. While it's active, the following conditions apply:
1) Only the **emergency execution committee** has the right to execute scheduled proposals
2) The same committee has the one-off right to **disable the DG subsystem**. After this action, the system should start behaving according to [this specification](plan-b.md)). This involves disconnecting the `EmergencyProtectedTimelock` contract and its associated executor contracts from the DG contracts and reconnect them to the `TimelockedGovernance` contract instance.

Disabling the DG subsystem also disables the emergency mode and the emergency execution committee, so any proposal can be executed by the DAO without cooperation from any other actors.

If the emergency execution committee doesn't disable the DG until the emergency mode max duration elapses, anyone gets the right to deactivate the emergency mode, switching the system back to the protected mode and disabling the emergency committee.

> Note: the protected deployment mode and emergency mode are only designed to protect from a vulnerability in the DG contracts and assume the honest and operational DAO. The system is not designed to handle a situation when there's a vulnerability in the DG contracts AND the DAO is captured/malicious or otherwise dysfunctional.


## Governance state

The DG system implements a state machine tracking the **global governance state** defining which governance actions are currently possible. The state is global since it affects all non-executed proposals and all system actors.

The state machine is specified in the [Dual Governance mechanism design][mech design] document. The possible states are:

- `Normal` allows proposal submission and scheduling for execution.
- `VetoSignalling` only allows proposal submission.
    - `VetoSignallingDeactivation` sub-state (doesn't deactivate the parent state upon entry) doesn't allow proposal submission or scheduling for execution.
- `VetoCooldown` only allows scheduling already submitted proposals for execution.
- `RageQuit` only allows proposal submission.

![image](https://github.com/lidofinance/dual-governance/assets/1699593/44c2b253-6ea2-4aac-a1c6-fd54cec92887)

Possible state transitions:

- `Normal` → `VetoSignalling`
- `VetoSignalling` → `RageQuit`
- `VetoSignalling` → `VetoSignallingDeactivation` - sub-state entry and exit (while the parent `VetoSignalling` state is active)
- `VetoSignallingDeactivation` → `RageQuit`
- `VetoSignallingDeactivation` → `VetoCooldown`
- `VetoCooldown` → `Normal`
- `VetoCooldown` → `VetoSignalling`
- `RageQuit` → `VetoCooldown`
- `RageQuit` → `VetoSignalling`

These transitions are enabled by three processes (see the [mechanism design document][mech design] for more details):

1. **Rage quit support** changing due to stakers locking and unlocking their tokens into/out of the veto signalling escrow or stETH total supply changing;
2. Protocol withdrawals processing (in the `RageQuit` state);
3. Time passing.

![image](https://github.com/lidofinance/dual-governance/assets/1699593/118c26ef-5187-469f-a5ab-aea945fdb6aa)


## Rage quit

Rage quit is a global process of withdrawing stETH and wstETH locked in the signalling escrow and waiting until all these withdrawals, as well as any withdrawals represented by withdrawal NFTs that were locked into the signalling escrow prior to the process started, are finished.

![image](https://github.com/lidofinance/dual-governance/assets/1699593/4b42490e-4d67-4277-b1e1-390d4c385ca8)

In the [governance state machine](#Governance-state), the rage quit process is represented by the `RageQuit` global state. While this state is active, no proposal can be scheduled for execution. Thus, rage quit contributes to dynamic timelocks of all pending proposals.

At any time, only one instance of the rage quit process can be active.

From the stakers' point of view, opposition to the DAO and the rage quit process can be described by the following diagram:

![image](https://github.com/lidofinance/dual-governance/assets/1699593/f0f3647d-e251-458c-8556-2c481c2df35b)


## Tiebreaker committee

The mechanism design allows for a deadlock where the system is stuck in the `RageQuit` state while protocol withdrawals are paused or dysfunctional and require a DAO vote to resume, and includes a third-party arbiter Tiebreaker committee for resolving it.

The committee gains the power to execute pending proposals, bypassing the DG dynamic timelock, and unpause any protocol contract under the specific conditions of the deadlock. The detailed Tiebreaker mechanism design can be found in the [Dual Governance mechanism design overview][mech design - tiebreaker] document.

The Tiebreaker committee is represented in the system by its address which can be configured via the admin executor calling the [`DualGovernance.setTiebreakerCommittee`](#Function-DualGovernancesetTiebreakerCommittee) function.

While the deadlock conditions are met, the Tiebreaker committee address is allowed to:

1. Schedule execution of any pending proposal by calling [`DualGovernance.tiebreakerScheduleProposal`] after the tiebreaker activation timeout passes.
2. Unpause of a pausable ("sealable") protocol contract by calling  [`DualGovernance.tiebreakerResumeSealable`] after the tiebreaker activation timeout passes.


## Administrative actions

The dual governance system supports a set of administrative actions, including:

- Changing the configuration options.
- [Upgrading the system's code](#Upgrade-flow-description).
- Managing the [deployment mode](#Proposal-execution-and-deployment-modes): configuring or disabling the emergency protection delay, setting the emergency committee addresses and lifetime.
- Setting the [Tiebreaker committee](#Tiebreaker-committee) address.

Each of these actions can only be performed by a designated **admin executor** contract (declared in the `EmergencyProtectedTimelock` instance), meaning that:

1. It has to be proposed by one of the proposers associated with this executor. Such proposers are called **admin proposers**.
2. It has to go through the dual governance execution flow with stakers having the power to object.


## Common types

### Struct: `ExternalCall`

```solidity
struct ExternalCall {
    address target;
    uint96 value;
    bytes payload;
}
```

Encodes an EVM call from an executor contract to the `target` address with the specified `value` and the calldata being set to `payload`.

---

## Contract: `DualGovernance`

The main entry point to the dual governance system.

- Provides an interface for submitting and cancelling governance proposals and implements a dynamic timelock on scheduling their execution.
- Manages the list of supported proposers (DAO voting systems).
- Implements a state machine tracking the current [global governance state](#Governance-state) which, in turn, determines whether proposal submission and execution is currently allowed.
- Deploys and tracks the [`Escrow`](#Contract-Escrow) contract instances. Tracks the current signalling escrow.

This contract is a singleton, meaning that any DG deployment includes exactly one instance of this contract.


### Enum: `DualGovernanceStateMachine.State`

```solidity
enum State {
    NotInitialized, // Indicates an uninitialized state during the contract creation
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}
```

Encodes the current global [governance state](#Governance-state), affecting the set of actions allowed for each of the system's actors.

---

### Function: `DualGovernance.submitProposal`

```solidity
function submitProposal(ExternalCall[] calls, string calldata metadata)
  returns (uint256 proposalId)
```

Instructs the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) singleton instance to register a new governance proposal composed of one or more EVM `calls`, along with the attached `metadata` text. The proposal will be executed by an executor contract associated with the proposer address calling this function at the moment of submission. Starts a dynamic timelock on [scheduling the proposal](#Function-DualGovernancescheduleProposal) for execution.

See: [`EmergencyProtectedTimelock.submit`](#Function-EmergencyProtectedTimelocksubmit).

Returns the id of the successfully registered proposal.

#### Preconditions

- The calling address MUST be [registered as a proposer](#Function-DualGovernanceregisterProposer).
- The current governance state MUST be either of: `Normal`, `VetoSignalling`, `RageQuit`.
- The number of EVM calls MUST be greater than zero.

Triggers a transition of the current governance state (if one is possible) before checking the preconditions.

---

### Function: `DualGovernance.scheduleProposal`

```solidity
function scheduleProposal(uint256 proposalId)
```

Schedules a previously submitted proposal for execution in the Dual Governance system. The function ensures that the proposal meets specific conditions before it can be scheduled. If the conditions are met, the proposal is registered for execution in the `EmergencyProtectedTimelock` singleton instance.

Preconditions

- The proposal with the specified proposalId MUST exist in the system.
- The required delay since submission (`EmergencyProtectedTimelock.getAfterSubmitDelay`) MUST have elapsed.
- The Dual Governance system MUST be in the `Normal` or `VetoCooldown` state
- If the system is in the `VetoCooldown` state, the proposal MUST have been submitted not later than the `VetoSignalling` state was entered.
- The proposal MUST NOT have been cancelled.
- The proposal MUST NOT already be scheduled.

Triggers a transition of the current governance state (if one is possible) before checking the preconditions.

---

### Function: `DualGovernance.cancelAllPendingProposals`

```solidity
function cancelAllPendingProposals() returns (bool)
```

Cancels all currently submitted and non-executed proposals. If a proposal was submitted but not scheduled, it becomes unschedulable. If a proposal was scheduled, it becomes unexecutable.

If the current governance state is neither `VetoSignalling` nor `VetoSignallingDeactivation`, the function will exit early without canceling any proposals, emitting the `CancelAllPendingProposalsSkipped` event and returning `false`.
If proposals are successfully cancelled, the `CancelAllPendingProposalsExecuted` event will be emitted, and the function will return `true`.

#### Preconditions

- MUST be called by an authorized `proposalsCanceller`.

Triggers a transition of the current governance state, if one is possible.

---

### Function: `DualGovernance.activateNextState`

```solidity
function activateNextState()
```

Triggers a transition of the [global governance state](#Governance-state), if one is possible; does nothing otherwise.

> [!NOTE]
> This is a permissionless function intended to be called when the `persisted` and `effective` states are not equal, in order to apply the next pending Dual Governance state transition.

---

### Function: `DualGovernance.setConfigProvider`

```solidity
function setConfigProvider(IDualGovernanceConfigProvider newConfigProvider)
```

Sets the configuration provider for the Dual Governance system.

#### Preconditions
- MUST be called by the admin executor.
- The `newConfigProvider` address MUST NOT be the zero address.
- The `newConfigProvider` address MUST NOT be the same as the current configuration provider.
- The values returned by the config MUST be valid:
  - `firstSealRageQuitSupport` MUST be less than `secondSealRageQuitSupport`.
  - `secondSealRageQuitSupport` MUST be less than or equal to 100%, represented as a percentage with 16 decimal places of precision.
  - `vetoSignallingMinDuration` MUST be less than `vetoSignallingMaxDuration`.
  - `rageQuitEthWithdrawalsMinDelay` MUST be less than or equal to `rageQuitEthWithdrawalsMaxDelay`.
  - `minAssetsLockDuration` MUST NOT be zero.
  - `minAssetsLockDuration` MUST NOT exceed `Escrow.MAX_MIN_ASSETS_LOCK_DURATION`.

---

### Function: `DualGovernance.setProposalsCanceller`

```solidity
function setProposalsCanceller(address newProposalsCanceller)
```

Updates the address of the proposals canceller authorized to cancel pending proposals. Typically, this should be set to one of the DAO voting systems but can also be assigned to a contract with additional logic.

#### Preconditions
- MUST be called by the admin executor.
- The `newProposalsCanceller` address MUST NOT be the zero address.
- The `newProposalsCanceller` address MUST NOT be the same as the current proposals canceller.

---

### Function: `DualGovernance.getProposalsCanceller`

```solidity
function getProposalsCanceller() view returns (address)
```

Returns the address of the current proposals canceller.

---

### Function: `DualGovernance.getConfigProvider`

```solidity
function getConfigProvider() view returns (IDualGovernanceConfigProvider)
```

Returns the current configuration provider for the Dual Governance system.

---

### Function: `DualGovernance.getVetoSignallingEscrow`

```solidity
function getVetoSignallingEscrow() view returns (address)
```

Returns the address of the veto signaling escrow contract.

---

### Function: `DualGovernance.getRageQuitEscrow`

```solidity
function getRageQuitEscrow() view returns (address)
```

Returns the address of the rage quit escrow contract associated with the most recent or ongoing rage quit.
If no rage quits have occurred in the system, the returned address will be the zero address.

---

### Function: `DualGovernance.getPersistedState`

```solidity
function getPersistedState() view returns (State persistedState)
```

Returns the most recently persisted state of the DualGovernance.

---

### Function: `DualGovernance.getEffectiveState`

```solidity
function getEffectiveState() view returns (State persistedState)
```

Returns the effective state of the DualGovernance. The effective state refers to the state the DualGovernance would transition to upon calling `DualGovernance.activateNextState`.

---

### Function `DualGovernance.getStateDetails`

```solidity
function getStateDetails() view returns (StateDetails)
```

This function returns detailed information about the current state of the `DualGovernance`, comprising the following data:

- **`State effectiveState`**: The state that the `DualGovernance` would transition to upon calling `DualGovernance.activateNextState`.
- **`State persistedState`**: The current stored state of the `DualGovernance`.
- **`Timestamp persistedStateEnteredAt`**: The timestamp when the `persistedState` was entered.
- **`Timestamp vetoSignallingActivatedAt`**: The timestamp when the `VetoSignalling` state was last activated.
- **`Timestamp vetoSignallingReactivationTime`**: The timestamp when the `VetoSignalling` state was last re-activated.
- **`Timestamp normalOrVetoCooldownExitedAt`**: The timestamp when the `Normal` or `VetoCooldown` state was last exited.
- **`uint256 rageQuitRound`**: The number of continuous RageQuit rounds.
- **`Duration vetoSignallingDuration`**: The duration of the `VetoSignalling` state, calculated based on the RageQuit support in the Veto Signalling `Escrow`.

---

### Function: `DualGovernance.registerProposer`

```solidity
function registerProposer(address proposerAccount, address executor)
```

Registers the `proposerAccount` address in the system as a valid proposer and associates it with the `executor` contract address. The `executor` is expected to be an instance of [`Executor`](#Contract-Executor).

#### Preconditions

- MUST be called by the admin executor.
- The `proposerAccount` address MUST NOT be the zero address.
- The `executor` address MUST NOT be the zero address.
- The `proposerAccount` address MUST NOT already be registered in the system.

---

### Function: `DualGovernance.setProposerExecutor`

```solidity
function setProposerExecutor(address proposerAccount, address newExecutor)
```

Updates the executor associated with a specified proposer. The `newExecutor` is expected to be an instance of [`Executor`](#Contract-Executor).

#### Preconditions

- MUST be called by the admin executor.
- The `proposerAccount` address MUST be registered in the system.
- The `newExecutor` address MUST NOT be the zero address.
- The `newExecutor` address MUST NOT be the same as the current executor associated with the `proposerAccount`.
- Updating the proposer’s executor MUST NOT result in the admin executor having no associated proposer.

---

### Function: `DualGovernance.unregisterProposer`

```solidity
function unregisterProposer(address proposerAccount)
```

Removes the registered `proposerAccount` address from the list of valid proposers and dissociates it with the executor contract address.

#### Preconditions

- MUST be called by the admin executor contract.
- The `proposerAccount` address MUST be registered in the system as proposer.
- The `proposerAccount` address MUST NOT be the only one assigned to the admin executor.

---

### Function: `DualGovernance.getProposer`

```solidity
function getProposer(address proposerAccount) view returns (Proposers.Proposer memory proposer)
```

Returns the proposer data for the specified `proposerAccount` if it is a registered proposer. The returned data includes:
- **`account`**: The address of the registered proposer.
- **`executor`**: The address of the executor associated with the proposer.

#### Preconditions
- The `proposerAccount` MUST be registered in the system as a proposer.

---

### Function: `DualGovernance.getProposers`

```solidity
function getProposers() view returns (Proposers.Proposer[] memory proposers)
```

Returns information about all registered proposers. Each item in the returned array includes the following fields:
- **`account`**: The address of the registered proposer.
- **`executor`**: The address of the executor associated with the proposer.

---

### Function: `DualGovernance.isProposer`

```solidity
function isProposer(address proposerAccount) view returns (bool)
```

Returns whether the specified `proposerAccount` is a registered proposer.

---

### Function: `DualGovernance.isExecutor`

```solidity
function isExecutor(address executor) view returns (bool)
```

Returns whether the specified `executor` address is assigned as the executor for at least one registered proposer.

---

### Function: `DualGovernance.addTiebreakerSealableWithdrawalBlocker`

```solidity
function addTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker)
```

Adds a unique address of a sealable contract that can be paused and may cause a Dual Governance tie (deadlock). A tie may occur when user withdrawal requests cannot be processed due to the paused state of a registered sealable withdrawal blocker while the Dual Governance system is in the RageQuit state.

#### Preconditions

- MUST be called by the admin executor.
- The `sealableWithdrawalBlocker` address MUST implement the `ISealable` interface.
- The total number of registered sealable withdrawal blockers MUST NOT equal `DualGovernance.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT`.
- The `sealableWithdrawalBlocker` address MUST NOT be in a paused state at the time of addition.
- The `sealableWithdrawalBlocker` address MUST NOT already be registered.

---

### Function: `DualGovernance.removeTiebreakerSealableWithdrawalBlocker`

```solidity
function removeTiebreakerSealableWithdrawalBlocker(address sealableWithdrawalBlocker)
```

Removes a previously registered `sealableWithdrawalBlocker` contract from the system.

#### Preconditions

- MUST be called by the admin executor contract.
- The `sealableWithdrawalBlocker` address MUST have been previously registered using the `DualGovernance.addTiebreakerSealableWithdrawalBlocker` method.

---

### Function: `DualGovernance.setTiebreakerCommittee`

```solidity
function setTiebreakerCommittee(address newTiebreaker)
```

Updates the address of the [Tiebreaker committee](#Tiebreaker-committee).

#### Preconditions

- MUST be called by the admin executor.
- The `newTiebreaker` address MUST NOT be the zero address.
- The `newTiebreaker` address MUST be different from the current tiebreaker address.

---

### Function: `DualGovernance.setTiebreakerActivationTimeout`

```solidity
function setTiebreakerActivationTimeout(Duration newTiebreakerActivationTimeout)
```

Sets a new value for the tiebreaker activation timeout. If the Dual Governance system remains out of the `Normal` or `VetoCooldown` state for longer than the `tiebreakerActivationTimeout` duration, the tiebreaker committee is permitted to schedule submitted proposals.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newTiebreakerActivationTimeout` MUST be greater than or equal to `DualGovernance.MIN_TIEBREAKER_ACTIVATION_TIMEOUT`.
- The `newTiebreakerActivationTimeout` MUST be less than or equal to `DualGovernance.MAX_TIEBREAKER_ACTIVATION_TIMEOUT`.
- The `newTiebreakerActivationTimeout` MUST be different from the current value.

---

### Function: `DualGovernance.tiebreakerResumeSealable`

[`DualGovernance.tiebreakerResumeSealable`]: #Function-DualGovernancetiebreakerResumeSealable

```solidity
function tiebreakerResumeSealable(address sealable)
```

Allows the [Tiebreaker committee](#Tiebreaker-committee) to resume a paused `sealable` contract when the system is in a tie state.

#### Preconditions

- MUST be called by the [Tiebreaker committee](#Tiebreaker-committee) address.
- Either **Tiebreaker Condition A** or **Tiebreaker Condition B** MUST be met (see the [mechanism design document][mech design - tiebreaker]).
- The `sealable` instance MUST currently be paused.
- The `resealManager` MUST have the permissions required to resume the specified `sealable` instance.

Triggers a transition of the [global governance state](#Governance-state), if one is possible, before checking the tie state.

---

### Function: `DualGovernance.tiebreakerScheduleProposal`

[`DualGovernance.tiebreakerScheduleProposal`]: #Function-DualGovernancetiebreakerScheduleProposal

```solidity
function tiebreakerScheduleProposal(uint256 proposalId)
```

Allows the [Tiebreaker committee](#Tiebreaker-committee) to instruct the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) singleton instance to schedule a submitted and non-cancelled proposal with the id `proposalId` for execution. This method bypasses the DG's dynamic timelock and can only be called when the system is in a tie state.

#### Preconditions

- MUST be called by the [Tiebreaker committee](#Tiebreaker-committee) address.
- Either **Tiebreaker Condition A** or **Tiebreaker Condition B** MUST be met (see the [mechanism design document][mech design - tiebreaker]).
- The proposal with the given id MUST have been previously submitted using the `DualGovernance.submitProposal` call.
- The required delay since submission (`EmergencyProtectedTimelock.getAfterSubmitDelay`) MUST have elapsed.
- The proposal MUST NOT already be scheduled.
- The proposal MUST NOT have been cancelled.

Triggers a transition of the current governance state (if one is possible) before checking the preconditions.

---

### Function: `DualGovernance.getTiebreakerDetails`

```solidity
function getTiebreakerDetails() view returns (ITiebreaker.TiebreakerDetails memory tiebreakerState)
```

Returns detailed information about the current tiebreaker state based on the `effective` state of the system. The returned `TiebreakerDetails` struct includes the following data:

- `isTie`: Indicates whether the system is in a tie state, allowing the [Tiebreaker committee](#Tiebreaker-committee) to schedule proposals or resume sealable contracts.
- `tiebreakerCommittee`: The address of the current [Tiebreaker committee](#Tiebreaker-committee).
- `tiebreakerActivationTimeout`: The duration the system must remain in a "locked" state (not in `Normal` or `VetoCooldown` state) before the [Tiebreaker committee](#Tiebreaker-committee) is permitted to take actions.
- `sealableWithdrawalBlockers`: An array of sealable contracts registered in the system as withdrawal blockers.

---

### Function: `DualGovernance.resealSealable`

```solidity
function resealSealable(address sealable)
```

Allows the reseal committee to "reseal" (pause indefinitely) an instance of a sealable contract that is currently paused for a limited duration. This is done using the [`ResealManager`](#Contract-ResealManager) contract.

#### Preconditions

- The system MUST NOT be in the `Normal` state.
- The caller MUST be the `resealCommittee` address.
- The `sealable` address MUST implement the `ISealable` interface.
- The `sealable` instance MUST be paused for a limited duration with a future resume timestamp, and not indefinitely.
- The `resealManager` MUST have the permissions required to pause and resume the specified `sealable` instance.

Triggers a transition of the current governance state (if one is possible) before checking the preconditions.

---

### Function: `DualGovernance.setResealCommittee`

```solidity
function setResealCommittee(address newResealCommittee)
```

Sets the address of the reseal committee.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newResealCommittee` address MUST NOT be the same as the current value.

---

### Function: `DualGovernance.setResealManager`

```solidity
function setResealManager(IResealManager newResealManager)
```

Sets the address of the Reseal Manager contract.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newResealManager` address MUST NOT be the same as the current value.
- The `newResealManager` address MUST NOT be the zero address.

---

### Function: `DualGovernance.getResealManager`

```solidity
function getResealManager() view returns (IResealManager)
```

Returns the address of the Reseal Manager contract.

---

### Function: `DualGovernance.getResealCommittee`

```solidity
function getResealCommittee() view returns (address)
```

Returns the address of the reseal committee.

---

## Contract: `Executor`

Handles calls resulting from governance proposals' execution. Every protocol permission or role protected by the Dual Governance system, as well as the permission to manage these roles or permissions, must be controlled exclusively by instances of this contract.

The system supports multiple instances of this contract, but all instances SHOULD be owned by the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) singleton instance.

This contract extends OpenZeppelin’s `Ownable` contract.

---

### Function: `Executor.execute`

```solidity
function execute(address target, uint256 value, bytes payload) payable
```

Performs an EVM call to the `target` address with the specified `payload` calldata, optionally transferring `value` wei in ETH.

Reverts if the call fails.


#### Preconditions

- MUST be called by the contract owner (which SHOULD be the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) singleton instance).

---

## Contract: `ResealManager`

In the Lido protocol, specific critical components (`WithdrawalQueue` and `ValidatorsExitBus`) are safeguarded by the `GateSeal` contract instance. According to the gate seals [documentation](https://github.com/lidofinance/gate-seals?tab=readme-ov-file#what-is-a-gateseal):

>*"A GateSeal is a contract that allows the designated account to instantly put a set of contracts on pause (i.e. seal) for a limited duration. This will give the Lido DAO the time to come up with a solution, hold a vote, implement changes, etc."*

However, the effectiveness of this approach depends on the predictability of the DAO's solution adoption timeframe. With the dual governance system, proposal execution may experience significant delays depending on the current state of the `DualGovernance` contract. This creates a risk that the `GateSeal`'s pause period may expire before the Lido DAO can implement the necessary fixes.

The `ResealManager` contract addresses this issue by enabling the extension of temporarily paused contracts into a permanent pause or by resuming them if the following conditions are met:
- The contracts are paused for a limited duration, not indefinitely.
- The Dual Governance system is not in the `Normal` state.

To function properly, the `ResealManager` MUST be granted the `PAUSE_ROLE` and `RESUME_ROLE` for the target contracts.

---

### Function: `ResealManager.reseal`

```solidity
function reseal(address sealable)
```

Extends the pause of the specified `sealable` contract indefinitely.

#### Preconditions
- The function MUST be called by the governance address returned by the `EmergencyProtectedTimelock.getGovernance` method.
- The `ResealManager` MUST have the permissions required to pause and resume the specified `sealable` instance.
- The `sealable` instance MUST be paused for a limited duration with a future resume timestamp, and not indefinitely.

---

### Function: `ResealManager.resume`

```solidity
function resume(address sealable)
```

Resumes the specified `sealable` contract if it is scheduled to resume at a future timestamp.

#### Preconditions

- The function MUST be called by the governance address returned by the `EmergencyProtectedTimelock.getGovernance` method.
- The `ResealManager` MUST have the permissions required to resume the specified `sealable` instance.
- The `sealable` instance MUST currently be paused.

---

## Contract: `Escrow`

The `Escrow` contract serves as an accumulator of users' (w)stETH, withdrawal NFTs (unstETH), and ETH. It has two internal states and serves a different purpose depending on its state:

- The initial state is the `SignallingEscrow` state.  In this state, the contract serves as an oracle for users' opposition to DAO proposals. It allows users to lock and unlock (unlocking is permitted only for the caller after the `minAssetsLockDuration` has passed since their last funds locking operation) stETH, wstETH, and withdrawal NFTs, potentially changing the global governance state. The `minAssetsLockDuration` duration, measured in hours, safeguards against manipulating the dual governance state through instant lock/unlock actions within the `Escrow` contract instance.
- The final state is the `RageQuitEscrow` state. In this state, the contract serves as an immutable and ungoverned accumulator for the ETH withdrawn as a result of the [rage quit](#Rage-quit) and enforces a timelock on reclaiming this ETH by users.

The `DualGovernance` contract tracks the current signalling escrow contract using the `DualGovernance.getVetoSignallingEscrow` pointer. Upon the initial deployment of the system, an instance of `Escrow` is deployed in the `SignallingEscrow` state by the `DualGovernance` contract, and the `DualGovernance.getVetoSignallingEscrow` pointer is set to this contract.

Each time the governance enters the global `RageQuit` state, two things happen simultaneously:

1. The `Escrow` instance currently stored in the `DualGovernance.getVetoSignallingEscrow` pointer changes its state from `SignallingEscrow` to `RageQuitEscrow`. This is the only possible (and thus irreversible) state transition.
2. The `DualGovernance` contract deploys a new instance of `Escrow` in the `SignallingEscrow` state and resets the `DualGovernance.getVetoSignallingEscrow` pointer to this newly-deployed contract.

At any point in time, there can be only one instance of the contract in the `SignallingEscrow` state (so the contract in this state is a singleton) but multiple instances of the contract in the `RageQuitEscrow` state.

After the `Escrow` instance transitions into the `RageQuitEscrow` state, all locked stETH and wstETH tokens are meant to be converted into withdrawal NFTs using the permissionless `Escrow.requestNextWithdrawalsBatch` function.

Once all funds locked in the `Escrow` instance are converted into withdrawal NFTs, finalized, and claimed, the main rage quit phase concludes, and the `Escrow.startRageQuitExtensionPeriod` method may be used to start the `RageQuitExtensionPeriod`.

The purpose of the `startRageQuitExtensionPeriod` is to provide participants who have locked withdrawal NFTs (unstETH) with additional time to [claim](https://docs.lido.fi/contracts/withdrawal-queue-erc721#claim) them before the Lido DAO’s proposal execution is unblocked. During the entire `RageQuit` period (including the `RageQuitExtensionPeriod`), users are able to claim their locked unstETH, ensuring that the DAO cannot affect the ETH tied to their Withdrawal NFT. It is expected that users will claim their unstETH within this time frame to safeguard their ETH. While users can still claim their ETH after the `RageQuitExtensionPeriod`, **they risk losing all ETH associated with their locked unstETH**, as a malicious DAO could still exert control over the `WithdrawalQueue` contract.

When the `startRageQuitExtensionPeriod` period elapses, the `DualGovernance.activateNextState` function exits the `RageQuit` state and initiates the `RageQuitEthWithdrawalsDelay`. Throughout this timelock, tokens remain locked within the `Escrow` instance and are inaccessible for withdrawal. Once the timelock expires, participants in the rage quit process can retrieve their ETH by withdrawing it from the `Escrow` instance.

The duration of the `RageQuitEthWithdrawalsDelay` is dynamic and varies based on the number of "continuous" rage quits. A pair of rage quits is considered continuous when `DualGovernance` has not transitioned to the `Normal` or `VetoCooldown` state between them.

---

### Enum: `EscrowState.State`

```solidity
enum State {
    NotInitialized,
    SignallingEscrow,
    RageQuitEscrow
}
```

Encodes the current state of an `Escrow` instance. The `NotInitialized` value is expected to apply only to the master copy implementation of the `Escrow` contract. At any given time, one instance must be in the `SignallingEscrow` state, while zero or more instances may be in the `RageQuitEscrow` state.

---

### Function: `Escrow.initialize`

```solidity
function initialize(Duration minAssetsLockDuration)
```

The `Escrow` instance is intended to be used behind [minimal proxy contracts](https://eips.ethereum.org/EIPS/eip-1167). This method initializes a proxy instance in the `SignallingEscrow` state with the specified minimum assets lock duration. The method can be called only once and is designed for use by the `DualGovernance` contract.

#### Preconditions

- MUST be called using the proxy contract.
- MUST be called by the `DualGovernance` contract.
- MUST NOT have been initialized previously.
- `minAssetsLockDuration` MUST NOT exceed `Escrow.MAX_MIN_ASSETS_LOCK_DURATION`.
- `minAssetsLockDuration` MUST NOT be equal to previous value (by default `0`).

---

### Function: `Escrow.getEscrowState`

```solidity
function getEscrowState() view returns (EscrowState.State)
```

Returns the current state of the `Escrow` instance, as defined by the `EscrowState.State` enum.

---

### Function: `Escrow.lockStETH`

```solidity!
function lockStETH(uint256 amount) external returns (uint256 lockedStETHShares)
```

Transfers the specified `amount` of stETH from the caller's (i.e., `msg.sender`) account into the `SignallingEscrow` instance of the `Escrow` contract.

The total rage quit support is updated proportionally to the number of shares corresponding to the locked stETH (see the `Escrow.getRageQuitSupport` function for the details). For the correct rage quit support calculation, the function updates the number of locked stETH shares in the protocol as follows:

```solidity
amountInShares = stETH.getSharesByPooledEther(amount);

assets[msg.sender].stETHLockedShares += amountInShares;
stETHTotals.lockedShares += amountInShares;
```

The rage quit support will be dynamically updated to reflect changes in the stETH balance due to protocol rewards or validators slashing.

The method calls the `DualGovernance.activateNextState` function at the beginning and end of the execution, which may transition the `Escrow` instance from the `SignallingEscrow` state to the `RageQuitEscrow` state.

> [!IMPORTANT]
> To mitigate possible failures when calling the `Escrow.lockStETH` method, it SHOULD be used alongside the `DualGovernance.getPersistedState`/`DualGovernance.getEffectiveState` methods or the `DualGovernance.getStateDetails` method. These methods help identify scenarios where `persistedState != RageQuit` but `effectiveState == RageQuit`. When this state is detected, locking funds in the `SignallingEscrow` is no longer possible and will revert. In such cases, `DualGovernance.activateNextState` MUST be called to initiate the pending `RageQuit`.

#### Returns

The amount of stETH shares locked by the caller during the current method call.

#### Preconditions

- The `Escrow` instance MUST be in the `SignallingEscrow` state.
- The caller MUST have an allowance set on the stETH token for the `Escrow` instance equal to or greater than the locked `amount`.
- The locked `amount` MUST NOT exceed the caller's stETH balance.
- The locked `amount`, after conversion to stETH shares, MUST be greater than zero.
- The `DualGovernance` contract MUST NOT have a pending state transition to the `RageQuit` state.

---

### Function: `Escrow.unlockStETH`

```solidity
function unlockStETH() external returns (uint256 unlockedStETHShares)
```

Allows the caller (i.e., `msg.sender`) to unlock all previously locked stETH and wstETH in the `SignallingEscrow` instance of the `Escrow` contract as stETH. The locked balance may change due to protocol rewards or validator slashing, potentially altering the original locked amount. The total unlocked stETH amount equals the sum of all previously locked stETH and wstETH by the caller, accounting for any changes during the locking period.

For accurate rage quit support calculation, the function updates the number of locked stETH shares in the protocol as follows:

```solidity
stETHTotals.lockedShares -= _assets[msg.sender].stETHLockedShares;
assets[msg.sender].stETHLockedShares = 0;
```

Additionally, the function triggers the `DualGovernance.activateNextState` function at the beginning and end of the execution.

> [!IMPORTANT]
> To mitigate possible failures when calling the `Escrow.unlockStETH` method, it SHOULD be used alongside the `DualGovernance.getPersistedState`/`DualGovernance.getEffectiveState` methods or the `DualGovernance.getStateDetails` method. These methods help identify scenarios where `persistedState != RageQuit` but `effectiveState == RageQuit`. When this state is detected, unlocking funds in the `SignallingEscrow` is no longer possible and will revert. In such cases, `DualGovernance.activateNextState` MUST be called to initiate the pending `RageQuit`.

#### Returns

The amount of stETH shares unlocked by the caller.

#### Preconditions

- The `Escrow` instance MUST be in the `SignallingEscrow` state.
- The caller MUST have a non-zero amount of previously locked stETH in the `Escrow` instance using the `Escrow.lockStETH` function.
- The duration of the `SignallingEscrowMinLockTime` MUST have passed since the caller last invoked any of the methods `Escrow.lockStETH`, `Escrow.lockWstETH`, or `Escrow.lockUnstETH`.
- The `DualGovernance` contract MUST NOT have a pending state transition to the `RageQuit` state.

---

### Function: `Escrow.lockWstETH`

```solidity
function lockWstETH(uint256 amount) external returns (uint256 lockedStETHShares)
```

Transfers the specified `amount` of wstETH from the caller's (i.e., `msg.sender`) account into the `SignallingEscrow` instance of the `Escrow` contract and unwraps it into the stETH.

The total rage quit support is updated proportionally to the `amount` of locked wstETH (see the `Escrow.getRageQuitSupport` function for details). For accurate rage quit support calculation, the function updates the number of locked stETH shares in the protocol as follows:

```solidity
stETHAmount = WST_ETH.unwrap(amount);
// Use `getSharesByPooledEther`, because `unwrap` method may transfer 1 wei less amount of stETH
stETHShares = ST_ETH.getSharesByPooledEth(stETHAmount);

assets[msg.sender].stETHLockedShares += stETHShares;
stETHTotals.lockedShares += stETHShares;
```

The method calls the `DualGovernance.activateNextState` function at the beginning and end of the execution, which may transition the `Escrow` instance from the `SignallingEscrow` state to the `RageQuitEscrow` state.

> [!IMPORTANT]
> To mitigate possible failures when calling the `Escrow.lockWstETH` method, it SHOULD be used alongside the `DualGovernance.getPersistedState`/`DualGovernance.getEffectiveState` methods or the `DualGovernance.getStateDetails` method. These methods help identify scenarios where `persistedState != RageQuit` but `effectiveState == RageQuit`. When this state is detected, locking funds in the `SignallingEscrow` is no longer possible and will revert. In such cases, `DualGovernance.activateNextState` MUST be called to initiate the pending `RageQuit`.

#### Returns

The amount of stETH shares locked by the caller during the current method call.

#### Preconditions

- The `Escrow` instance MUST be in the `SignallingEscrow` state.
- The caller MUST have an allowance set on the wstETH token for the `Escrow` instance equal to or greater than the locked `amount`.
- The locked `amount` MUST NOT exceed the caller's wstETH balance.
- The locked `amount`, after unwrapping to stETH and converting to stETH shares, MUST be greater than zero.
- The `DualGovernance` contract MUST NOT have a pending state transition to the `RageQuit` state.

---

### Function: `Escrow.unlockWstETH`

```solidity
function unlockWstETH() external returns (uint256 unlockedStETHShares)
```

Allows the caller (i.e. `msg.sender`) to unlock previously locked wstETH and stETH from the `SignallingEscrow` instance of the `Escrow` contract as wstETH. The locked balance may change due to protocol rewards or validator slashing, potentially altering the original locked amount. The total unlocked wstETH equals the sum of all previously locked wstETH and stETH by the caller.

For the correct rage quit support calculation, the function updates the number of locked stETH shares in the protocol as follows:

```solidity
stETHTotals.lockedShares -= _assets[msg.sender].stETHLockedShares;
assets[msg.sender].stETHLockedShares = 0;
```

Additionally, the function triggers the `DualGovernance.activateNextState` function at the beginning and end of the execution.

> [!IMPORTANT]
> To mitigate possible failures when calling the `Escrow.unlockWstETH` method, it SHOULD be used alongside the `DualGovernance.getPersistedState`/`DualGovernance.getEffectiveState` methods or the `DualGovernance.getStateDetails` method. These methods help identify scenarios where `persistedState != RageQuit` but `effectiveState == RageQuit`. When this state is detected, unlocking funds in the `SignallingEscrow` is no longer possible and will revert. In such cases, `DualGovernance.activateNextState` MUST be called to initiate the pending `RageQuit`.


#### Returns

The amount of stETH shares unlocked by the caller.

#### Preconditions

- The `Escrow` instance MUST be in the `SignallingEscrow` state.
- The caller MUST have a non-zero amount of previously locked wstETH in the `Escrow` instance using the `Escrow.lockWstETH` function.
- At least the duration of the `SignallingEscrowMinLockTime` MUST have passed since the caller last invoked any of the methods `Escrow.lockStETH`, `Escrow.lockWstETH`, or `Escrow.lockUnstETH`.
- The `DualGovernance` contract MUST NOT have a pending state transition to the `RageQuit` state.

---

### Function: `Escrow.lockUnstETH`

```solidity
function lockUnstETH(uint256[] unstETHIds)
```

Transfers the withdrawal NFTs with ids contained in the `unstETHIds` from the caller's (i.e. `msg.sender`) account into the `SignallingEscrow` instance of the `Escrow` contract.


To correctly calculate the rage quit support (see the `Escrow.getRageQuitSupport` function for the details), updates the number of locked withdrawal NFT shares in the protocol for each withdrawal NFT in the `unstETHIds`,  as follows:

```solidity
uint256 amountOfShares = withdrawalRequests[id].amountOfShares;

assets[msg.sender].unstETHLockedShares += amountOfShares;
unstETHTotals.unfinalizedShares += amountOfShares;
```

The method calls the `DualGovernance.activateNextState` function at the beginning and end of the execution, which may transition the `Escrow` instance from the `SignallingEscrow` state to the `RageQuitEscrow` state.

> [!IMPORTANT]
> To mitigate possible failures when calling the `Escrow.lockUnstETH` method, it SHOULD be used alongside the `DualGovernance.getPersistedState`/`DualGovernance.getEffectiveState` methods or the `DualGovernance.getStateDetails` method. These methods help identify scenarios where `persistedState != RageQuit` but `effectiveState == RageQuit`. When this state is detected, locking funds in the `SignallingEscrow` is no longer possible and will revert. In such cases, `DualGovernance.activateNextState` MUST be called to initiate the pending `RageQuit`.

#### Preconditions

- The `Escrow` instance MUST be in the `SignallingEscrow` state.
- The caller MUST be the owner of all withdrawal NFTs with the given ids.
- The caller MUST grant permission to the `SignallingEscrow` instance to transfer tokens with the given withdrawal NFT ids (`approve` or `setApprovalForAll`).
- The provided withdrawal NFT ids MUST NOT be empty.
- The provided withdrawal NFT ids MUST NOT contain the finalized or claimed withdrawal NFTs.
- The provided withdrawal NFT ids MUST NOT contain duplicates.
- The `DualGovernance` contract MUST NOT have a pending state transition to the `RageQuit` state.

---

### Function: `Escrow.unlockUnstETH`

```solidity
function unlockUnstETH(uint256[] unstETHIds)
```

Allows the caller (i.e. `msg.sender`) to unlock a set of previously locked withdrawal NFTs with ids `unstETHIds` from the `SignallingEscrow` instance of the `Escrow` contract.

To correctly calculate the rage quit support (see the `Escrow.getRageQuitSupport` function for details), updates the number of locked withdrawal NFT shares in the protocol for each withdrawal NFT in the `unstETHIds`, as follows:

- If the withdrawal NFT was marked as finalized (see the `Escrow.markUnstETHFinalized` function for details):

```solidity
uint256 amountOfShares = withdrawalRequests[id].amountOfShares;
uint256 claimableAmount = _getClaimableEther(id);

assets[msg.sender].unstETHLockedShares -= amountOfShares;
unstETHTotals.finalizedETH -= claimableAmount;
unstETHTotals.unfinalizedShares -= amountOfShares;
```

- if the Withdrawal NFT wasn't marked as finalized:

```solidity
uint256 amountOfShares = withdrawalRequests[id].amountOfShares;

assets[msg.sender].unstETHLockedShares -= amountOfShares;
unstETHTotals.unfinalizedShares -= amountOfShares;
```

Additionally, the function triggers the `DualGovernance.activateNextState` function at the beginning and end of the execution.

> [!IMPORTANT]
> To mitigate possible failures when calling the `Escrow.unlockUnstETH` method, it SHOULD be used alongside the `DualGovernance.getPersistedState`/`DualGovernance.getEffectiveState` methods or the `DualGovernance.getStateDetails` method. These methods help identify scenarios where `persistedState != RageQuit` but `effectiveState == RageQuit`. When this state is detected, unlocking funds in the `SignallingEscrow` is no longer possible and will revert. In such cases, `DualGovernance.activateNextState` MUST be called to initiate the pending `RageQuit`.

#### Preconditions

- The `Escrow` instance MUST be in the `SignallingEscrow` state.
- The provided withdrawal NFT ids MUST NOT be empty.
- Each provided withdrawal NFT MUST have been previously locked by the caller.
- At least the duration of the `SignallingEscrowMinLockTime` MUST have passed since the caller last invoked any of the methods `Escrow.lockStETH`, `Escrow.lockWstETH`, or `Escrow.lockUnstETH`.
- The `DualGovernance` contract MUST NOT have a pending state transition to the `RageQuit` state.

---

### Function: `Escrow.markUnstETHFinalized`

```solidity
function markUnstETHFinalized(uint256[] unstETHIds, uint256[] hints)
```

Marks the provided withdrawal NFTs with ids `unstETHIds` as finalized to accurately calculate their rage quit support.

The finalization of the withdrawal NFT leads to the following events:

- The value of the withdrawal NFT is no longer affected by stETH token rebases.
- The total supply of stETH is adjusted based on the value of the finalized withdrawal NFT.

As both of these events affect the rage quit support value, this function updates the number of finalized withdrawal NFTs for the correct rage quit support accounting.

For each withdrawal NFT in the `unstETHIds`:

```solidity
uint256 claimableAmount = _getClaimableEther(id);
uint256 amountOfShares = withdrawalRequests[id].amountOfShares;

unstETHTotals.finalizedETH += claimableAmount;
unstETHTotals.unfinalizedShares -= amountOfShares;
```

Withdrawal NFTs belonging to any of the following categories are excluded from the rage quit support update:

- Claimed or unfinalized withdrawal NFTs
- Withdrawal NFTs already marked as finalized
- Withdrawal NFTs not locked in the `Escrow` instance

The method calls the `DualGovernance.activateNextState` function at the beginning and end of the execution, which may transition the `Escrow` instance from the `SignallingEscrow` state to the `RageQuitEscrow` state.

> [!IMPORTANT]
> To mitigate possible failures when calling the `Escrow.markUnstETHFinalized` method, it SHOULD be used alongside the `DualGovernance.getPersistedState`/`DualGovernance.getEffectiveState` methods or the `DualGovernance.getStateDetails` method. These methods help identify scenarios where `persistedState != RageQuit` but `effectiveState == RageQuit`. When this state is detected, calling methods that change Rage Quit support in the `SignallingEscrow` will no longer be possible and will result in a revert. In such cases, `DualGovernance.activateNextState` MUST be called to initiate the pending `RageQuit`.

#### Preconditions

- The provided withdrawal NFT ids MUST NOT be empty.
- The `Escrow` instance MUST be in the `SignallingEscrow` state.
- The `DualGovernance` contract MUST NOT have a pending state transition to the `RageQuit` state.

---

### Function: `Escrow.startRageQuit`

```solidity
function startRageQuit(
  Duration rageQuitExtensionPeriodDuration,
  Duration rageQuitEthWithdrawalsDelay
)
```

Irreversibly transitions the `Escrow` instance from the `SignallingEscrow` state to the `RageQuitEscrow` state. Following this transition, locked funds become unwithdrawable and are accessible to users only as plain ETH after the completion of the full `RageQuit` process, including the `RageQuitExtensionPeriod` and `RageQuitEthWithdrawalsDelay` stages.

#### Preconditions

- Method MUST be called by the `DualGovernance` contract.
- The `Escrow` instance MUST be in the `SignallingEscrow` state.

---

### Function: `Escrow.setMinAssetsLockDuration`

```solidity
function setMinAssetsLockDuration(Duration newMinAssetsLockDuration)
```

Sets the minimum duration that must elapse after the last stETH, wstETH, or unstETH lock by a vetoer before they are permitted to unlock their assets from the `SignallingEscrow`.

#### Preconditions

- Method MUST be called by the `DualGovernance` contract.
- The `Escrow` instance MUST be in the `SignallingEscrow` state.
- `newMinAssetsLockDuration` MUST NOT be equal to the current value.
- `newMinAssetsLockDuration` MUST NOT exceed `Escrow.MAX_MIN_ASSETS_LOCK_DURATION`.

---

### Function: `Escrow.getRageQuitSupport`

```solidity
function getRageQuitSupport() view returns (PercentD16)
```

Calculates and returns the total rage quit support as a percentage of the stETH total supply locked in the instance of the `Escrow` contract. It considers contributions from stETH, wstETH, and non-finalized withdrawal NFTs while adjusting for the impact of locked finalized withdrawal NFTs.

The returned value represents the total rage quit support expressed as a percentage with a precision of 16 decimals, calculated using the following formula:

```math
\frac{ \text{stETH.getPooledEtherByShares} (\text{lockedShares} + \text{unfinalizedShares}) + \text{finalizedETH} }{ \text{stETH.totalSupply()} + \text{finalizedETH} }
```
where :
- `finalizedETH` refers to `unstETHTotals.finalizedETH`
- `unfinalizedShares` refers to `stETHTotals.lockedShares + unstETHTotals.unfinalizedShares`

---

### Function: `Escrow.getMinAssetsLockDuration`

```solidity
function getMinAssetsLockDuration() view returns (Duration minAssetsLockDuration)
```

Returns the minimum duration that must elapse after the most recent stETH, wstETH, or unstETH lock by a vetoer before they are allowed to unlock their assets from the `SignallingEscrow`.

---

### Function: `Escrow.getVetoerDetails`

```solidity
function getVetoerDetails(address vetoer) view returns (VetoerDetails memory details)
```

Returns the state of locked assets for a specific vetoer. The `VetoerDetails` struct includes the following fields:

- `unstETHIdsCount`: The total number of unstETH NFTs locked by the vetoer.
- `stETHLockedShares`: The total number of stETH shares locked by the vetoer.
- `unstETHLockedShares`: The total number of unstETH shares locked by the vetoer.
- `lastAssetsLockTimestamp`: The timestamp of the most recent assets lock by the vetoer.

---

### Function: `Escrow.getVetoerUnstETHIds`

```solidity
function getVetoerUnstETHIds(address vetoer) view returns (uint256[] memory unstETHIds)
```

Returns the ids of the unstETH NFTs locked by the specified vetoer.

---

### Function: `Escrow.getSignallingEscrowDetails`

```solidity
function getSignallingEscrowDetails() view returns (SignallingEscrowDetails memory details)
```

Returns the total amounts of locked and claimed assets in the Escrow. The `SignallingEscrowDetails` struct includes the following fields:

- `totalStETHClaimedETH`: The total amount of ETH claimed from locked stETH.
- `totalStETHLockedShares`: The total number of stETH shares currently locked in the Escrow.
- `totalUnstETHUnfinalizedShares`: The total number of shares from unstETH NFTs that have not yet been finalized.
- `totalUnstETHFinalizedETH`: The total amount of ETH from finalized unstETH NFTs.

---

### Function: `Escrow.getLockedUnstETHDetails`

```solidity
function getLockedUnstETHDetails(uint256[] calldata unstETHIds) view returns (LockedUnstETHDetails[] memory unstETHDetails)
```

Retrieves details of locked unstETH records for the specified ids. Each `LockedUnstETHDetails` struct includes the following fields:

- `id`: The id of the locked unstETH NFT.
- `status`: The current status of the unstETH record. This value is described by the `UnstETHRecordStatus` enum, with the following possible values: `NotLocked`, `Locked`, `Finalized`, `Claimed`, and `Withdrawn`.
- `lockedBy`: The address that locked the unstETH record.
- `shares`: The number of shares associated with the locked unstETH.
- `claimableAmount`: The amount of claimable ETH in the unstETH. This value is `0` until the unstETH is finalized or claimed.

#### Preconditions

- All `unstETHIds` MUST be locked in the `Escrow` instance.

---

### Function: `Escrow.requestNextWithdrawalsBatch`

```solidity
function requestNextWithdrawalsBatch(uint256 batchSize)
```

Transfers stETH held in the `RageQuitEscrow` instance into the `WithdrawalQueue`. The function may be invoked multiple times until all stETH is converted into withdrawal NFTs. For each withdrawal NFT, the owner is set to `Escrow` contract instance. Each call creates  `batchSize` withdrawal requests (except the final one, which may contain fewer items), where each withdrawal request size equals `WithdrawalQueue.MAX_STETH_WITHDRAWAL_AMOUNT`, except for potentially the last batch, which may have a smaller size.

Upon execution, the function tracks the ids of the withdrawal requests generated by all invocations. When the remaining stETH balance on the contract falls below `max(_MIN_TRANSFERRABLE_ST_ETH_AMOUNT, WITHDRAWAL_QUEUE.MIN_STETH_WITHDRAWAL_AMOUNT)`, the generation of withdrawal batches is concluded, and subsequent function calls will revert.

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.
- The `batchSize` MUST be greater than or equal to `Escrow.MIN_WITHDRAWALS_BATCH_SIZE`.
- The generation of withdrawal request batches MUST not be concluded.

---

### Function: `Escrow.claimNextWithdrawalsBatch(uint256, uint256[])`

```solidity
function claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] hints)
```

Allows users to claim finalized withdrawal NFTs generated by the `Escrow.requestNextWithdrawalsBatch` function.
This function updates the `stETHTotals.claimedETH` variable to track the total amount of claimed ETH.

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.
- The `RageQuitExtensionPeriod` MUST NOT have already been started.
- The `fromUnstETHId` MUST be equal to the id of the first unclaimed withdrawal NFT locked in the `Escrow`. The ids of the unclaimed withdrawal NFTs can be retrieved via the `getNextWithdrawalBatch` method.
- The `hints` array MUST NOT be empty. 
- There MUST be at least one unclaimed withdrawal NFT.

---

### Function: `Escrow.claimNextWithdrawalsBatch(uint256)`

```solidity
function claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount)
```

This is an overload version of `Escrow.claimNextWithdrawalsBatch(uint256, uint256[])`. It retrieves hints for processing the withdrawal NFTs on-chain.

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.
- The `RageQuitExtensionPeriod` MUST NOT have already been started.
- The `maxUnstETHIdsCount` MUST NOT be equal to zero. 
- There MUST be at least one unclaimed withdrawal NFT.

---

### Function: `Escrow.startRageQuitExtensionPeriod`

```solidity
function startRageQuitExtensionPeriod()
```

Initiates the `RageQuitExtensionPeriod` once all withdrawal batches have been claimed. In cases where the `Escrow` instance only has locked unstETH NFTs, it verifies that the last unstETH NFT registered in the `WithdrawalQueue` at the time of the `Escrow.startRageQuit` call is finalized. This ensures that every unstETH NFT locked in the Escrow can be claimed by the user during the `RageQuitExtensionPeriod`.

#### Preconditions
- All withdrawal batches MUST be formed using the `Escrow.requestNextWithdrawalsBatch`.
- The last unstETH NFT in the `WithdrawalQueue` at the time of the `Escrow.startRageQuit` call MUST be finalized.
- All withdrawal batches generated during `Escrow.requestNextWithdrawalsBatch` MUST be claimed.
- The `RageQuitExtensionPeriod` MUST NOT have already been started.

---

### Function: `Escrow.claimUnstETH`

```solidity
function claimUnstETH(uint256[] unstETHIds, uint256[] hints)
```

Allows users to claim the ETH associated with finalized withdrawal NFTs with ids `unstETHIds` locked in the `Escrow` contract. Upon calling this function, the claimed ETH is transferred to the `Escrow` contract instance.

To safeguard the ETH associated with withdrawal NFTs, this function should be invoked when the `Escrow` is in the `RageQuitEscrow` state and before the `RageQuitExtensionPeriod` ends. The ETH corresponding to unclaimed withdrawal NFTs after this period ends would still be controlled by the code potentially affected by pending and future DAO decisions.

> [!NOTE]
> This method does not require the caller (`msg.sender`) to be the original owner of the `unstETHIds`. This allows users who previously locked their NFTs in the `Escrow` to have them claimed from a different address.

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.
- The provided `unstETHIds` MUST only contain finalized but unclaimed withdrawal requests.

---

### Function: `Escrow.withdrawETH`

```solidity
function withdrawETH()
```

Allows the caller (i.e. `msg.sender`) to withdraw all stETH and wstETH they have previously locked into `Escrow` contract instance (while it was in the `SignallingEscrow` state) as plain ETH, given that the `RageQuit` process is completed and that the `RageQuitEthWithdrawalsDelay` has elapsed. Upon execution, the function transfers ETH to the caller's account and marks the corresponding stETH and wstETH as withdrawn for the caller.

The amount of ETH sent to the caller is determined by the proportion of the user's stETH and wstETH shares compared to the total amount of locked stETH and wstETH shares in the Escrow instance, calculated as follows:

```solidity
return stETHTotals.claimedETH * assets[msg.sender].stETHLockedShares
    / stETHTotals.lockedShares;
```

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.
- The rage quit process MUST be completed, including the expiration of the `RageQuitExtensionPeriod` duration.
- The `RageQuitEthWithdrawalsDelay` period MUST be elapsed after the expiration of the `RageQuitExtensionPeriod` duration.
- The caller MUST have a non-zero amount of stETH shares to withdraw.

---

### Function: `Escrow.withdrawETH(uint256[])`

```solidity
function withdrawETH(uint256[] unstETHIds)
```

Allows the caller (i.e. `msg.sender`) to withdraw the claimed ETH from the withdrawal NFTs with ids `unstETHIds` locked by the caller in the `Escrow` contract while the latter was in the `SignallingEscrow` state. Upon execution, all ETH previously claimed from the NFTs is transferred to the caller's account, and the NFTs are marked as withdrawn.

#### Preconditions

- The `unstETHIds` array MUST NOT be empty.
- The `Escrow` instance MUST be in the `RageQuitEscrow` state.
- The rage quit process MUST be completed, including the expiration of the `RageQuitExtensionPeriod` duration.
- The `RageQuitEthWithdrawalsDelay` period MUST be elapsed after the expiration of the `RageQuitExtensionPeriod` duration.
- The caller MUST be set as the owner of the provided NFTs.
- Each withdrawal NFT MUST have been claimed using the `Escrow.claimUnstETH` function.
- Withdrawal NFTs must not have been withdrawn previously.

---

### Function: `Escrow.getNextWithdrawalBatch`

```solidity
function getNextWithdrawalBatch(uint256 limit) view returns (uint256[] memory unstETHIds)
```

Returns the ids of the next batch of unstETH NFTs available for claiming. The `limit` parameter specifies the maximum number of ids to include in the resulting array.

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.

---

### Function: `Escrow.isWithdrawalsBatchesClosed`

```solidity
function isWithdrawalsBatchesClosed() view returns (bool)
```

Returns whether all withdrawal batches have been closed.

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.

---

### Function: `Escrow.getUnclaimedUnstETHIdsCount`

```solidity
function getUnclaimedUnstETHIdsCount() view returns (uint256)
```

Returns the total number of unstETH NFTs that have not yet been claimed.

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.

---

### Function: `Escrow.isRageQuitFinalized`

```solidity
function isRageQuitFinalized() view returns (bool)
```

Returns whether the rage quit process has been finalized. The rage quit process is considered finalized when all the following conditions are met:
- The `Escrow` instance is in the `RageQuitEscrow` state.
- All withdrawal request batches have been claimed.
- The duration of the `RageQuitExtensionPeriod` has elapsed.

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.

---

### Function: `Escrow.getRageQuitEscrowDetails`

```solidity
function getRageQuitEscrowDetails() view returns (RageQuitEscrowDetails memory details)
```

Returns details about the current state of the rage quit escrow. The `RageQuitEscrowDetails` struct includes the following fields:

- `isRageQuitExtensionPeriodStarted`: A boolean indicating whether the rage quit extension period has started.
- `rageQuitEthWithdrawalsDelay`: The delay period (in seconds) for ETH withdrawals during the rage quit process.
- `rageQuitExtensionPeriodDuration`: The duration (in seconds) of the rage quit extension period.
- `rageQuitExtensionPeriodStartedAt`: The timestamp when the rage quit extension period started.

#### Preconditions

- The `Escrow` instance MUST be in the `RageQuitEscrow` state.

---

### Function: `Escrow.receive`

```solidity
receive() external payable
```

Accepts ETH payments exclusively from the `WithdrawalQueue` contract.

#### Preconditions

- The ETH sender MUST be the address of the `WithdrawalQueue` contract.


## Contract: `EmergencyProtectedTimelock`

`EmergencyProtectedTimelock` is the singleton instance storing proposals approved by DAO voting systems and submitted to the Dual Governance. It allows for setting up time-bound **Emergency Activation Committee** and **Emergency Execution Committee**, acting as safeguards for the case of zero-day vulnerability in Dual Governance contracts.

For a proposal to be executed, the following steps have to be performed in order:

1. The proposal must be submitted using the `EmergencyProtectedTimelock.submit` function.
2. The configured post-submit timelock (`EmergencyProtectedTimelock.getAfterSubmitDelay`) must elapse.
3. The proposal must be scheduled using the `EmergencyProtectedTimelock.schedule` function.
4. The configured emergency protection delay (`EmergencyProtectedTimelock.getAfterScheduleDelay`) must elapse (can be zero, see below).
5. The proposal must be executed using the `EmergencyProtectedTimelock.execute` function.

The contract only allows proposal submission and scheduling by the `governance` address. Normally, this address points to the [`DualGovernance`](#Contract-DualGovernances) singleton instance. Proposal execution is permissionless, unless Emergency Mode is activated.

If the Emergency Committees are set up and active, the `EmergencyProtectedTimelock` may be configured, making governance proposal getting a separate emergency protection delay between submitting and scheduling. This additional timelock is implemented in the `EmergencyProtectedTimelock` contract to protect from zero-day vulnerability in the logic of `DualGovernance` and other core DG contracts. If the Emergency Committees aren't set, the proposal flow is the same, and the timelock duration may be set to zero.

Emergency Activation Committee, while active, can enable the Emergency Mode. This mode prohibits anyone but the Emergency Execution Committee from executing proposals. It also allows the Emergency Execution Committee to reset the governance, effectively disabling the Dual Governance subsystem.

The governance reset entails the following steps:

1. Clearing both the Emergency Activation and Execution Committees from the `EmergencyProtectedTimelock`.
2. Cancelling all proposals that have not been executed.
3. Setting the `governance` address to a pre-configured Emergency Governance address. In the simplest scenario, this would be the instance of the [`TimelockedGovernance`](plan-b.md#contract-timelockedgovernance) contract connected to the Lido DAO Aragon Voting contract.

---

### Function: `EmergencyProtectedTimelock.MIN_EXECUTION_DELAY`

```solidity
Duration public immutable MIN_EXECUTION_DELAY;
```

The minimum duration that must pass between a proposal's submission and its execution.

---

### Function: `EmergencyProtectedTimelock.MAX_AFTER_SUBMIT_DELAY`

```solidity
Duration public immutable MAX_AFTER_SUBMIT_DELAY;
```

The upper bound for the delay required before a submitted proposal can be scheduled for execution.

---

### Function: `EmergencyProtectedTimelock.MAX_AFTER_SCHEDULE_DELAY`

```solidity
Duration public immutable MAX_AFTER_SCHEDULE_DELAY;
```

The upper bound for the delay required before a scheduled proposal can be executed.

---

### Function: `EmergencyProtectedTimelock.MAX_EMERGENCY_MODE_DURATION`

```solidity
Duration public immutable MAX_EMERGENCY_MODE_DURATION;
```

The upper bound for the time the timelock can remain in emergency mode.

---

### Function: `EmergencyProtectedTimelock.MAX_EMERGENCY_PROTECTION_DURATION`

```solidity
Duration public immutable MAX_EMERGENCY_PROTECTION_DURATION;
```

The upper bound for the time the emergency protection mechanism can be activated.

---

### Function: `EmergencyProtectedTimelock.submit`

```solidity
function submit(address executor, ExternalCall[] calls)
  returns (uint256 proposalId)
```

Registers a new governance proposal consisting of one or more EVM `calls` to be executed by the specified `executor` contract.

#### Returns

The id of the successfully registered proposal.

#### Preconditions

- MUST be called by the `governance` address.
- The `calls` array MUST NOT be empty.

---

### Function: `EmergencyProtectedTimelock.schedule`

```solidity
function schedule(uint256 proposalId)
```

Schedules a previously submitted and non-cancelled proposal for execution after the required delay has passed.

#### Preconditions

- MUST be called by the `governance` address.
- The proposal MUST have been previously submitted.
- The proposal MUST NOT have been cancelled.
- The proposal MUST NOT already be scheduled.
- `EmergencyProtectedTimelock.getAfterSubmitDelay` MUST have elapsed since the proposal submission.

---

### Function: `EmergencyProtectedTimelock.execute`

```solidity
function execute(uint256 proposalId)
```

Instructs the executor contract associated with the proposal to issue the proposal's calls.

#### Preconditions

- Emergency Mode MUST NOT be active.
- The proposal MUST be already submitted & scheduled for execution.
- The proposal MUST NOT have been cancelled.
- `EmergencyProtectedTimelock.MIN_EXECUTION_DELAY` MUST have elapsed since the proposal’s submission.
- `EmergencyProtectedTimelock.getAfterScheduleDelay` MUST have elapsed since the proposal was scheduled for execution.

---

### Function: `EmergencyProtectedTimelock.cancelAllNonExecutedProposals`

```solidity
function cancelAllNonExecutedProposals()
```

Cancels all non-executed proposal, making them forever non-executable.

#### Preconditions

- MUST be called by the `governance` address.

---

### Function: `EmergencyProtectedTimelock.setGovernance`

```solidity
function setGovernance(address newGovernance)
```

Updates the address of the `governance` and cancels all non-executed proposals.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newGovernance` address MUST NOT be the zero address.
- The `newGovernance` address MUST NOT be the same as the current value.

---

### Function: `EmergencyProtectedTimelock.setAfterSubmitDelay`

```solidity
function setAfterSubmitDelay(Duration newAfterSubmitDelay)
```

Sets the delay required between the submission of a proposal and its scheduling for execution. Ensures that the new delay value complies with the defined sanity check bounds.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newAfterSubmitDelay` duration MUST NOT exceed the `EmergencyProtectedTimelock.MAX_AFTER_SUBMIT_DELAY` value.
- The `newAfterSubmitDelay` duration MUST NOT be the same as the current value.
- After the update, the sum of `afterSubmitDelay` and `afterScheduleDelay` MUST NOT be less than the `EmergencyProtectedTimelock.MIN_EXECUTION_DELAY`.

---

### Function: `EmergencyProtectedTimelock.setAfterScheduleDelay`

```solidity
function setAfterScheduleDelay(Duration newAfterScheduleDelay)
```

Sets the delay required to pass from the scheduling of a proposal before it can be executed. Ensures that the new delay value complies with the defined sanity check bounds.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newAfterScheduleDelay` duration MUST NOT exceed the `EmergencyProtectedTimelock.MAX_AFTER_SCHEDULE_DELAY` value.
- The `newAfterScheduleDelay` duration MUST NOT be the same as the current value.
- After the update, the sum of `afterSubmitDelay` and `afterScheduleDelay` MUST NOT be less than the `EmergencyProtectedTimelock.MIN_EXECUTION_DELAY`.

---

### Function: `EmergencyProtectedTimelock.transferExecutorOwnership`

```solidity
function transferExecutorOwnership(address executor, address owner)
```

Transfers ownership of the specified executor contract to a new owner.

#### Preconditions

- MUST be called by the admin executor contract.
- The `executor` MUST implement the `IOwnable` interface.
- The current owner of the `executor` (`executor.owner`) MUST be the address of the `EmergencyProtectedTimelock` instance.

---

### Function: `EmergencyProtectedTimelock.setEmergencyProtectionActivationCommittee`

```solidity
function setEmergencyProtectionActivationCommittee(address newEmergencyActivationCommittee)
```

Sets the address of the emergency activation committee.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newEmergencyActivationCommittee` duration MUST NOT be the same as the current value.

---

### Function: `EmergencyProtectedTimelock.setEmergencyProtectionExecutionCommittee`

```solidity
function setEmergencyProtectionExecutionCommittee(address newEmergencyExecutionCommittee)
```

Sets the address of the emergency execution committee.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newEmergencyExecutionCommittee` address MUST NOT be the same as the current value.

---

### Function: `EmergencyProtectedTimelock.setEmergencyProtectionEndDate`

```solidity
function setEmergencyProtectionEndDate(Timestamp newEmergencyProtectionEndDate)
```

Sets the end date for the emergency protection period.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newEmergencyProtectionEndDate` MUST NOT be farther in the future than `EmergencyProtectedTimelock.MAX_EMERGENCY_PROTECTION_DURATION` from the `block.timestamp` at the time of method invocation.
- The `newEmergencyProtectionEndDate` MUST NOT be the same as the current value.

---

### Function: `EmergencyProtectedTimelock.setEmergencyModeDuration`

```solidity
function setEmergencyModeDuration(Duration newEmergencyModeDuration)
```

Sets the duration of the emergency mode.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newEmergencyModeDuration` MUST NOT exceed the `EmergencyProtectedTimelock.MAX_EMERGENCY_MODE_DURATION` duration.
- The `newEmergencyModeDuration` MUST NOT be the same as the current value.

---

### Function: `EmergencyProtectedTimelock.setEmergencyGovernance`

```solidity
function setEmergencyGovernance(address newEmergencyGovernance)
```

Sets the address of the emergency governance contract.

#### Preconditions

- MUST be called by the admin executor contract.
- The `newEmergencyGovernance` address MUST NOT be the same as the current value.

---

### Function: `EmergencyProtectedTimelock.activateEmergencyMode`

```solidity
function activateEmergencyMode()
```

Activates the Emergency Mode.

#### Preconditions

- MUST be called by the Emergency Activation Committee address.
- Emergency Mode MUST NOT already be active.
- Emergency Protection MUST NOT be expired.

---

### Function: `EmergencyProtectedTimelock.emergencyExecute`

```solidity
function emergencyExecute(uint256 proposalId)
```

Executes the scheduled proposal, bypassing the post-schedule delay.

#### Preconditions

- The Emergency Mode MUST be active.
- MUST be called by the Emergency Execution Committee address.

---

### Function: `EmergencyProtectedTimelock.deactivateEmergencyMode`

```solidity
function deactivateEmergencyMode()
```

Deactivates the Emergency Activation and Emergency Execution Committees (setting their addresses to zero), cancels all unexecuted proposals, and disables the [Protected deployment mode](#Proposal-execution-and-deployment-modes).

#### Preconditions

- The Emergency Mode MUST be active.
- If the Emergency Mode was activated less than the `emergency mode max duration` ago, MUST be called by the [Admin Executor](#Administrative-actions) address.

---

### Function: `EmergencyProtectedTimelock.emergencyReset`

```solidity
function emergencyReset()
```

Resets the `governance` address to the `EmergencyProtectedTimelock.getEmergencyGovernance()` value, cancels all unexecuted proposals, and disables the [Protected deployment mode](#Proposal-execution-and-deployment-modes).

#### Preconditions

- The Emergency Mode MUST be active.
- MUST be called by the Emergency Execution Committee address.
- The current `governance` address MUST NOT already equal `EmergencyProtectedTimelock.getEmergencyGovernance()`

---

### Function: `EmergencyProtectedTimelock.isEmergencyProtectionEnabled`

```solidity
function isEmergencyProtectionEnabled() view returns (bool)
```

Returns whether emergency protection is currently enabled.

---

### Function: `EmergencyProtectedTimelock.isEmergencyModeActive`

```solidity
function isEmergencyModeActive() view returns (bool)
```

Returns whether the system is currently in Emergency Mode.

---

### Function: `EmergencyProtectedTimelock.getEmergencyProtectionDetails`

```solidity
function getEmergencyProtectionDetails() view returns (EmergencyProtectionDetails memory details)
```

Returns details about the current state of emergency protection. The `EmergencyProtectionDetails` struct includes the following fields:

- `emergencyModeDuration`: The duration for which the emergency mode remains active after activation.
- `emergencyModeEndsAfter`: The timestamp indicating when the current emergency mode will end.
- `emergencyProtectionEndsAfter`: The timestamp indicating when the overall emergency protection period will expire.

---

### Function: `EmergencyProtectedTimelock.getEmergencyGovernance`

```solidity
function getEmergencyGovernance() view returns (address)
```

Returns the address of the emergency governance contract.

---

### Function: `EmergencyProtectedTimelock.getEmergencyActivationCommittee`

```solidity
function getEmergencyActivationCommittee() view returns (address)
```

Returns the address of the emergency activation committee.

---

### Function: `EmergencyProtectedTimelock.getEmergencyExecutionCommittee`

```solidity
function getEmergencyExecutionCommittee() view returns (address)
```

Returns the address of the emergency execution committee.

---

### Function: `EmergencyProtectedTimelock.getGovernance`

```solidity
function getGovernance() view returns (address)
```

Returns the address of the current governance contract.

---

### Function: `EmergencyProtectedTimelock.getAdminExecutor`

```solidity
function getAdminExecutor() view returns (address)
```

Returns the address of the admin executor contract.

---

### Function: `EmergencyProtectedTimelock.getAfterSubmitDelay`

```solidity
function getAfterSubmitDelay() view returns (Duration)
```

Returns the configured delay duration required before a submitted proposal can be scheduled.

---

### Function: `EmergencyProtectedTimelock.getAfterScheduleDelay`

```solidity
function getAfterScheduleDelay() view returns (Duration)
```

Returns the configured delay duration required before a scheduled proposal can be executed.

---

### Function: `EmergencyProtectedTimelock.getProposalDetails`

```solidity
function getProposalDetails(uint256 proposalId) view returns (ProposalDetails memory details)
```

Returns information about a proposal, excluding the external calls associated with it. The `ProposalDetails` struct includes the following fields:

- `id`: The id of the proposal.
- `status`: The current status of the proposal. Possible values are:
  - `1`: The proposal was submitted but not scheduled.
  - `2`: The proposal was submitted and scheduled but not yet executed.
  - `3`: The proposal was submitted, scheduled, and executed. This is the final state of the proposal lifecycle.
  - `4`: The proposal was cancelled via `cancelAllNonExecutedProposals` and cannot be scheduled or executed anymore. This is the final state of the proposal lifecycle.
- `executor`: The address of the executor responsible for executing the proposal's external calls.
- `submittedAt`: The timestamp when the proposal was submitted.
- `scheduledAt`: The timestamp when the proposal was scheduled for execution. This value is `0` if the proposal was submitted but not yet scheduled.

#### Preconditions

- The proposal with the `proposalId` MUST have been previously submitted into the `EmergencyProtectedTimelock` instance.

---

### Function: `EmergencyProtectedTimelock.getProposalCalls`

```solidity
function getProposalCalls(uint256 proposalId) view returns (ExternalCall[] memory calls)
```

Returns the EVM calls associated with the specified proposal. See the [Struct: ExternalCall](#Struct-ExternalCall) for details on the structure of each call.

#### Preconditions

- The proposal with the `proposalId` MUST have been previously submitted into the `EmergencyProtectedTimelock` instance.

---

### Function: `EmergencyProtectedTimelock.getProposal`

```solidity
function getProposal(uint256 proposalId) view returns
  (ProposalDetails memory proposalDetails, ExternalCall[] memory calls)
```

Retrieves the details of a proposal, including the associated calls to be executed, identified by the proposal's id.

#### Returns

- `proposalDetails`: A `ProposalDetails` struct containing metadata and state information about the proposal.
- `calls`: An array of `ExternalCall` structs representing the EVM calls associated with the proposal.

#### Preconditions

- The proposal with the `proposalId` MUST have been previously submitted into the `EmergencyProtectedTimelock` instance.

---

### Function: `EmergencyProtectedTimelock.getProposalsCount`

```solidity
function getProposalsCount() view returns (uint256 count)
```

Returns the total number of proposals submitted to the system.

---

### Function: `EmergencyProtectedTimelock.canExecute`

```solidity
function canExecute(uint256 proposalId) view returns (bool)
```

Checks whether the specified proposal can be executed.

---

### Function: `EmergencyProtectedTimelock.canSchedule`

```solidity
function canSchedule(uint256 proposalId) view returns (bool)
```

Checks whether the specified proposal can be scheduled.

---

### Function: `EmergencyProtectedTimelock.setAdminExecutor`

```solidity
function setAdminExecutor(address newAdminExecutor)
```

Sets a new address for the admin executor contract.

#### Preconditions

- MUST be called by the current admin executor contract.
- The `newAdminExecutor` address MUST NOT be the zero address.
- The `newAdminExecutor` address MUST NOT be the same as the current value.

> [!CAUTION]
> There is a risk of misconfiguration if the new executor address is not assigned to a proposer within Dual Governance. To eliminate this risk, any proposal updating the admin executor MUST include a validation check as the final action, ensuring that the new admin executor is properly assigned as a Dual Governance proposer.

---

## Contract: `ImmutableDualGovernanceConfigProvider`

`ImmutableDualGovernanceConfigProvider` is a smart contract that stores all the constants used in the Dual Governance system and provides an interface for accessing them. It implements the `IDualGovernanceConfigProvider` interface.

During deployment, the contract validates that the provided values satisfy the following conditions:
  - `firstSealRageQuitSupport` MUST be less than `secondSealRageQuitSupport`.
  - `secondSealRageQuitSupport` MUST be less than or equal to 100%, represented as a percentage with 16 decimal places of precision.
  - `vetoSignallingMinDuration` MUST be less than `vetoSignallingMaxDuration`.
  - `rageQuitEthWithdrawalsMinDelay` MUST be less than or equal to `rageQuitEthWithdrawalsMaxDelay`.
  - `minAssetsLockDuration` MUST NOT be zero.
  - `minAssetsLockDuration` MUST NOT exceed `Escrow.MAX_MIN_ASSETS_LOCK_DURATION`.

---

### Function: `ImmutableDualGovernanceConfigProvider.getDualGovernanceConfig`

```solidity
function getDualGovernanceConfig() view returns (DualGovernanceConfig.Context memory config)
```

Provides the configuration settings required for the proper functioning of the `DualGovernance` contract. These settings ensure that the system has access to the necessary context and parameters for managing state transitions. The `DualGovernanceConfig.Context` includes the following fields:

- `firstSealRageQuitSupport`: The percentage of the total stETH supply that must be reached in the Signalling Escrow to transition Dual Governance from the `Normal` state to the `VetoSignalling` state.
- `secondSealRageQuitSupport`: The percentage of the total stETH supply that must be reached in the Signalling Escrow to transition Dual Governance into the `RageQuit` state.
- `minAssetsLockDuration`: The minimum duration that assets must remain locked in the Signalling Escrow before unlocking is permitted.
- `vetoSignallingMinDuration`: The minimum duration of the `VetoSignalling` state.
- `vetoSignallingMaxDuration`: The maximum duration of the `VetoSignalling` state.
- `vetoSignallingMinActiveDuration`: The minimum duration of the `VetoSignalling` state before it can be exited. Once in the `VetoSignalling` state, it cannot be exited sooner than this duration.
- `vetoSignallingDeactivationMaxDuration`: The maximum duration of the `VetoSignallingDeactivation` state.
- `vetoCooldownDuration`: The duration of the `VetoCooldown` state.
- `rageQuitExtensionPeriodDuration`: The duration of the Rage Quit Extension Period.
- `rageQuitEthWithdrawalsMinDelay`: The minimum delay for ETH withdrawals after the Rage Quit process completes.
- `rageQuitEthWithdrawalsMaxDelay`: The maximum delay for ETH withdrawals after the Rage Quit process completes.
- `rageQuitEthWithdrawalsDelayGrowth`: The incremental growth of the ETH withdrawal delay with each "continuous" Rage Quit. A Rage Quit is considered continuous if Dual Governance has not re-entered the `Normal` state between two Rage Quits.

---

## Contract: `ProposalsList`

`ProposalsList` implements storage for list of `Proposal`s with public interface to access.

---

### Function: `ProposalsList.getProposals`

```solidity
function getProposals(uint256 offset, uint256 limit) view returns (Proposal[] memory proposals)
```

Returns a list of `Proposal` objects starting from the specified `offset`, with the number of proposals limited by the `limit` parameter.

#### Preconditions

- `offset` MUST be less than the total number of proposals.

---

### Function: `ProposalsList.getProposalAt`

```solidity
function getProposalAt(uint256 index) view returns (Proposal memory)
```

Returns the `Proposal` located at the specified `index` in the proposals list.

#### Preconditions

- `index` MUST be less than total number of proposals.

---

### Function: `ProposalsList.getProposal`

```solidity
function getProposal(bytes32 key) view returns (Proposal memory)
```

Returns the `Proposal` identified by its unique `key`.

#### Preconditions

- A proposal with the given `key` MUST have been previously registered.

---

### Function: `ProposalsList.getProposalsLength`

```solidity
function getProposalsLength() view returns (uint256)
```

Returns the total number of `Proposal` objects created.

---

### Function: `ProposalsList.getOrderedKeys`

```solidity
function getOrderedKeys(uint256 offset, uint256 limit) view returns (bytes32[] memory)
```

Returns an ordered list of `Proposal` keys with the given `offset` and `limit` for pagination.

#### Preconditions

- `offset` MUST be less than the total number of proposals.

---

## Contract: `HashConsensus`

`HashConsensus` is an abstract contract that allows for consensus-based decision-making among a set of members. The consensus is achieved by members voting on a specific hash, and decisions can only be executed if a quorum is reached and a timelock period has elapsed.

This contract extends OpenZeppelin’s `Ownable` contract.

---

### Function: `HashConsensus.addMembers`

```solidity
function addMembers(address[] memory newMembers, uint256 executionQuorum)
```

Adds new members and updates the quorum.

#### Preconditions

- MUST be called by the contract owner.
- All `newMembers` MUST NOT already be part of the committee.
- `newMembers` MUST NOT contain zero addresses.
- `newQuorum` MUST be greater than 0 and less than or equal to the number of members.

---

### Function: `HashConsensus.removeMembers`

```solidity
function removeMembers(address[] memory membersToRemove, uint256 executionQuorum)
```

Removes members and updates the quorum.

#### Preconditions

- MUST be called by the contract owner.
- All `membersToRemove` MUST be members of the committee.
- `newQuorum` MUST be greater than 0 and less than or equal to the number of remaining members.

---
`
### Function: `HashConsensus.getMembers`

```solidity
function getMembers() view returns (address[] memory)
```

Returns the list of current members.

---

### Function: `HashConsensus.isMember`

```solidity
function isMember(address member) view returns (bool)
```

Returns if an address is a member.

---

### Function `HashConsensus.getTimelockDuration`

```solidity
function getTimelockDuration() view returns (Duration)
```

Returns the timelock duration that must elapse after a hash is scheduled and before it can be marked as used.

---

### Function: `HashConsensus.setTimelockDuration`

```solidity
function setTimelockDuration(uint256 newTimelock)
```

Sets the timelock duration.

#### Preconditions

- MUST be called by the contract owner.
- The new `timelock` value MUST not be equal to the current one.


---

### Function: `HashConsensus.getQuorum`

```solidity
function getQuorum() view returns (uint256) 
```

Returns the current quorum value required to schedule a proposal for execution.

---

### Function: `HashConsensus.setQuorum`

```solidity
function setQuorum(uint256 newQuorum)
```

Sets the quorum required for decision execution.

#### Preconditions

- MUST be called by the contract owner.
- `newQuorum` MUST be greater than 0, less than or equal to the number of members, and not equal to the current `quorum` value.

---

### Function: `HashConsensus.schedule`

```solidity
function schedule(bytes32 hash)
```

Schedules a proposal for execution if quorum is reached and it has not yet been scheduled.

#### Preconditions
- Proposal with given `hash` MUST NOT have been scheduled before.
- The current execution quorum MUST be greater than zero.
- The current support for the proposal MUST be greater than or equal to the execution quorum.

---


## Contract: `TiebreakerCoreCommittee`

`TiebreakerCoreCommittee` is a smart contract that extends the `HashConsensus` and `ProposalsList` contracts to manage the scheduling of proposals and the resuming of sealable contracts through a consensus-based mechanism. It interacts with a DualGovernance contract to execute decisions once consensus is reached.

---

### Function: `TiebreakerCoreCommittee.scheduleProposal`

```solidity
function scheduleProposal(uint256 proposalId)
```

Allows committee members to vote on scheduling a proposal, previously submitted to the `EmergencyProtectedTimelock`, for execution.

#### Preconditions

- MUST be called by a committee member.
- Proposal with the given `proposalId` MUST have been submitted to the `EmergencyProtectedTimelock`.
- The quorum required to schedule the proposal for execution in the `EmergencyProtectedTimelock` MUST NOT have been reached previously

---

### Function: `TiebreakerCoreCommittee.getScheduleProposalState`

```solidity
function getScheduleProposalState(uint256 proposalId)
    view
    returns (uint256 support, uint256 executionQuorum, bool isExecuted)
```

Returns the state of the scheduling request for the `EmergencyProtectedTimelock` proposal with the given `proposalId`. The returned tuple contains:

- `support` - The number of votes in support of scheduling the proposal.
- `executionQuorum` - The number of votes required to reach the execution quorum.
- `quorumAt` - The timestamp when the quorum was reached.
- `isExecuted` - Whether the proposal has already been scheduled for execution.

---

### Function: `TiebreakerCoreCommittee.executeScheduleProposal`

```solidity
function executeScheduleProposal(uint256 proposalId)
```

Calls `DualGovernance.tiebreakerScheduleProposal` to schedule the proposal for execution in the `EmergencyProtectedTimelock`, once the required quorum of committee members has been reached and the timelock duration since reaching quorum has elapsed.

#### Preconditions

- The quorum required to schedule the proposal for execution in the `EmergencyProtectedTimelock` MUST have been reached.
- The `executeScheduleProposal` function MUST NOT have been called for the given `proposalId` previously.
- The required timelock duration since the quorum was reached MUST have elapsed.
- The preconditions of `DualGovernance.tiebreakerScheduleProposal` MUST be satisfied.

---

### Function: `TiebreakerCoreCommittee.checkProposalExists`

```solidity
function checkProposalExists(uint256 proposalId) public view
```

Checks whether the specified proposal exists in the `EmergencyProtectedTimelock` and reverts if not.

---

### Function: `TiebreakerCoreCommittee.getSealableResumeNonce`

```solidity
function getSealableResumeNonce(address sealable) view returns (uint256)
```

Returns the current nonce for resuming operations of a sealable contract.

---

### Function: `TiebreakerCoreCommittee.sealableResume`

```solidity
function sealableResume(address sealable, uint256 nonce)
```

Allows committee members to vote on resuming operations of a paused `sealable` contract.

#### Preconditions

- MUST be called by a committee member.
- The `sealable` address MUST be in `Paused` state.
- The provided nonce MUST match the current nonce of the `sealable` contract.
- The quorum required to resume operations of the `sealable` contract for the given `nonce` MUST NOT have been reached previously.

---

### Function: `TiebreakerCoreCommittee.getSealableResumeState`

```solidity
function getSealableResumeState(address sealable, uint256 nonce)
    view
    returns (uint256 support, uint256 executionQuorum, bool isExecuted)
```
Returns the current state of the sealable resume request. The returned tuple includes:

- `support` - The number of votes in support of resuming the sealable contract.
- `executionQuorum` - The number of votes required to reach the execution quorum.
- `quorumAt` - The timestamp when the quorum was reached.
- `isExecuted` - Whether the request to resume the sealable contract has already been executed.

---

### Function: `TiebreakerCoreCommittee.executeSealableResume`

```solidity
function executeSealableResume(address sealable)
```

Calls `DualGovernance.tiebreakerResumeSealable` to resume a paused `sealable` contract once the required quorum of committee members has been reached and the timelock duration since reaching quorum has elapsed. Increments the resume nonce for the given sealable upon successful execution.

#### Preconditions

- The quorum required to resume operations of the sealable contract MUST have been reached.
- The `executeSealableResume` function MUST NOT have been called before for the given `sealable` and the current `TiebreakerCoreCommittee.getSealableResumeNonce()`.
- The required timelock duration since the quorum was reached MUST have elapsed.
- The preconditions of `DualGovernance.executeSealableResume` MUST be satisfied.

---

### Function: `TiebreakerCoreCommittee.checkSealableIsPaused`

```solidity
function checkSealableIsPaused(address sealable) public view
```

Checks if the specified sealable address is not a zero address and that it is paused, otherwise reverts.
---

## Contract: `TiebreakerSubCommittee`

`TiebreakerSubCommittee` is a smart contract that extends the functionalities of `HashConsensus` and `ProposalsList` to manage the scheduling of proposals and the resumption of sealable contracts through a consensus mechanism. It interacts with the `TiebreakerCoreCommittee` contract to execute decisions once consensus is reached.

---

### Function: `TiebreakerSubCommittee.scheduleProposal`

```solidity
function scheduleProposal(uint256 proposalId)
```

Allows committee members to vote on scheduling a proposal (previously submitted to the `EmergencyProtectedTimelock`) for execution, by triggering a call to `TiebreakerCoreCommittee.scheduleProposal` once quorum is reached.

#### Preconditions

- MUST be called by a committee member.
- Proposal with the given `proposalId` MUST have been submitted to the `EmergencyProtectedTimelock`.
- The quorum required to vote on scheduling the proposal for execution in the `EmergencyProtectedTimelock` MUST NOT have been reached previously.

---

### Function: `TiebreakerSubCommittee.getScheduleProposalState`

```solidity
function getScheduleProposalState(uint256 proposalId)
    view
    returns (uint256 support, uint256 executionQuorum, bool isExecuted)
```

Returns the state of the request to call `TiebreakerCoreCommittee.scheduleProposal` for scheduling the `EmergencyProtectedTimelock` proposal with the given `proposalId`. The returned tuple contains:

- `support` - The number of votes in support of scheduling the proposal.
- `executionQuorum` - The number of votes required to reach the execution quorum.
- `quorumAt` - The timestamp when the quorum was reached.
- `isExecuted` - Whether the proposal has already been submitted to the `TiebreakerCoreCommittee`.

---

### Function: `TiebreakerSubCommittee.executeScheduleProposal`

```solidity
function executeScheduleProposal(uint256 proposalId)
```

Calls `TiebreakerCoreCommittee.scheduleProposal` to vote on scheduling the proposal for execution in the `EmergencyProtectedTimelock`, once the required quorum of subcommittee members has been reached and the required timelock period has elapsed.

#### Preconditions

- The quorum required to call `TiebreakerCoreCommittee.scheduleProposal` for the given `proposalId` MUST have been reached.
- This function MUST NOT have been executed previously for the given `proposalId`.
- The required timelock duration since the quorum was reached MUST have elapsed.
- The preconditions of `TiebreakerCoreCommittee.scheduleProposal` MUST be satisfied.

---

### Function: `TiebreakerSubCommittee.sealableResume`

```solidity
function sealableResume(address sealable)
```

Allows committee members to vote on calling `TiebreakerCoreCommittee.sealableResume` to request the resumption of a paused `sealable` contract.

#### Preconditions

- MUST be called by a committee member.
- The `sealable` contract MUST be in the `Paused` state.
- The quorum required to call `TiebreakerCoreCommittee.sealableResume` for the given sealable and the current value of `TiebreakerCoreCommittee.getSealableResumeNonce(sealable)` MUST NOT have been reached previously.

---

### Function: `TiebreakerSubCommittee.getSealableResumeState`

```solidity
function getSealableResumeState(address sealable)
    view
    returns (uint256 support, uint256 executionQuorum, bool isExecuted)
```

Returns the state of the request to call `TiebreakerCoreCommittee.sealableResume` for the specified `sealable` contract. The returned tuple contains:

- `support` - Number of votes in support of calling the `TiebreakerCoreCommittee.sealableResume` method.
- `executionQuorum` - Number of votes required to reach quorum.
- `quorumAt` - Timestamp when quorum was reached.
- `isExecuted` - Whether the call to `TiebreakerCoreCommittee.sealableResume` for the given `sealable` and the current value of `TiebreakerCoreCommittee.getSealableResumeNonce(sealable)` has already been made.

---

### Function: `TiebreakerSubCommittee.executeSealableResume`

```solidity
function executeSealableResume(address sealable) external
```

Calls `TiebreakerCoreCommittee.sealableResume` to submit a resume request for the specified sealable contract, once the required quorum of subcommittee members has been reached and the timelock duration has elapsed.

#### Preconditions

- The quorum required to call `TiebreakerCoreCommittee.sealableResume` for the given sealable and the current value of `TiebreakerCoreCommittee.getSealableResumeNonce(sealable)` MUST have been reached.
- This function MUST NOT have been called previously for the given sealable and the current value of `TiebreakerCoreCommittee.getSealableResumeNonce(sealable)`.
- The required timelock duration since quorum was reached MUST have elapsed.
- The preconditions of `TiebreakerCoreCommittee.sealableResume` MUST be satisfied.

---

## Upgrade flow description

In designing the dual governance system, ensuring seamless updates while maintaining the contracts' immutability was a primary consideration. To achieve this, the system was divided into three key components: `DualGovernance`, `EmergencyProtectedTimelock`, and `Executor`.

When updates are necessary only for the `DualGovernance` contract logic, the `EmergencyProtectedTimelock` and `Executor` components remain unchanged. This simplifies the process, as it only requires deploying a new version of the `DualGovernance`. This approach preserves proposal history and avoids the complexities of redeploying executors or transferring rights from previous instances.

During the deployment of a new dual governance version, the Lido DAO will likely launch it under the protection of the emergency committee, similar to the initial launch (see [Proposal execution and deployment modes](#Proposal-execution-and-deployment-modes) for the details). The `EmergencyProtectedTimelock` allows for the reassembly and reactivation of emergency protection at any time, even if the previous committee's duration has not yet concluded.

A typical proposal to update the dual governance system to a new version will likely contain the following steps:

1. Set the `governance` variable in the `EmergencyProtectedTimelock` instance to the new version of the `DualGovernance` contract.
2. Deploy a new instance of the `ImmutableDualGovernanceConfigProvider` contract if necessary.
3. Configure emergency protection settings in the `EmergencyProtectedTimelock` contract, including the address of the committee, the duration of emergency protection, and the duration of the emergency mode.

For more significant updates involving changes to the `EmergencyProtectedTimelock` or `Proposals` mechanics, new versions of both the `DualGovernance` and `EmergencyProtectedTimelock` contracts are deployed. While this adds more steps to maintain the proposal history, such as tracking old and new versions of the Timelocks, it also eliminates the need to migrate permissions or rights from executors. The `transferExecutorOwnership` function of the `EmergencyProtectedTimelock` facilitates the assignment of executors to the newly deployed contract.
