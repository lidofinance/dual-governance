// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "./types/Duration.sol";
import {Timestamp, Timestamps} from "./types/Timestamp.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ITimelock, ProposalStatus} from "./interfaces/ITimelock.sol";

import {EmergencyProtection} from "./libraries/EmergencyProtections.sol";

import {ExternalCall} from "./libraries/ExternalCalls.sol";
import {ExecutableProposals} from "./libraries/ExecutableProposals.sol";

import {
    Timelock,
    IEmergencyProtectedTimelockConfigProvider
} from "./configuration/EmergencyProtectedTimelockConfigProvider.sol";

/// @title EmergencyProtectedTimelock
/// @dev A timelock contract with emergency protection functionality.
/// The contract allows for submitting, scheduling, and executing proposals,
/// while providing emergency protection features to prevent unauthorized
/// execution during emergency situations.
contract EmergencyProtectedTimelock is ITimelock {
    using Timelock for Timelock.Context;
    using ExecutableProposals for ExecutableProposals.State;
    using EmergencyProtection for EmergencyProtection.Context;

    error InvalidConfigProvider(address value);
    error NotGovernance(address account, address governance);
    error NotAdminExecutor(address account, address adminExecutor);

    error EmergencyModePassed();
    error EmergencyModeActive();
    error EmergencyModeNotActive();
    error NotEmergencyActivationCommittee();
    error NotEmergencyExecutionCommittee();
    error EmergencyProtectionExpired();

    event ConfigProviderSet(address newConfigProvider);
    event EmergencyModeActivated(Timestamp timestamp);
    event EmergencyModeDeactivated(Timestamp timestamp);

    Timelock.Context internal _timelock;
    ExecutableProposals.State internal _proposals;
    EmergencyProtection.Context internal _emergencyProtection;

    IEmergencyProtectedTimelockConfigProvider internal _configProvider;

    constructor(address configProvider, address adminExecutor) {
        setConfigProvider(configProvider);
        _timelock.setAdminExecutor(adminExecutor);
    }

    // ---
    // Main Timelock Functionality
    // ---

    /// @dev Submits a new proposal to execute a series of calls through an executor.
    /// Only the governance contract can call this function.
    /// @param executor The address of the executor contract that will execute the calls.
    /// @param calls An array of `ExternalCall` structs representing the calls to be executed.
    /// @return newProposalId The ID of the newly created proposal.
    function submit(address executor, ExternalCall[] calldata calls) external returns (uint256 newProposalId) {
        _timelock.checkGovernance(msg.sender);
        newProposalId = _proposals.submit(executor, calls);
    }

    /// @dev Schedules a proposal for execution after a specified delay.
    /// Only the governance contract can call this function.
    /// @param proposalId The ID of the proposal to be scheduled.
    function schedule(uint256 proposalId) external {
        _timelock.checkGovernance(msg.sender);
        _proposals.schedule(proposalId, _timelock.afterSubmitDelay);
    }

    /// @dev Executes a scheduled proposal.
    /// Checks if emergency mode is active and prevents execution if it is.
    /// @param proposalId The ID of the proposal to be executed.
    function execute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyMode({isActive: false});
        _proposals.execute(proposalId, _timelock.getAfterScheduleDelay());
    }

    /// @dev Cancels all non-executed proposals.
    /// Only the governance contract can call this function.
    function cancelAllNonExecutedProposals() external {
        _timelock.checkGovernance(msg.sender);
        _proposals.cancelAll();
    }

    // ---
    // Timelock Management
    // ---

    function setConfigProvider(address newConfigProvider) public {
        if (newConfigProvider == address(0)) {
            revert InvalidConfigProvider(newConfigProvider);
        }
        if (newConfigProvider == address(_configProvider)) {
            return;
        }
        _configProvider = IEmergencyProtectedTimelockConfigProvider(newConfigProvider);
        emit ConfigProviderSet(newConfigProvider);
    }

    function setGovernance(address newGovernance) external {
        _timelock.checkAdminExecutor(msg.sender);
        _timelock.setGovernance(newGovernance);
    }

    function setAdminExecutor(address newAdminExecutor) external {
        _timelock.checkAdminExecutor(msg.sender);
        _timelock.setAdminExecutor(newAdminExecutor);
    }

    function setDelays(Duration afterSubmitDelay, Duration afterScheduleDelay) external {
        _timelock.checkAdminExecutor(msg.sender);
        Timelock.Config memory timelockConfig = _configProvider.getTimelockConfig();
        _timelock.setAfterSubmitDelay(timelockConfig, afterSubmitDelay);
        _timelock.setAfterScheduleDelay(timelockConfig, afterScheduleDelay);
    }

    /// @dev Transfers ownership of the executor contract to a new owner.
    /// Only the admin executor can call this function.
    /// @param executor The address of the executor contract.
    /// @param owner The address of the new owner.
    function transferExecutorOwnership(address executor, address owner) external {
        _timelock.checkAdminExecutor(msg.sender);
        IOwnable(executor).transferOwnership(owner);
    }

    // ---
    // Emergency Protection Functionality
    // ---
    function setupEmergencyProtection(
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        Duration protectionDuration,
        Duration emergencyModeDuration
    ) external {
        _timelock.checkAdminExecutor(msg.sender);
        EmergencyProtection.Config memory emergencyConfig = _configProvider.getEmergencyProtectionConfig();
        _emergencyProtection.setEmergencyGovernance(emergencyGovernance);
        _emergencyProtection.setEmergencyModeDuration(emergencyConfig, emergencyModeDuration);
        _emergencyProtection.setEmergencyModeProtectedTill(emergencyConfig, protectionDuration);
        _emergencyProtection.setEmergencyActivationCommittee(emergencyActivationCommittee);
        _emergencyProtection.setEmergencyExecutionCommittee(emergencyExecutionCommittee);
    }

    /// @dev Activates the emergency mode.
    /// Only the activation committee can call this function.
    function activateEmergencyMode() external {
        _emergencyProtection.checkActivationCommittee(msg.sender);
        _emergencyProtection.checkEmergencyProtectionEnabled();
        _emergencyProtection.checkEmergencyMode({isActive: false});
        _emergencyProtection.activate();
    }

    /// @dev Executes a proposal during emergency mode.
    /// Checks if emergency mode is active and if the caller is part of the execution committee.
    /// @param proposalId The ID of the proposal to be executed.
    function emergencyExecute(uint256 proposalId) external {
        _emergencyProtection.checkExecutionCommittee(msg.sender);
        _emergencyProtection.checkEmergencyMode({isActive: true});
        _proposals.execute({proposalId: proposalId, afterScheduleDelay: Duration.wrap(0)});
    }

    /// @dev Deactivates the emergency mode.
    /// If the emergency mode has not passed, only the admin executor can call this function.
    function deactivateEmergencyMode() external {
        _timelock.checkAdminExecutor(msg.sender);
        _emergencyProtection.checkEmergencyMode({isActive: true});
        _emergencyProtection.deactivate();
        _proposals.cancelAll();
    }

    /// @dev Resets the system after entering the emergency mode.
    /// Only the execution committee can call this function.
    function emergencyReset() external {
        _emergencyProtection.checkExecutionCommittee(msg.sender);
        _emergencyProtection.checkEmergencyMode({isActive: true});
        _emergencyProtection.deactivate();
        _proposals.cancelAll();
        _timelock.setGovernance(_emergencyProtection.emergencyGovernance);
    }

    function getEmergencyProtectionContext() external view returns (EmergencyProtection.Context memory) {
        return _emergencyProtection;
    }

    function isEmergencyModeActive() public view returns (bool isActive) {
        isActive = _emergencyProtection.isEmergencyModeActive();
    }

    // ---
    // Timelock View Methods
    // ---

    function getAdminExecutor() external view returns (address) {
        return _timelock.adminExecutor;
    }

    function getAfterSubmitDelay() external view returns (Duration) {
        return _timelock.afterSubmitDelay;
    }

    function getAfterScheduleDelay() external view returns (Duration) {
        return _timelock.afterScheduleDelay;
    }

    /// @dev Retrieves the details of a proposal.
    /// @param proposalId The ID of the proposal.
    /// @return proposal The Proposal struct containing the details of the proposal.
    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        proposal.id = proposalId;
        (proposal.status, proposal.executor, proposal.submittedAt, proposal.scheduledAt) =
            _proposals.getProposalInfo(proposalId);
        proposal.calls = _proposals.getProposalCalls(proposalId);
    }

    /// @notice Retrieves information about a proposal, excluding the external calls associated with it.
    /// @param proposalId The ID of the proposal to retrieve information for.
    /// @return id The ID of the proposal.
    /// @return status The current status of the proposal. Possible values are:
    /// 0 - The proposal does not exist.
    /// 1 - The proposal was submitted but not scheduled.
    /// 2 - The proposal was submitted and scheduled but not yet executed.
    /// 3 - The proposal was submitted, scheduled, and executed. This is the final state of the proposal lifecycle.
    /// 4 - The proposal was cancelled via cancelAllNonExecutedProposals() and cannot be scheduled or executed anymore.
    ///     This is the final state of the proposal.
    /// @return executor The address of the executor responsible for executing the proposal's external calls.
    /// @return submittedAt The timestamp when the proposal was submitted.
    /// @return scheduledAt The timestamp when the proposal was scheduled for execution. Equals 0 if the proposal
    /// was submitted but not yet scheduled.
    function getProposalInfo(uint256 proposalId)
        external
        view
        returns (uint256 id, ProposalStatus status, address executor, Timestamp submittedAt, Timestamp scheduledAt)
    {
        id = proposalId;
        (status, executor, submittedAt, scheduledAt) = _proposals.getProposalInfo(proposalId);
    }

    /// @notice Retrieves the external calls associated with the specified proposal.
    /// @param proposalId The ID of the proposal to retrieve external calls for.
    /// @return calls An array of ExternalCall structs representing the sequence of calls to be executed for the proposal.
    function getProposalCalls(uint256 proposalId) external view returns (ExternalCall[] memory calls) {
        calls = _proposals.getProposalCalls(proposalId);
    }

    /// @dev Retrieves the total number of proposals.
    /// @return count The total number of proposals.
    function getProposalsCount() external view returns (uint256 count) {
        count = _proposals.getProposalsCount();
    }

    /// @dev Checks if a proposal can be executed.
    /// @param proposalId The ID of the proposal.
    /// @return A boolean indicating if the proposal can be executed.
    function canExecute(uint256 proposalId) external view returns (bool) {
        return !_emergencyProtection.isEmergencyModeActive()
            && _proposals.canExecute(proposalId, _timelock.getAfterScheduleDelay());
    }

    /// @dev Checks if a proposal can be scheduled.
    /// @param proposalId The ID of the proposal.
    /// @return A boolean indicating if the proposal can be scheduled.
    function canSchedule(uint256 proposalId) external view returns (bool) {
        return _proposals.canSchedule(proposalId, _timelock.getAfterSubmitDelay());
    }
}
