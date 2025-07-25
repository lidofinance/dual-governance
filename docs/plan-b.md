# Timelocked Governance specification

Timelocked Governance (TG) is a governance subsystem positioned between the Lido DAO, represented by the admin voting system (defaulting to Aragon's Voting), and the protocol contracts it manages. The TG subsystem helps protect users from malicious DAO proposals by allowing the **Emergency Activation Committee** to activate a long-lasting timelock on these proposals.

> Motivation: the upcoming Ethereum upgrade *Pectra* will introduce a new [withdrawal mechanism](https://eips.ethereum.org/EIPS/eip-7002) (EIP-7002), significantly affecting the operation of the Lido protocol. This enhancement will allow withdrawal queue contract to trigger withdrawals, introducing a new attack vector for the whole protocol. This poses a threat to stETH users, as governance capture (or malicious actions) could enable an upgrade to the withdrawal queue contract, resulting in the theft of user funds. Timelocked Governance in its turn provides security assurances through the implementation of guardians (emergency committees) that can halt malicious proposals and the implementation of the timelock to ensure users and committees have sufficient time to react to potential threats.


## Navigation

- [System overview](#system-overview)
- [Proposal flow](#proposal-flow)
- [Proposal execution](#proposal-execution)
- [Common types](#common-types)
- Contracts:
    - [Contract: `TimelockedGovernance`](#Contract-TimelockedGovernance)
    - [Contract: `EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock)
    - [Contract: `Executor`](#Contract-Executor)


## System Overview

<img width="1289" alt="image" src="https://github.com/lidofinance/dual-governance/assets/14151334/905bac24-dfb2-4eca-a113-1b82ead93752"/>

The system comprises the following primary contracts:
- [`TimelockedGovernance`](#Contract-TimelockedGovernance): A singleton contract that serves as the interface for submitting and scheduling the execution of governance proposals.
- [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock): A singleton contract that stores submitted proposals and provides an execution interface. In addition, it implements an optional protection from a malicious proposals submitted by the DAO. The protection is implemented as a timelock on proposal execution combined with two emergency committees that have the right to cooperate and suspend the execution of the proposals.
- [`Executor`](#Contract-Executor): A contract instance responsible for executing calls resulting from governance proposals. All protocol permissions or roles protected by TG, as well as the authority to manage these roles/permissions, should be controlled exclusively by instance of this contract, rather than being assigned directly to the DAO voting system.


## Proposal flow

<img width="567" alt="image" src="https://github.com/lidofinance/dual-governance/assets/14151334/f6f2efc1-7bd7-4e03-9c8b-6cd12cdfede8"/>

The general proposal flow is as follows:
1. **Proposal Submission**: The Lido DAO submits a proposal via the admin voting system. This involves a set of external calls (represented by an array of [`ExternalCall`](#Struct-ExternalCall) structs) to be executed by the **admin executor**, by calling the [`TimelockedGovernance.submitProposal`](#Function-TimelockedGovernancesubmitProposal) function.
2. **After Submit Delay**: This initiates a preconfigured `AfterSubmitDelay` timelock period. Depending on the configuration, this period may be set to 0. If set to 0, the submitted proposal can be scheduled for execution immediately by anyone using the [`TimelockGovernance.scheduleProposal`](#Function-TimelockedGovernancescheduleProposal) method.
3. **Optional Proposal Cancellation**: At any moment before the proposal is executed, the Lido DAO may cancel all pending proposals using the [`TimelockedGovernance.cancelAllPendingProposals`](#function-TimelockedGovernancecancelAllPendingProposals) method.
4. **Proposal Execution**: After the configured timelock has passed, the proposal may be executed, resulting in the proposal's calls being issued by the admin executor contract.


## Proposal execution

<img width="764" alt="image" src="https://github.com/lidofinance/dual-governance/assets/14151334/6e72b3a7-61fd-47f7-905e-9f5604aa9c2e"/>

The proposal execution flow begins after the proposal is scheduled for execution and the `AfterScheduleDelay` has passed.

If emergency protection is enabled on the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) instance, an **emergency activation committee** has a one-off, time-limited right to activate an adversarial **emergency mode** if they detect a malicious proposal submitted by the Lido DAO.

- Once the emergency mode is activated, the emergency activation committee is disabled, meaning it loses the ability to activate the emergency mode again. If the emergency activation committee doesn't activate the emergency mode within the **emergency protection duration** since the committee was configured, it gets automatically disabled as well.
- The emergency mode lasts up to the **emergency mode max duration** from the moment of its activation. While it's active, only the **emergency execution committee** has the right to execute scheduled proposals. This committee also has a one-off right to **disable the emergency mode**.
- If the emergency execution committee doesn't disable the emergency mode before the emergency mode max duration elapses, anyone can deactivate the emergency mode, allowing proposals to proceed and disabling the emergency committee. Once the emergency mode is disabled, all pending proposals will be marked as cancelled and cannot be executed.

## Common types

### Struct: `ExternalCall`

```solidity
struct ExternalCall {
    address target;
    uint96 value;
    bytes payload;
}
```

Encodes an external call from an executor contract to the `target` address with the specified `value` and the calldata being set to `payload`.

---

## Contract: `TimelockedGovernance`

The main entry point to the timelocked governance system, which provides an interface for submitting and canceling governance proposals in the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) contract. This contract is a singleton, meaning that any TG deployment includes exactly one instance of this contract.

---

### Function: `TimelockedGovernance.submitProposal`

```solidity
function submitProposal(ExecutorCall[] calls, string metadata)
  returns (uint256 proposalId)
```

Instructs the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) singleton instance to register a new governance proposal composed of one or more external `calls`, along with the attached metadata text, to be made by an admin executor contract. Initiates a timelock on scheduling the proposal for execution.

See: [`EmergencyProtectedTimelock.submit`](#Function-EmergencyProtectedTimelockSubmit)

#### Returns

The id of the successfully registered proposal.

#### Preconditions

- The `msg.sender` MUST be the address of the admin voting system

---

### Function: `TimelockedGovernance.scheduleProposal`

```solidity
function scheduleProposal(uint256 proposalId)
```

Instructs the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) singleton instance to schedule the proposal with id `proposalId` for execution.

See: [`EmergencyProtectedTimelock.schedule`](#Function-EmergencyProtectedTimelockSchedule)

#### Preconditions

- The proposal with the given id MUST be in the `Submitted` state.

---

### Function: `TimelockedGovernance.executeProposal`

```solidity
function executeProposal(uint256 proposalId)
```

Instructs the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) singleton instance to execute the proposal with id `proposalId`.

See: [`EmergencyProtectedTimelock.execute`](#Function-EmergencyProtectedTimelockExecute)

#### Preconditions

- The proposal with the given id MUST be in the `Scheduled` state.

---

### Function: `TimelockedGovernance.cancelAllPendingProposals`

```solidity
function cancelAllPendingProposals() returns (bool)
```

Cancels all currently submitted and non-executed proposals. If a proposal was submitted but not scheduled, it becomes unschedulable. If a proposal was scheduled, it becomes unexecutable.

The function will return `true` if all proposals are successfully cancelled. If the subsequent call to the [`EmergencyProtectedTimelock.cancelAllNonExecutedProposals`](#Function-EmergencyProtectedTimelockcancelAllNonExecutedProposals) method fails, the function will revert with an error.

#### Preconditions

- MUST be called by an admin voting system

---

## Contract: `EmergencyProtectedTimelock`

`EmergencyProtectedTimelock` is a singleton instance that stores and manages the lifecycle of proposals submitted by the DAO via the `TimelockedGovernance` contract. It can be configured with time-bound **Emergency Activation Committee** and **Emergency Execution Committee**, which act as safeguards against the execution of malicious proposals.

For a proposal to be executed, the following steps have to be performed in order:
1. The proposal must be submitted using the `EmergencyProtectedTimelock.submit` function.
2. The configured post-submit timelock (`EmergencyProtectedTimelock.getAfterSubmitDelay`) must elapse.
3. The proposal must be scheduled using the `EmergencyProtectedTimelock.schedule` function.
4. The configured emergency protection delay (`Configuration.getAfterScheduleDelay`) must elapse (can be zero, see below).
5. The proposal must be executed using the `EmergencyProtectedTimelock.execute` function.

The contract only allows proposal submission and scheduling by the `governance` address. Normally, this address points to the [`TimelockedGovernance`](#Contract-TimelockedGovernance) singleton instance. Proposal execution is permissionless, unless Emergency Mode is activated.

If the Emergency Committees are set up and active, the governance proposal undergoes a separate emergency protection delay between submission and scheduling. This additional timelock is implemented to protect against the execution of malicious proposals submitted by the DAO. If the Emergency Committees aren't set, the proposal flow remains the same, but the timelock duration is zero.

While active, the Emergency Activation Committee can enable Emergency Mode. This mode prohibits anyone but the Emergency Execution Committee from executing proposals. Once the **Emergency Duration** has ended, the Emergency Execution Committee or anyone else may disable the emergency mode, canceling all pending proposals. After the emergency mode is deactivated or the Emergency Period has elapsed, the Emergency Committees lose their power.

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

## Contract: `Executor`

Handles calls resulting from governance proposals' execution. Every protocol permission or role protected by the TG, as well as the permission to manage these roles or permissions, must be controlled exclusively by instances of this contract.

The timelocked governance setup is designed to use a single admin instance of the `Executor`, which is owned by the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelock) singleton instance.

This contract extends OpenZeppelin’s `Ownable` contract.

---

### Function: `Executor.execute`

```solidity
function execute(address target, uint256 value, bytes payload) payable
```

Performs an EVM call to the `target` address with the specified `payload` calldata, optionally transferring `value` wei in ETH.

Reverts if the call fails.

---