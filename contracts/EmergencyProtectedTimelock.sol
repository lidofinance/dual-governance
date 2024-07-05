// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";

import {Proposal, Proposals, ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection, EmergencyState} from "./libraries/EmergencyProtection.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

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

    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _checkGovernance(msg.sender);
        newProposalId = _proposals.submit(executor, calls);
    }

    function schedule(uint256 proposalId) external returns (Timestamp submittedAt) {
        _checkGovernance(msg.sender);
        submittedAt = _proposals.schedule(proposalId, CONFIG.AFTER_SUBMIT_DELAY());
    }

    function execute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeActive(false);
        _proposals.execute(proposalId, CONFIG.AFTER_SCHEDULE_DELAY());
    }

    function cancelAllNonExecutedProposals() external {
        _checkGovernance(msg.sender);
        _proposals.cancelAll();
    }

    function transferExecutorOwnership(address executor, address owner) external {
        _checkAdminExecutor(msg.sender);
        IOwnable(executor).transferOwnership(owner);
    }

    function setGovernance(address newGovernance) external {
        _checkAdminExecutor(msg.sender);
        _setGovernance(newGovernance);
    }

    // ---
    // Emergency Protection Functionality
    // ---

    function activateEmergencyMode() external {
        _emergencyProtection.checkActivationCommittee(msg.sender);
        _emergencyProtection.checkEmergencyModeActive(false);
        _emergencyProtection.activate();
    }

    function emergencyExecute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeActive(true);
        _emergencyProtection.checkExecutionCommittee(msg.sender);
        _proposals.execute(proposalId, /* afterScheduleDelay */ Duration.wrap(0));
    }

    function deactivateEmergencyMode() external {
        _emergencyProtection.checkEmergencyModeActive(true);
        if (!_emergencyProtection.isEmergencyModePassed()) {
            _checkAdminExecutor(msg.sender);
        }
        _emergencyProtection.deactivate();
        _proposals.cancelAll();
    }

    function emergencyReset() external {
        _emergencyProtection.checkEmergencyModeActive(true);
        _emergencyProtection.checkExecutionCommittee(msg.sender);
        _emergencyProtection.deactivate();
        _setGovernance(CONFIG.EMERGENCY_GOVERNANCE());
        _proposals.cancelAll();
    }

    function setEmergencyProtection(
        address activator,
        address enactor,
        Duration protectionDuration,
        Duration emergencyModeDuration
    ) external {
        _checkAdminExecutor(msg.sender);
        _emergencyProtection.setup(activator, enactor, protectionDuration, emergencyModeDuration);
    }

    function isEmergencyProtectionEnabled() external view returns (bool) {
        return _emergencyProtection.isEmergencyProtectionEnabled();
    }

    function getEmergencyState() external view returns (EmergencyState memory res) {
        res = _emergencyProtection.getEmergencyState();
    }

    // ---
    // Timelock View Methods
    // ---

    function getGovernance() external view returns (address) {
        return _governance;
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        proposal = _proposals.get(proposalId);
    }

    function getProposalsCount() external view returns (uint256 count) {
        count = _proposals.count();
    }

    // ---
    // Proposals Lifecycle View Methods
    // ---

    function canExecute(uint256 proposalId) external view returns (bool) {
        return !_emergencyProtection.isEmergencyModeActivated()
            && _proposals.canExecute(proposalId, CONFIG.AFTER_SCHEDULE_DELAY());
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        return _proposals.canSchedule(proposalId, CONFIG.AFTER_SUBMIT_DELAY());
    }

    // ---
    // Internal Methods
    // ---

    function _setGovernance(address newGovernance) internal {
        address prevGovernance = _governance;
        if (newGovernance == prevGovernance || newGovernance == address(0)) {
            revert InvalidGovernance(newGovernance);
        }
        _governance = newGovernance;
        emit GovernanceSet(newGovernance);
    }

    function _checkGovernance(address account) internal view {
        if (_governance != account) {
            revert NotGovernance(account, _governance);
        }
    }
}
