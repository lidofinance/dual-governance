// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";

import {Proposal, Proposals, ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection, EmergencyState} from "./libraries/EmergencyProtection.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

/// @title EmergencyProtectedTimelock
/// @dev A timelock contract with emergency protection functionality.
/// The contract allows for submitting, scheduling, and executing proposals,
/// while providing emergency protection features to prevent unauthorized
/// execution during emergency situations.
contract EmergencyProtectedTimelock is ITimelock, ConfigurationProvider {
    using Proposals for Proposals.State;
    using EmergencyProtection for EmergencyProtection.State;

    error InvalidGovernance(address governance);
    error NotGovernance(address account, address governance);

    event GovernanceSet(address governance);

    address internal _governance;

    Proposals.State internal _proposals;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(address config) ConfigurationProvider(config) {}

    // ---
    // Main Timelock Functionality
    // ---

    /// @dev Submits a new proposal to execute a series of calls through an executor.
    /// Only the governance contract can call this function.
    /// @param executor The address of the executor contract that will execute the calls.
    /// @param calls An array of `ExecutorCall` structs representing the calls to be executed.
    /// @return newProposalId The ID of the newly created proposal.
    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _checkGovernance(msg.sender);
        newProposalId = _proposals.submit(executor, calls);
    }

    /// @dev Schedules a proposal for execution after a specified delay.
    /// Only the governance contract can call this function.
    /// @param proposalId The ID of the proposal to be scheduled.
    function schedule(uint256 proposalId) external {
        _checkGovernance(msg.sender);
        _proposals.schedule(proposalId, CONFIG.AFTER_SUBMIT_DELAY());
    }

    /// @dev Executes a scheduled proposal.
    /// Checks if emergency mode is active and prevents execution if it is.
    /// @param proposalId The ID of the proposal to be executed.
    function execute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeActive(false);
        _proposals.execute(proposalId, CONFIG.AFTER_SCHEDULE_DELAY());
    }

    /// @dev Cancels all non-executed proposals.
    /// Only the governance contract can call this function.
    function cancelAllNonExecutedProposals() external {
        _checkGovernance(msg.sender);
        _proposals.cancelAll();
    }

    /// @dev Transfers ownership of the executor contract to a new owner.
    /// Only the admin executor can call this function.
    /// @param executor The address of the executor contract.
    /// @param owner The address of the new owner.
    function transferExecutorOwnership(address executor, address owner) external {
        _checkAdminExecutor(msg.sender);
        IOwnable(executor).transferOwnership(owner);
    }

    /// @dev Sets a new governance contract address.
    /// Only the admin executor can call this function.
    /// @param newGovernance The address of the new governance contract.
    function setGovernance(address newGovernance) external {
        _checkAdminExecutor(msg.sender);
        _setGovernance(newGovernance);
    }

    // ---
    // Emergency Protection Functionality
    // ---

    /// @dev Activates the emergency mode.
    /// Only the activation committee can call this function.
    function activateEmergencyMode() external {
        _emergencyProtection.checkActivationCommittee(msg.sender);
        _emergencyProtection.checkEmergencyModeActive(false);
        _emergencyProtection.activate();
    }

    /// @dev Executes a proposal during emergency mode.
    /// Checks if emergency mode is active and if the caller is part of the execution committee.
    /// @param proposalId The ID of the proposal to be executed.
    function emergencyExecute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeActive(true);
        _emergencyProtection.checkExecutionCommittee(msg.sender);
        _proposals.execute(proposalId, /* afterScheduleDelay */ Duration.wrap(0));
    }

    /// @dev Deactivates the emergency mode.
    /// If the emergency mode has not passed, only the admin executor can call this function.
    function deactivateEmergencyMode() external {
        _emergencyProtection.checkEmergencyModeActive(true);
        if (!_emergencyProtection.isEmergencyModePassed()) {
            _checkAdminExecutor(msg.sender);
        }
        _emergencyProtection.deactivate();
        _proposals.cancelAll();
    }

    /// @dev Resets the system after entering the emergency mode.
    /// Only the execution committee can call this function.
    function emergencyReset() external {
        _emergencyProtection.checkEmergencyModeActive(true);
        _emergencyProtection.checkExecutionCommittee(msg.sender);
        _emergencyProtection.deactivate();
        _setGovernance(CONFIG.EMERGENCY_GOVERNANCE());
        _proposals.cancelAll();
    }

    /// @dev Sets the parameters for the emergency protection functionality.
    /// Only the admin executor can call this function.
    /// @param activator The address of the activation committee.
    /// @param enactor The address of the execution committee.
    /// @param protectionDuration The duration of the protection period.
    /// @param emergencyModeDuration The duration of the emergency mode.
    function setEmergencyProtection(
        address activator,
        address enactor,
        Duration protectionDuration,
        Duration emergencyModeDuration
    ) external {
        _checkAdminExecutor(msg.sender);
        _emergencyProtection.setup(activator, enactor, protectionDuration, emergencyModeDuration);
    }

    /// @dev Checks if the emergency protection functionality is enabled.
    /// @return A boolean indicating if the emergency protection is enabled.
    function isEmergencyProtectionEnabled() external view returns (bool) {
        return _emergencyProtection.isEmergencyProtectionEnabled();
    }

    /// @dev Retrieves the current emergency state.
    /// @return res The EmergencyState struct containing the current emergency state.
    function getEmergencyState() external view returns (EmergencyState memory res) {
        res = _emergencyProtection.getEmergencyState();
    }

    // ---
    // Timelock View Methods
    // ---

    /// @dev Retrieves the address of the current governance contract.
    /// @return The address of the current governance contract.
    function getGovernance() external view returns (address) {
        return _governance;
    }

    /// @dev Retrieves the details of a proposal.
    /// @param proposalId The ID of the proposal.
    /// @return proposal The Proposal struct containing the details of the proposal.
    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        proposal = _proposals.get(proposalId);
    }

    /// @dev Retrieves the total number of proposals.
    /// @return count The total number of proposals.
    function getProposalsCount() external view returns (uint256 count) {
        count = _proposals.count();
    }

    /// @dev Retrieves the submission time of a proposal.
    /// @param proposalId The ID of the proposal.
    /// @return submittedAt The submission time of the proposal.
    function getProposalSubmissionTime(uint256 proposalId) external view returns (Timestamp submittedAt) {
        submittedAt = _proposals.getProposalSubmissionTime(proposalId);
    }

    /// @dev Checks if a proposal can be executed.
    /// @param proposalId The ID of the proposal.
    /// @return A boolean indicating if the proposal can be executed.
    function canExecute(uint256 proposalId) external view returns (bool) {
        return !_emergencyProtection.isEmergencyModeActivated()
            && _proposals.canExecute(proposalId, CONFIG.AFTER_SCHEDULE_DELAY());
    }

    /// @dev Checks if a proposal can be scheduled.
    /// @param proposalId The ID of the proposal.
    /// @return A boolean indicating if the proposal can be scheduled.
    function canSchedule(uint256 proposalId) external view returns (bool) {
        return _proposals.canSchedule(proposalId, CONFIG.AFTER_SUBMIT_DELAY());
    }

    // ---
    // Internal Methods
    // ---

    /// @dev Internal function to set the governance contract address.
    /// @param newGovernance The address of the new governance contract.
    function _setGovernance(address newGovernance) internal {
        address prevGovernance = _governance;
        if (newGovernance == prevGovernance || newGovernance == address(0)) {
            revert InvalidGovernance(newGovernance);
        }
        _governance = newGovernance;
        emit GovernanceSet(newGovernance);
    }

    /// @dev Internal function to check if the caller is the governance contract.
    /// @param account The address to check.
    function _checkGovernance(address account) internal view {
        if (_governance != account) {
            revert NotGovernance(account, _governance);
        }
    }
}
