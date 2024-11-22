// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {IEmergencyProtectedTimelock} from "./interfaces/IEmergencyProtectedTimelock.sol";

import {ExternalCall} from "./libraries/ExternalCalls.sol";
import {TimelockState} from "./libraries/TimelockState.sol";
import {ExecutableProposals} from "./libraries/ExecutableProposals.sol";
import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";

/// @title EmergencyProtectedTimelock
/// @dev A timelock contract with emergency protection functionality. The contract allows for submitting, scheduling,
///     and executing proposals, while providing emergency protection features to prevent unauthorized execution during
///     emergency situations.
contract EmergencyProtectedTimelock is IEmergencyProtectedTimelock {
    using TimelockState for TimelockState.Context;
    using ExecutableProposals for ExecutableProposals.Context;
    using EmergencyProtection for EmergencyProtection.Context;

    // ---
    // Errors
    // ---

    error CallerIsNotAdminExecutor(address value);

    // ---
    // Sanity Check Parameters & Immutables
    // ---

    /// @notice The parameters for the sanity checks.
    /// @param maxAfterSubmitDelay The maximum allowable delay before a submitted proposal can be scheduled for execution.
    /// @param maxAfterScheduleDelay The maximum allowable delay before a scheduled proposal can be executed.
    /// @param maxEmergencyModeDuration The maximum time the timelock can remain in emergency mode.
    /// @param maxEmergencyProtectionDuration The maximum time the emergency protection mechanism can be activated.
    struct SanityCheckParams {
        Duration maxAfterSubmitDelay;
        Duration maxAfterScheduleDelay;
        Duration maxEmergencyModeDuration;
        Duration maxEmergencyProtectionDuration;
    }

    /// @notice The upper bound for the delay required before a submitted proposal can be scheduled for execution.
    Duration public immutable MAX_AFTER_SUBMIT_DELAY;

    /// @notice The upper bound for the delay required before a scheduled proposal can be executed.
    Duration public immutable MAX_AFTER_SCHEDULE_DELAY;

    /// @notice The upper bound for the time the timelock can remain in emergency mode.
    Duration public immutable MAX_EMERGENCY_MODE_DURATION;

    /// @notice The upper bound for the time the emergency protection mechanism can be activated.
    Duration public immutable MAX_EMERGENCY_PROTECTION_DURATION;

    // ---
    // Admin Executor Immutables
    // ---

    /// @dev The address of the admin executor, authorized to manage the EmergencyProtectedTimelock instance.
    address private immutable _ADMIN_EXECUTOR;

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

    constructor(SanityCheckParams memory sanityCheckParams, address adminExecutor) {
        _ADMIN_EXECUTOR = adminExecutor;

        MAX_AFTER_SUBMIT_DELAY = sanityCheckParams.maxAfterSubmitDelay;
        MAX_AFTER_SCHEDULE_DELAY = sanityCheckParams.maxAfterScheduleDelay;
        MAX_EMERGENCY_MODE_DURATION = sanityCheckParams.maxEmergencyModeDuration;
        MAX_EMERGENCY_PROTECTION_DURATION = sanityCheckParams.maxEmergencyProtectionDuration;
    }

    // ---
    // Main Timelock Functionality
    // ---

    /// @notice Submits a new proposal to execute a series of calls through an executor.
    /// @param executor The address of the executor contract that will execute the calls.
    /// @param calls An array of `ExternalCall` structs representing the calls to be executed.
    /// @param metadata A string containing additional information about the proposal.
    /// @return newProposalId The id of the newly created proposal.
    function submit(
        address executor,
        ExternalCall[] calldata calls,
        string calldata metadata
    ) external returns (uint256 newProposalId) {
        _timelockState.checkCallerIsGovernance();
        newProposalId = _proposals.submit(executor, calls, metadata);
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
        _proposals.execute(proposalId, _timelockState.getAfterScheduleDelay());
    }

    /// @notice Cancels all non-executed proposals, preventing them from being executed in the future.
    function cancelAllNonExecutedProposals() external {
        _timelockState.checkCallerIsGovernance();
        _proposals.cancelAll();
    }

    // ---
    // Timelock Management
    // ---

    /// @notice Updates the address of the governance contract.
    /// @param newGovernance The address of the new governance contract to be set.
    function setGovernance(address newGovernance) external {
        _checkCallerIsAdminExecutor();
        _timelockState.setGovernance(newGovernance);
    }

    /// @notice Configures the delays for submitting and scheduling proposals, within defined upper bounds.
    /// @param afterSubmitDelay The delay required before a submitted proposal can be scheduled.
    /// @param afterScheduleDelay The delay required before a scheduled proposal can be executed.
    function setupDelays(Duration afterSubmitDelay, Duration afterScheduleDelay) external {
        _checkCallerIsAdminExecutor();
        _timelockState.setAfterSubmitDelay(afterSubmitDelay, MAX_AFTER_SUBMIT_DELAY);
        _timelockState.setAfterScheduleDelay(afterScheduleDelay, MAX_AFTER_SCHEDULE_DELAY);
    }

    /// @notice Transfers ownership of the executor contract to a new owner.
    /// @param executor The address of the executor contract.
    /// @param owner The address of the new owner.
    function transferExecutorOwnership(address executor, address owner) external {
        _checkCallerIsAdminExecutor();
        IOwnable(executor).transferOwnership(owner);
    }

    // ---
    // Emergency Protection Functionality
    // ---

    /// @notice Sets the emergency activation committee address.
    /// @param emergencyActivationCommittee The address of the emergency activation committee.
    function setEmergencyProtectionActivationCommittee(address emergencyActivationCommittee) external {
        _checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyActivationCommittee(emergencyActivationCommittee);
    }

    /// @notice Sets the emergency execution committee address.
    /// @param emergencyExecutionCommittee The address of the emergency execution committee.
    function setEmergencyProtectionExecutionCommittee(address emergencyExecutionCommittee) external {
        _checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyExecutionCommittee(emergencyExecutionCommittee);
    }

    /// @notice Sets the emergency protection end date.
    /// @param emergencyProtectionEndDate The timestamp of the emergency protection end date.
    function setEmergencyProtectionEndDate(Timestamp emergencyProtectionEndDate) external {
        _checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyProtectionEndDate(
            emergencyProtectionEndDate, MAX_EMERGENCY_PROTECTION_DURATION
        );
    }

    /// @notice Sets the emergency mode duration.
    /// @param emergencyModeDuration The duration of the emergency mode.
    function setEmergencyModeDuration(Duration emergencyModeDuration) external {
        _checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyModeDuration(emergencyModeDuration, MAX_EMERGENCY_MODE_DURATION);
    }

    /// @notice Sets the emergency governance address.
    /// @param emergencyGovernance The address of the emergency governance.
    function setEmergencyGovernance(address emergencyGovernance) external {
        _checkCallerIsAdminExecutor();
        _emergencyProtection.setEmergencyGovernance(emergencyGovernance);
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
        _proposals.execute({proposalId: proposalId, afterScheduleDelay: Duration.wrap(0)});
    }

    /// @notice Deactivates the emergency mode.
    function deactivateEmergencyMode() external {
        _emergencyProtection.checkEmergencyMode({isActive: true});
        if (!_emergencyProtection.isEmergencyModeDurationPassed()) {
            _checkCallerIsAdminExecutor();
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
    /// @return isEmergencyModeActive A boolean indicating whether the emergency protection is enabled.
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
        return _ADMIN_EXECUTOR;
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

    /// @notice Retrieves the details of a proposal.
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

    /// @notice Retrieves information about a proposal, excluding the external calls associated with it.
    /// @param proposalId The id of the proposal to retrieve information for.
    /// @return proposalDetails A ProposalDetails struct containing the details of the proposal, with the following data:
    ///     - `id`: The id of the proposal.
    ///     - `status`: The current status of the proposal. Possible values are:
    ///         0 - The proposal does not exist.
    ///         1 - The proposal was submitted but not scheduled.
    ///         2 - The proposal was submitted and scheduled but not yet executed.
    ///         3 - The proposal was submitted, scheduled, and executed. This is the final state of the proposal lifecycle.
    ///         4 - The proposal was cancelled via cancelAllNonExecutedProposals() and cannot be scheduled or executed anymore.
    ///             This is the final state of the proposal.
    ///     - `executor`: The address of the executor responsible for executing the proposal's external calls.
    ///     - `submittedAt`: The timestamp when the proposal was submitted.
    ///     - `scheduledAt`: The timestamp when the proposal was scheduled for execution. Equals 0 if the proposal
    ///            was submitted but not yet scheduled.
    function getProposalDetails(uint256 proposalId) external view returns (ProposalDetails memory proposalDetails) {
        return _proposals.getProposalDetails(proposalId);
    }

    /// @notice Retrieves the external calls associated with the specified proposal.
    /// @param proposalId The id of the proposal to retrieve external calls for.
    /// @return calls An array of ExternalCall structs representing the sequence of calls to be executed for the proposal.
    function getProposalCalls(uint256 proposalId) external view returns (ExternalCall[] memory calls) {
        calls = _proposals.getProposalCalls(proposalId);
    }

    /// @notice Retrieves the total number of proposals.
    /// @return count The total number of proposals.
    function getProposalsCount() external view returns (uint256 count) {
        count = _proposals.getProposalsCount();
    }

    /// @notice Checks if a proposal can be executed.
    /// @param proposalId The id of the proposal.
    /// @return A boolean indicating if the proposal can be executed.
    function canExecute(uint256 proposalId) external view returns (bool) {
        return !_emergencyProtection.isEmergencyModeActive()
            && _proposals.canExecute(proposalId, _timelockState.getAfterScheduleDelay());
    }

    /// @notice Checks if a proposal can be scheduled.
    /// @param proposalId The id of the proposal.
    /// @return A boolean indicating if the proposal can be scheduled.
    function canSchedule(uint256 proposalId) external view returns (bool) {
        return _proposals.canSchedule(proposalId, _timelockState.getAfterSubmitDelay());
    }

    // ---
    // Internal Methods
    // ---

    function _checkCallerIsAdminExecutor() internal view {
        if (msg.sender != _ADMIN_EXECUTOR) {
            revert CallerIsNotAdminExecutor(msg.sender);
        }
    }
}
