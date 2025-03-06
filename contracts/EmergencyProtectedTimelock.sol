// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamp} from "./types/Timestamp.sol";
import {Duration, Durations} from "./types/Duration.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {IEmergencyProtectedTimelock} from "./interfaces/IEmergencyProtectedTimelock.sol";

import {ExternalCall} from "./libraries/ExternalCalls.sol";
import {TimelockState} from "./libraries/TimelockState.sol";
import {ExecutableProposals} from "./libraries/ExecutableProposals.sol";
import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";

/// @notice Timelock contract facilitating the submission, scheduling, and execution of governance proposals.
///     It provides time-limited Emergency Protection to prevent the execution of proposals submitted by
///     a compromised or misbehaving (including those caused by code vulnerabilities) governance entity.
/// @dev The proposal lifecycle:
///
///                                                                MIN_EXECUTION_DELAY and
///                                         afterSubmitDelay         afterScheduleDelay
///                                              passed                    passed
///     ┌──────────┐            ┌───────────┐              ┌───────────┐             ╔══════════╗
///     │ NotExist ├ submit() ─>│ Submitted ├ schedule() ─>│ Scheduled ├ execute() ─>║ Executed ║
///     └──────────┘            └────────┬──┘              └──┬────────┘             ╚══════════╝
///                                  cancelAllNonExecutedProposals()
///                                      │   ╔═══════════╗    │
///                                      └──>║ Cancelled ║<───┘
///                                          ╚═══════════╝
///
///     The afterSubmit and afterSchedule delays should be configured appropriately to provide the Emergency Activation
///     Committee sufficient time to activate Emergency Mode if a malicious proposal has been submitted or was
///     unexpectedly scheduled for execution due to governance capture or a vulnerability in the governance contract.
///     While Emergency Mode is active, the execution of proposals is restricted to the Emergency Execution Committee.
contract EmergencyProtectedTimelock is IEmergencyProtectedTimelock {
    using TimelockState for TimelockState.Context;
    using ExecutableProposals for ExecutableProposals.Context;
    using EmergencyProtection for EmergencyProtection.Context;

    // ---
    // Sanity Check Parameters & Immutables
    // ---

    /// @notice The parameters for the sanity checks.
    /// @param minExecutionDelay The minimum allowable duration for the combined after-submit and after-schedule delays.
    /// @param maxAfterSubmitDelay The maximum allowable delay before a submitted proposal can be scheduled for execution.
    /// @param maxAfterScheduleDelay The maximum allowable delay before a scheduled proposal can be executed.
    /// @param maxEmergencyModeDuration The maximum time the timelock can remain in emergency mode.
    /// @param maxEmergencyProtectionDuration The maximum time the emergency protection mechanism can be activated.
    struct SanityCheckParams {
        Duration minExecutionDelay;
        Duration maxAfterSubmitDelay;
        Duration maxAfterScheduleDelay;
        Duration maxEmergencyModeDuration;
        Duration maxEmergencyProtectionDuration;
    }

    /// @notice Represents the minimum allowed time that must pass between the submission of a proposal and its execution.
    /// @dev The minimum permissible value for the sum of `afterScheduleDelay` and `afterSubmitDelay`.
    Duration public immutable MIN_EXECUTION_DELAY;

    /// @notice The upper bound for the delay required before a submitted proposal can be scheduled for execution.
    Duration public immutable MAX_AFTER_SUBMIT_DELAY;

    /// @notice The upper bound for the delay required before a scheduled proposal can be executed.
    Duration public immutable MAX_AFTER_SCHEDULE_DELAY;

    /// @notice The upper bound for the time the timelock can remain in emergency mode.
    Duration public immutable MAX_EMERGENCY_MODE_DURATION;

    /// @notice The upper bound for the time the emergency protection mechanism can be activated.
    Duration public immutable MAX_EMERGENCY_PROTECTION_DURATION;

    // ---
    // Aspects
    // ---

    /// @dev The functionality for managing the state of the timelock.
    TimelockState.Context internal _timelockState;

    /// @dev The functionality for managing the lifecycle of proposals.
    ExecutableProposals.Context internal _proposals;

    /// @dev The functionality for managing the emergency protection mechanism.
    EmergencyProtection.Context internal _emergencyProtection;

    // ---
    // Constructor
    // ---

    constructor(
        SanityCheckParams memory sanityCheckParams,
        address adminExecutor,
        Duration afterSubmitDelay,
        Duration afterScheduleDelay
    ) {
        MIN_EXECUTION_DELAY = sanityCheckParams.minExecutionDelay;
        MAX_AFTER_SUBMIT_DELAY = sanityCheckParams.maxAfterSubmitDelay;
        MAX_AFTER_SCHEDULE_DELAY = sanityCheckParams.maxAfterScheduleDelay;
        MAX_EMERGENCY_MODE_DURATION = sanityCheckParams.maxEmergencyModeDuration;
        MAX_EMERGENCY_PROTECTION_DURATION = sanityCheckParams.maxEmergencyProtectionDuration;

        _timelockState.setAdminExecutor(adminExecutor);

        if (afterSubmitDelay > Durations.ZERO) {
            _timelockState.setAfterSubmitDelay(afterSubmitDelay, MAX_AFTER_SUBMIT_DELAY);
        }

        if (afterScheduleDelay > Durations.ZERO) {
            _timelockState.setAfterScheduleDelay(afterScheduleDelay, MAX_AFTER_SCHEDULE_DELAY);
        }

        _timelockState.checkExecutionDelay(MIN_EXECUTION_DELAY);
    }

    // ---
    // Main Timelock Functionality
    // ---

    /// @notice Submits a new proposal to execute a series of calls through an executor.
    /// @param executor The address of the executor contract that will execute the calls.
    /// @param calls An array of `ExternalCall` structs representing the calls to be executed.
    /// @return newProposalId The id of the newly created proposal.
    function submit(address executor, ExternalCall[] calldata calls) external returns (uint256 newProposalId) {
        _timelockState.checkCallerIsGovernance();
        newProposalId = _proposals.submit(executor, calls);
    }

    /// @notice Schedules a proposal for execution after a specified delay.
    /// @param proposalId The id of the proposal to be scheduled.
    function schedule(uint256 proposalId) external {
        _timelockState.checkCallerIsGovernance();
        _proposals.schedule(proposalId, _timelockState.getAfterSubmitDelay());
    }

    /// @notice Executes a scheduled proposal.
    /// @param proposalId The id of the proposal to be executed.
    function execute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyMode({isActive: false});
        _proposals.execute(proposalId, _timelockState.getAfterScheduleDelay(), MIN_EXECUTION_DELAY);
    }

    /// @notice Cancels all non-executed proposals, preventing them from being executed in the future.
    function cancelAllNonExecutedProposals() external {
        _timelockState.checkCallerIsGovernance();
        _proposals.cancelAll();
    }

    // ---
    // Timelock Management
    // ---

    /// @notice Updates the address of the governance contract  and cancels all non-executed proposals.
    /// @param newGovernance The address of the new governance contract to be set.
    function setGovernance(address newGovernance) external {
        _timelockState.checkCallerIsAdminExecutor();
        _timelockState.setGovernance(newGovernance);
        _proposals.cancelAll();
    }

    /// @notice Sets the delay required to pass from the submission of a proposal before it can be scheduled for execution.
    ///     Ensures that the new delay value complies with the defined sanity check bounds.
    /// @param newAfterSubmitDelay The delay required before a submitted proposal can be scheduled.
    function setAfterSubmitDelay(Duration newAfterSubmitDelay) external {
        _timelockState.checkCallerIsAdminExecutor();
        _timelockState.setAfterSubmitDelay(newAfterSubmitDelay, MAX_AFTER_SUBMIT_DELAY);
        _timelockState.checkExecutionDelay(MIN_EXECUTION_DELAY);
    }

    /// @notice Sets the delay required to pass from the scheduling of a proposal before it can be executed.
    ///     Ensures that the new delay value complies with the defined sanity check bounds.
    /// @param newAfterScheduleDelay The delay required before a scheduled proposal can be executed.
    function setAfterScheduleDelay(Duration newAfterScheduleDelay) external {
        _timelockState.checkCallerIsAdminExecutor();
        _timelockState.setAfterScheduleDelay(newAfterScheduleDelay, MAX_AFTER_SCHEDULE_DELAY);
        _timelockState.checkExecutionDelay(MIN_EXECUTION_DELAY);
    }

    /// @notice Transfers ownership of the executor contract to a new owner.
    /// @param executor The address of the executor contract.
    /// @param owner The address of the new owner.
    function transferExecutorOwnership(address executor, address owner) external {
        _timelockState.checkCallerIsAdminExecutor();
        IOwnable(executor).transferOwnership(owner);
    }

    // ---
    // Emergency Protection Functionality
    // ---

    /// @notice Sets the emergency activation committee address.
    /// @param newEmergencyActivationCommittee The address of the emergency activation committee.
    function setEmergencyProtectionActivationCommittee(address newEmergencyActivationCommittee) external {
        _timelockState.checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyActivationCommittee(newEmergencyActivationCommittee);
    }

    /// @notice Sets the emergency execution committee address.
    /// @param newEmergencyExecutionCommittee The address of the emergency execution committee.
    function setEmergencyProtectionExecutionCommittee(address newEmergencyExecutionCommittee) external {
        _timelockState.checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyExecutionCommittee(newEmergencyExecutionCommittee);
    }

    /// @notice Sets the emergency protection end date.
    /// @param newEmergencyProtectionEndDate The timestamp of the emergency protection end date.
    function setEmergencyProtectionEndDate(Timestamp newEmergencyProtectionEndDate) external {
        _timelockState.checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyProtectionEndDate(
            newEmergencyProtectionEndDate, MAX_EMERGENCY_PROTECTION_DURATION
        );
    }

    /// @notice Sets the emergency mode duration.
    /// @param newEmergencyModeDuration The duration of the emergency mode.
    function setEmergencyModeDuration(Duration newEmergencyModeDuration) external {
        _timelockState.checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyModeDuration(newEmergencyModeDuration, MAX_EMERGENCY_MODE_DURATION);
    }

    /// @notice Sets the emergency governance address.
    /// @param newEmergencyGovernance The address of the emergency governance.
    function setEmergencyGovernance(address newEmergencyGovernance) external {
        _timelockState.checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyGovernance(newEmergencyGovernance);
    }

    /// @notice Activates the emergency mode.
    function activateEmergencyMode() external {
        _emergencyProtection.checkCallerIsEmergencyActivationCommittee();
        _emergencyProtection.checkEmergencyMode({isActive: false});
        _emergencyProtection.activateEmergencyMode();
    }

    /// @notice Executes a proposal during emergency mode.
    /// @param proposalId The id of the proposal to be executed.
    function emergencyExecute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyMode({isActive: true});
        _emergencyProtection.checkCallerIsEmergencyExecutionCommittee();
        _proposals.execute({
            proposalId: proposalId,
            afterScheduleDelay: Durations.ZERO,
            minExecutionDelay: Durations.ZERO
        });
    }

    /// @notice Deactivates the emergency mode.
    function deactivateEmergencyMode() external {
        _emergencyProtection.checkEmergencyMode({isActive: true});
        if (!_emergencyProtection.isEmergencyModeDurationPassed()) {
            _timelockState.checkCallerIsAdminExecutor();
        }
        _emergencyProtection.deactivateEmergencyMode();
        _proposals.cancelAll();
    }

    /// @notice Resets the system after entering the emergency mode.
    function emergencyReset() external {
        _emergencyProtection.checkCallerIsEmergencyExecutionCommittee();
        _emergencyProtection.checkEmergencyMode({isActive: true});
        _emergencyProtection.deactivateEmergencyMode();

        _timelockState.setGovernance(_emergencyProtection.emergencyGovernance);
        _proposals.cancelAll();
    }

    /// @notice Returns whether the emergency protection is enabled.
    /// @return isEmergencyProtectionEnabled A boolean indicating whether the emergency protection is enabled.
    function isEmergencyProtectionEnabled() external view returns (bool) {
        return _emergencyProtection.isEmergencyProtectionEnabled();
    }

    /// @notice Returns whether the emergency mode is active.
    /// @return isEmergencyModeActive A boolean indicating whether the emergency mode is active.
    function isEmergencyModeActive() external view returns (bool) {
        return _emergencyProtection.isEmergencyModeActive();
    }

    /// @notice Returns the details of the emergency protection.
    /// @return details A struct containing the emergency mode duration, emergency mode ends after, and emergency protection ends after.
    function getEmergencyProtectionDetails() external view returns (EmergencyProtectionDetails memory details) {
        return _emergencyProtection.getEmergencyProtectionDetails();
    }

    /// @notice Returns the address of the emergency governance.
    /// @return emergencyGovernance The address of the emergency governance.
    function getEmergencyGovernance() external view returns (address) {
        return _emergencyProtection.emergencyGovernance;
    }

    /// @notice Returns the address of the emergency activation committee.
    /// @return emergencyActivationCommittee The address of the emergency activation committee.
    function getEmergencyActivationCommittee() external view returns (address) {
        return _emergencyProtection.emergencyActivationCommittee;
    }

    /// @notice Returns the address of the emergency execution committee.
    /// @return emergencyExecutionCommittee The address of the emergency execution committee.
    function getEmergencyExecutionCommittee() external view returns (address) {
        return _emergencyProtection.emergencyExecutionCommittee;
    }

    // ---
    // Timelock View Methods
    // ---

    /// @notice Returns the address of the current governance contract.
    /// @return governance The address of the governance contract.
    function getGovernance() external view returns (address) {
        return _timelockState.governance;
    }

    /// @notice Returns the address of the admin executor.
    /// @return adminExecutor The address of the admin executor.
    function getAdminExecutor() external view returns (address) {
        return _timelockState.adminExecutor;
    }

    /// @notice Returns the configured delay duration required before a submitted proposal can be scheduled.
    /// @return afterSubmitDelay The duration of the after-submit delay.
    function getAfterSubmitDelay() external view returns (Duration) {
        return _timelockState.getAfterSubmitDelay();
    }

    /// @notice Returns the configured delay duration required before a scheduled proposal can be executed.
    /// @return afterScheduleDelay The duration of the after-schedule delay.
    function getAfterScheduleDelay() external view returns (Duration) {
        return _timelockState.getAfterScheduleDelay();
    }

    /// @notice Returns the details of a proposal.
    /// @param proposalId The id of the proposal.
    /// @return proposalDetails The Proposal struct containing the details of the proposal.
    /// @return calls An array of ExternalCall structs representing the sequence of calls to be executed for the proposal.
    function getProposal(uint256 proposalId)
        external
        view
        returns (ProposalDetails memory proposalDetails, ExternalCall[] memory calls)
    {
        proposalDetails = _proposals.getProposalDetails(proposalId);
        calls = _proposals.getProposalCalls(proposalId);
    }

    /// @notice Returns information about a proposal, excluding the external calls associated with it.
    /// @param proposalId The id of the proposal to return information for.
    /// @return proposalDetails A ProposalDetails struct containing the details of the proposal, with the following data:
    ///     - `id`: The id of the proposal.
    ///     - `executor`: The address of the executor responsible for executing the proposal's external calls.
    ///     - `submittedAt`: The timestamp when the proposal was submitted.
    ///     - `scheduledAt`: The timestamp when the proposal was scheduled for execution. Equals 0 if the proposal
    ///            was submitted but not yet scheduled.
    ///     - `status`: The current status of the proposal. Possible values are:
    ///         1 - The proposal was submitted but not scheduled.
    ///         2 - The proposal was submitted and scheduled but not yet executed.
    ///         3 - The proposal was submitted, scheduled, and executed. This is the final state of the proposal lifecycle.
    ///         4 - The proposal was cancelled via cancelAllNonExecutedProposals() and cannot be scheduled or executed anymore.
    ///             This is the final state of the proposal.
    function getProposalDetails(uint256 proposalId) external view returns (ProposalDetails memory proposalDetails) {
        return _proposals.getProposalDetails(proposalId);
    }

    /// @notice Returns the external calls associated with the specified proposal.
    /// @param proposalId The id of the proposal to return external calls for.
    /// @return calls An array of ExternalCall structs representing the sequence of calls to be executed for the proposal.
    function getProposalCalls(uint256 proposalId) external view returns (ExternalCall[] memory calls) {
        calls = _proposals.getProposalCalls(proposalId);
    }

    /// @notice Returns the total number of proposals.
    /// @return count The total number of proposals.
    function getProposalsCount() external view returns (uint256 count) {
        count = _proposals.getProposalsCount();
    }

    /// @notice Checks if a proposal can be executed.
    /// @param proposalId The id of the proposal.
    /// @return A boolean indicating if the proposal can be executed.
    function canExecute(uint256 proposalId) external view returns (bool) {
        return !_emergencyProtection.isEmergencyModeActive()
            && _proposals.canExecute(proposalId, _timelockState.getAfterScheduleDelay(), MIN_EXECUTION_DELAY);
    }

    /// @notice Checks if a proposal can be scheduled.
    /// @param proposalId The id of the proposal.
    /// @return A boolean indicating if the proposal can be scheduled.
    function canSchedule(uint256 proposalId) external view returns (bool) {
        return _proposals.canSchedule(proposalId, _timelockState.getAfterSubmitDelay());
    }

    // ---
    // Admin Executor Methods
    // ---

    /// @notice Sets the address of the admin executor.
    /// @param newAdminExecutor The address of the new admin executor.
    function setAdminExecutor(address newAdminExecutor) external {
        _timelockState.checkCallerIsAdminExecutor();
        _timelockState.setAdminExecutor(newAdminExecutor);
    }
}
