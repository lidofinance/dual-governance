# Timelocked Governance specification

Timelocked Governance (TG) is a governance subsystem positioned between the Lido DAO, represented by the admin voting system (defaulting to Aragon's Voting), and the protocol contracts it manages. The TG subsystem helps protect users from malicious DAO proposals by allowing the **Emergency Activation Committee** to activate a long-lasting timelock on these proposals.

> Motivation: the upcoming Ethereum upgrade *Pectra* will introduce a new [withdrawal mechanism](https://eips.ethereum.org/EIPS/eip-7002) (EIP-7002), significantly affecting the operation of the Lido protocol. This enhancement will allow withdrawal queue contract to trigger withdrawals, introducing a new attack vector for the whole protocol. This poses a threat to stETH users, as governance capture (or malicious actions) could enable an upgrade to the withdrawal queue contract, resulting in the theft of user funds. Timelocked Governance in its turn provides security assurances through the implementation of guardians (emergency committees) that can halt malicious proposals and the implementation of the timelock to ensure users and committees have sufficient time to react to potential threats.

## Navigation
* [System overview](#system-overview)
* [Proposal flow](#proposal-flow)
* [Proposal execution](#proposal-execution)
* [Common types](#common-types)
* Core Contracts:
    * [Contract: `TimelockedGovernance`](#contract-timelockedgovernance)
    * [Contract: `EmergencyProtectedTimelock`](#contract-emergencyprotectedtimelock)
    * [Contract: `Executor`](#contract-executor)
* Committees:
    * [Contract: `ProposalsList`](#contract-proposalslist)
    * [Contract: `HashConsensus`](#contract-hashconsensus)
    * [Contract: `EmergencyActivationCommittee`](#contract-emergencyactivationcommittee)
    * [Contract: `EmergencyExecutionCommittee`](#contract-emergencyexecutioncommittee)

## System Overview

<img width="1289" alt="image" src="https://github.com/lidofinance/dual-governance/assets/14151334/905bac24-dfb2-4eca-a113-1b82ead93752"/>

The system comprises the following primary contracts:
- [**`TimelockedGovernance.sol`**](#contract-timelockedgovernance): A singleton contract that serves as the interface for submitting and scheduling the execution of governance proposals.
- [**`EmergencyProtectedTimelock.sol`**](#contract-emergencyprotectedtimelock): A singleton contract that stores submitted proposals and provides an execution interface. In addition, it implements an optional protection from a malicious proposals submitted by the DAO. The protection is implemented as a timelock on proposal execution combined with two emergency committees that have the right to cooperate and suspend the execution of the proposals.
- [**`Executor.sol`**](#contract-executor): A contract instance responsible for executing calls resulting from governance proposals. All protocol permissions or roles protected by TG, as well as the authority to manage these roles/permissions, should be assigned exclusively to instance of this contract, rather than being assigned directly to the DAO voting system.

Additionally, the system uses several committee contracts that allow members to execute, acquiring quorum, a narrow set of actions:

- [**`EmergencyActivationCommittee`**](#contract-emergencyactivationcommittee): A contract with the authority to activate Emergency Mode. Activation requires a quorum from committee members.
- [**`EmergencyExecutionCommittee`**](#contract-emergencyexecutioncommittee): A contract that enables the execution of proposals during Emergency Mode by obtaining a quorum of committee members.

## Proposal flow
<img width="567" alt="image" src="https://github.com/lidofinance/dual-governance/assets/14151334/f6f2efc1-7bd7-4e03-9c8b-6cd12cdfede8"/>

The general proposal flow is as follows:
1. **Proposal Submission**: The Lido DAO submits a proposal via the admin voting system. This involves a set of external calls (represented by an array of [`ExecutorCall`] structs) to be executed by the [Admin Executor], by calling the [`TimelockedGovernance.submitProposal()`] function.
2. **After Submit Delay**: This initiates a preconfigured `AfterSubmitDelay` timelock period. Depending on the configuration, this period may be set to 0. If set to 0, the submitted proposal can be scheduled for execution immediately by anyone using the `TimelockGovernance.scheduleProposal()` method.
3. **Optional Proposal Cancellation**: At any moment before the proposal is executed, the Lido DAO may cancel all pending proposals using the `TimelockedGovernance.cancelAllPendingProposals` method.
4. **Proposal Execution**: After the configured timelock has passed, the proposal may be executed, resulting in the proposal's calls being issued by the admin executor contract.

## Proposal execution
<img width="764" alt="image" src="https://github.com/lidofinance/dual-governance/assets/14151334/6e72b3a7-61fd-47f7-905e-9f5604aa9c2e"/>

The proposal execution flow begins after the proposal is scheduled for execution and the `AfterScheduleDelay` has passed.

If emergency protection is enabled on the `EmergencyProtectedTimelock` instance, an **emergency activation committee** has a one-off, time-limited right to activate an adversarial **emergency mode** if they detect a malicious proposal submitted by the Lido DAO.

- Once the emergency mode is activated, the emergency activation committee is disabled, meaning it loses the ability to activate the emergency mode again. If the emergency activation committee doesn't activate the emergency mode within the **emergency protection duration** since the committee was configured, it gets automatically disabled as well.
- The emergency mode lasts up to the **emergency mode max duration** from the moment of its activation. While it's active, only the **emergency execution committee** has the right to execute scheduled proposals. This committee also has a one-off right to **disable the emergency mode**.
- If the emergency execution committee doesn't disable the emergency mode before the emergency mode max duration elapses, anyone can deactivate the emergency mode, allowing proposals to proceed and disabling the emergency committee. Once the emergency mode is disabled, all pending proposals will be marked as cancelled and cannot be executed.

## Common types

### Struct: ExternalCall

```solidity
struct ExternalCall {
    address target;
    uint96 value;
    bytes payload;
}
```

Encodes an external call from an executor contract to the `target` address with the specified `value` and the calldata being set to `payload`.

## Contract: `TimelockedGovernance`

The main entry point to the timelocked governance system, which provides an interface for submitting and canceling governance proposals in the `EmergencyProtectedTimelock` contract. This contract is a singleton, meaning that any TG deployment includes exactly one instance of this contract.

### Function: `TimelockedGovernance.submitProposal`
```solidity
function submitProposal(ExecutorCall[] calls, string metadata)
  returns (uint256 proposalId)
```

Instructs the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelocksol) singleton instance to register a new governance proposal composed of one or more external `calls`, along with the attached metadata text, to be made by an admin executor contract. Initiates a timelock on scheduling the proposal for execution.

See: [`EmergencyProtectedTimelock.submit`](#)
#### Returns
The id of the successfully registered proposal.
#### Preconditions
* The `msg.sender` MUST be the address of the admin voting system

### Function: `TimelockedGovernance.scheduleProposal`
```solidity
function scheduleProposal(uint256 proposalId) external
```
Instructs the [`EmergencyProtectedTimelock`](#) singleton instance to schedule the proposal with id `proposalId` for execution.

See: [`EmergencyProtectedTimelock.schedule`](#)
#### Preconditions
- The proposal with the given id MUST be in the `Submitted` state.

### Function: `TimelockedGovernance.executeProposal`
```solidity
function executeProposal(uint256 proposalId) external
```
Instructs the [`EmergencyProtectedTimelock`](#) singleton instance to execute the proposal with id `proposalId`.

See: [`EmergencyProtectedTimelock.execute`](#)
#### Preconditions
- The proposal with the given id MUST be in the `Scheduled` state.

### Function: `TimelockedGovernance.cancelAllPendingProposals`

```solidity
function cancelAllPendingProposals() returns (bool)
```

Cancels all currently submitted and non-executed proposals. If a proposal was submitted but not scheduled, it becomes unschedulable. If a proposal was scheduled, it becomes unexecutable.

The function will return `true` if all proposals are successfully canceled. If the subsequent call to the `EmergencyProtectedTimelock.cancelAllNonExecutedProposals()` method fails, the function will revert with an error.

See: [`EmergencyProtectedTimelock.cancelAllNonExecutedProposals`](#)
#### Preconditions
* MUST be called by an [admin voting system](#)

## Contract: `EmergencyProtectedTimelock`
`EmergencyProtectedTimelock` is a singleton instance that stores and manages the lifecycle of proposals submitted by the DAO via the `TimelockedGovernance` contract. It can be configured with time-bound **Emergency Activation Committee** and **Emergency Execution Committee**, which act as safeguards against the execution of malicious proposals.

For a proposal to be executed, the following steps have to be performed in order:
1. The proposal must be submitted using the `EmergencyProtectedTimelock.submit()` function.
2. The configured post-submit timelock (`EmergencyProtectedTimelock.getAfterSubmitDelay()`) must elapse.
3. The proposal must be scheduled using the `EmergencyProtectedTimelock.schedule()` function.
4. The configured emergency protection delay (`Configuration.getAfterScheduleDelay()`) must elapse (can be zero, see below).
5. The proposal must be executed using the `EmergencyProtectedTimelock.execute()` function.

The contract only allows proposal submission and scheduling by the `governance` address. Normally, this address points to the [`TimelockedGovernance`](#Contract-TimelockedGovernancesol) singleton instance. Proposal execution is permissionless, unless Emergency Mode is activated.

If the Emergency Committees are set up and active, the governance proposal undergoes a separate emergency protection delay between submission and scheduling. This additional timelock is implemented to protect against the execution of malicious proposals submitted by the DAO. If the Emergency Committees aren't set, the proposal flow remains the same, but the timelock duration is zero.

If the Emergency Committees are set up and active, the governance proposal undergoes a separate emergency protection delay between submission and scheduling. This additional timelock is implemented to safeguard against the execution of malicious proposals submitted by the DAO. If the Emergency Committees aren't set, the proposal flow remains the same, but the timelock duration is zero.

While active, the Emergency Activation Committee can enable Emergency Mode. This mode prohibits anyone but the Emergency Execution Committee from executing proposals. Once the **Emergency Duration** has ended, the Emergency Execution Committee or anyone else may disable the emergency mode, canceling all pending proposals. After the emergency mode is deactivated or the Emergency Period has elapsed, the Emergency Committees lose their power.
### Function: `EmergencyProtectedTimelock.submit`
```solidity
function submit(address executor, ExecutorCall[] calls, string metadata)
  returns (uint256 proposalId)
```
Registers a new governance proposal composed of one or more external `calls` to be made by the `executor` contract. Initiates the `AfterSubmitDelay`.
#### Returns
The ID of the successfully registered proposal.
#### Preconditions
* MUST be called by the `governance` address.
### Function: `EmergencyProtectedTimelock.schedule`
```solidity
function schedule(uint256 proposalId)
```
Schedules the submitted proposal for execution. Initiates the `AfterScheduleDelay`.
#### Preconditions

* MUST be called by the `governance` address.
* The proposal MUST be in the `Submitted` state.
* The `AfterSubmitDelay` MUST already elapse since the moment the proposal was submitted.

### Function: `EmergencyProtectedTimelock.execute`
```solidity
function execute(uint256 proposalId)
```
Instructs the executor contract associated with the proposal to issue the proposal's calls.
#### Preconditions
* Emergency mode MUST NOT be active.
* The proposal MUST be in the `Scheduled` state.
* The `AfterScheduleDelay` MUST already elapse since the moment the proposal was scheduled.

### Function: `EmergencyProtectedTimelock.cancelAllNonExecutedProposals`
```solidity
function cancelAllNonExecutedProposals()
```
Cancels all non-executed proposals, making them permanently non-executable.
#### Preconditions
* MUST be called by the `governance` address.
### Function: `EmergencyProtectedTimelock.activateEmergencyMode`
```solidity
function activateEmergencyMode()
```
Activates the Emergency Mode.
#### Preconditions
* MUST be called by the active Emergency Activation Committee address.
* The Emergency Mode MUST NOT be active.
### Function: `EmergencyProtectedTimelock.emergencyExecute`

```solidity
function emergencyExecute(uint256 proposalId)
```

Executes the scheduled proposal, bypassing the post-schedule delay.
#### Preconditions
* MUST be called by the Emergency Execution Committee address.
* The Emergency Mode MUST be active.
### Function: `EmergencyProtectedTimelock.deactivateEmergencyMode`
```solidity
function deactivateEmergencyMode()
```
Deactivates Emergency Mode, resets the Emergency Activation and Emergency Execution committees (setting their addresses to `0x00`), and cancels all unexecuted proposals.
#### Preconditions
* The Emergency Mode MUST be active.
* If the Emergency Mode was activated less than the `emergency mode max duration` ago, MUST be called by the [Admin Executor](#) address.
### Function: `EmergencyProtectedTimelock.emergencyReset`
```solidity
function emergencyReset()
```
Resets the `governance` address to the `EMERGENCY_GOVERNANCE` value defined in the configuration, deactivates the Emergency Mode, resets the Emergency Activation and Emergency Execution Committees (setting their addresses to `0x00`), and cancels all unexecuted proposals.
#### Preconditions
* The Emergency Mode MUST be active.
* MUST be called by the Emergency Execution Committee address.

### Admin functions
The contract has the interface for managing the configuration related to emergency protection (`setEmergencyProtectionActivationCommittee`, `setEmergencyProtectionExecutionCommittee`, `setEmergencyProtectionEndDate`, `setEmergencyModeDuration`, `setEmergencyGovernance`) and general system wiring (`transferExecutorOwnership`, `setGovernance`, `setupDelays`). These functions MUST be called by the [Admin Executor](#) address.

## Contract: `Executor`
Executes calls resulting from governance proposals' execution. Every protocol permission or role protected by the TG, as well as the permission to manage these roles/permissions, should be assigned exclusively to instances of this contract.

The timelocked governance setup is designed to use a single admin instance of the `Executor`, which is owned by the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelocksol) singleton instance.

### Function: `Executor.execute`
```solidity
function execute(address target, uint256 value, bytes payload)
  payable returns (bytes result)
```
Issues a external call to the `target` address with the `payload` calldata, optionally sending `value` wei ETH.

Reverts if the call was unsuccessful.
#### Returns
The result of the call.
#### Preconditions
* MUST be called by the contract owner (which SHOULD be the [`EmergencyProtectedTimelock`](#Contract-EmergencyProtectedTimelocksol) singleton instance).

## Contract: `Configuration`
`Configuration` is the smart contract encompassing all the constants in the Timelocked Governance design & providing the interfaces for getting access to them. It implements interfaces `IAdminExecutorConfiguration`, `ITimelockConfiguration` covering for relevant "parameters domains".

## Contract: `ProposalsList`
`ProposalsList` implements storage for list of `Proposal`s with public interface to access.

### Function: `ProposalsList.getProposals`
```solidity
function getProposals(uint256 offset, uint256 limit) external view returns (Proposal[] memory proposals)
```
Returns a list of `Proposal` structs, starting from the specified `offset` and bounded to the specified `limit`.

### Function: `ProposalsList.getProposalAt`
```solidity
function getProposalAt(uint256 index) external view returns (Proposal memory)
```
Returns the `Proposal` at the specified index.

### Function: `ProposalsList.getProposal`
```solidity
function getProposal(bytes32 key) external view returns (Proposal memory)
```
Returns the `Proposal` with the given key.

### Function: `ProposalsList.getProposalsLength`
```solidity
function getProposalsLength() external view returns (uint256)
```
Returns the total number of created `Proposal`s.

### Function: `ProposalsList.getOrderedKeys`
```solidity
function getOrderedKeys(uint256 offset, uint256 limit) external view returns (bytes32[] memory)
```
Returns a list of `Proposal` keys, starting from the specified `offset` and bounded by the specified `limit`.


## Contract: `HashConsensus`
`HashConsensus` is an abstract contract that facilitates consensus-based decision-making among a set of members. Consensus is achieved through members voting on a specific hash, with decisions executed only if a quorum is reached and a timelock period has elapsed.

### Function: `HashConsensus.addMember`
```solidity
function addMember(address newMember, uint256 newQuorum) external onlyOwner
```
Adds a new member and updates the quorum.

#### Preconditions
- Only the `owner` can call this function.
- `newQuorum` MUST be greater than 0 and less than or equal to the number of members.

### Function: `HashConsensus.removeMember`
```solidity
function removeMember(address memberToRemove, uint256 newQuorum) external onlyOwner
```
Removes a member and updates the quorum.

#### Preconditions
- Only the `owner` can call this function.
- `memberToRemove` MUST be an added member.
- `newQuorum` MUST be greater than 0 and less than or equal to the number of remaining members.

### Function: `HashConsensus.getMembers`
```solidity
function getMembers() external view returns (address[] memory)
```
Returns the list of current members.

### Function: `HashConsensus.isMember`
```solidity
function isMember(address member) external view returns (bool)
```
Returns whether an account is listed as a member.

### Function: `HashConsensus.setTimelockDuration`
```solidity
function setTimelockDuration(uint256 timelock) external onlyOwner
```
Sets the duration of the timelock.

#### Preconditions
- Only the `owner` can call this function.

### Function: `HashConsensus.setQuorum`
```solidity
function setQuorum(uint256 newQuorum) external onlyOwner
```
Sets the quorum required for decision execution.

#### Preconditions
- Only the `owner` can call this function.
- `newQuorum` MUST be greater than 0 and less than or equal to the number of members.

## Contract: `EmergencyActivationCommittee`
`EmergencyActivationCommittee` is a smart contract that extends the functionality of the `HashConsensus` contract to manage the emergency activation process. It allows committee members to vote on and execute the activation of emergency protocols in the specified contract.

### Constructor
```solidity
constructor(
    address owner,
    address[] memory committeeMembers,
    uint256 executionQuorum,
    address emergencyProtectedTimelock
)
```
Initializes the contract with an owner, committee members, a quorum, and the address of the `EmergencyProtectedTimelock` contract.

#### Preconditions
- `executionQuorum` MUST be greater than 0.

### Function: `EmergencyActivationCommittee.approveActivateEmergencyMode`
```solidity
function approveActivateEmergencyMode() public onlyMember
```
Approves the emergency activation by voting on the `EMERGENCY_ACTIVATION_HASH`.

#### Preconditions
- MUST be called by a committee member.

### Function: `EmergencyActivationCommittee.getActivateEmergencyModeState`
```solidity
function getActivateEmergencyModeState()
    public
    view
    returns (uint256 support, uint256 executionQuorum, bool isExecuted)
```
Returns the state of the emergency activation proposal, including the support count, quorum, and execution status.

### Function: `EmergencyActivationCommittee.executeActivateEmergencyMode`
```solidity
function executeActivateEmergencyMode() external
```
Executes the emergency activation by calling the `emergencyActivate` function on the `EmergencyProtectedTimelock` contract.

#### Preconditions
- The emergency activation proposal MUST have reached quorum and passed the timelock duration.

## Contract: `EmergencyExecutionCommittee`
`EmergencyExecutionCommittee` is a smart contract that extends the functionalities of `HashConsensus` and `ProposalsList` to manage emergency execution and governance reset proposals through a consensus mechanism. It interacts with the `EmergencyProtectedTimelock` contract to execute critical emergency proposals.

### Constructor
```solidity
constructor(
    address owner,
    address[] memory committeeMembers,
    uint256 executionQuorum,
    address emergencyProtectedTimelock
)
```
Initializes the contract with an owner, committee members, a quorum, and the address of the `EmergencyProtectedTimelock` contract.

#### Preconditions
- `executionQuorum` MUST be greater than 0.

### Function: `EmergencyExecutionCommittee.voteEmergencyExecute`
```solidity
function voteEmergencyExecute(uint256 proposalId, bool _supports) public
```
Allows committee members to vote on an emergency execution proposal.

#### Preconditions
- MUST be called by a committee member.

### Function: `EmergencyExecutionCommittee.getEmergencyExecuteState`
```solidity
function getEmergencyExecuteState(uint256 proposalId)
    public
    view
    returns (uint256 support, uint256 executionQuorum, bool isExecuted)
```
Returns the state of an emergency execution proposal, including the support count, quorum, and execution status.

### Function: `EmergencyExecutionCommittee.executeEmergencyExecute`
```solidity
function executeEmergencyExecute(uint256 proposalId) public
```
Executes an emergency execution proposal by calling the `emergencyExecute` function on the `EmergencyProtectedTimelock` contract.

#### Preconditions
- The emergency execution proposal MUST have reached quorum and passed the timelock duration.

### Function: `EmergencyExecutionCommittee.approveEmergencyReset`
```solidity
function approveEmergencyReset() public
```
Approves the governance reset by voting on the reset proposal.

#### Preconditions
- MUST be called by a committee member.

### Function: `EmergencyExecutionCommittee.getEmergencyResetState`
```solidity
function getEmergencyResetState()
    public
    view
    returns (uint256 support, uint256 executionQuorum, bool isExecuted)
```
Returns the state of the governance reset proposal, including the support count, quorum, and execution status.

### Function: `EmergencyExecutionCommittee.executeEmergencyReset`
```solidity
function executeEmergencyReset() external
```
Executes the governance reset by calling the `emergencyReset` function on the `EmergencyProtectedTimelock` contract.

#### Preconditions
- The governance reset proposal MUST have reached quorum and passed the timelock duration.

