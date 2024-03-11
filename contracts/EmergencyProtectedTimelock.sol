// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ITimelockController} from "./interfaces/ITimelock.sol";

import {Proposal, Proposals, ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection, EmergencyState} from "./libraries/EmergencyProtection.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

contract EmergencyProtectedTimelock is ConfigurationProvider {
    using Proposals for Proposals.State;
    using EmergencyProtection for EmergencyProtection.State;

    error SchedulingDisabled();
    error UnscheduledExecutionForbidden();

    event ProposalLaunched(address indexed proposer, address indexed executor, uint256 indexed proposalId);

    ITimelockController internal _controller;

    Proposals.State internal _proposals;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(address config) ConfigurationProvider(config) {}

    function submit(ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        address executor = _controller.handleProposalCreation(msg.sender);
        newProposalId = _proposals.submit(executor, calls);
        emit ProposalLaunched(msg.sender, executor, newProposalId);
    }

    function schedule(uint256 proposalId) external {
        if (!_emergencyProtection.isEmergencyProtectionEnabled()) {
            revert SchedulingDisabled();
        }
        _controller.handleProposalAdoption(msg.sender);
        _proposals.schedule(CONFIG, proposalId);
    }

    function executeScheduled(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeNotActivated();
        _proposals.executeScheduled(CONFIG, proposalId);
    }

    function executeSubmitted(uint256 proposalId) external {
        if (_emergencyProtection.isEmergencyProtectionEnabled()) {
            revert UnscheduledExecutionForbidden();
        }
        _emergencyProtection.checkEmergencyModeNotActivated();
        _controller.handleProposalAdoption(msg.sender);
        _proposals.executeSubmitted(CONFIG, proposalId);
    }

    function cancelAll() external {
        _controller.handleProposalsRevocation(msg.sender);
        _proposals.cancelAll();
    }

    function transferExecutorOwnership(address executor, address owner) external {
        _checkAdminExecutor(msg.sender);
        IOwnable(executor).transferOwnership(owner);
    }

    function setController(address controller) external {
        _checkAdminExecutor(msg.sender);
        _setController(controller);
    }

    // ---
    // Emergency Protection Functionality
    // ---

    function emergencyActivate() external {
        _emergencyProtection.checkEmergencyCommittee(msg.sender);
        _emergencyProtection.activate();
    }

    function emergencyExecute(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeActivated();
        _emergencyProtection.checkEmergencyCommittee(msg.sender);
        _proposals.executeScheduled(CONFIG, proposalId);
    }

    function emergencyDeactivate() external {
        if (!_emergencyProtection.isEmergencyModePassed()) {
            _checkAdminExecutor(msg.sender);
        }
        _emergencyProtection.deactivate();
        _proposals.cancelAll();
    }

    function emergencyReset() external {
        _emergencyProtection.checkEmergencyModeActivated();
        _emergencyProtection.checkEmergencyCommittee(msg.sender);
        _emergencyProtection.reset();
        _proposals.cancelAll();
        _setController(CONFIG.EMERGENCY_CONTROLLER());
    }

    function setEmergencyProtection(
        address committee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration
    ) external {
        _checkAdminExecutor(msg.sender);
        _emergencyProtection.setup(committee, protectionDuration, emergencyModeDuration);
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

    function getController() external view returns (address) {
        return address(_controller);
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        proposal = _proposals.get(proposalId);
    }

    function getProposalsCount() external view returns (uint256 count) {
        count = _proposals.count();
    }

    function getIsSchedulingEnabled() external view returns (bool) {
        return _emergencyProtection.isEmergencyProtectionEnabled();
    }

    // ---
    // Proposals Lifecycle View Methods
    // ---

    function canExecuteSubmitted(uint256 proposalId) external view returns (bool) {
        if (_emergencyProtection.isEmergencyModeActivated()) return false;
        if (_emergencyProtection.isEmergencyProtectionEnabled()) return false;
        return _controller.isProposalsAdoptionAllowed() && _proposals.canScheduleOrExecuteSubmitted(CONFIG, proposalId);
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        if (!_emergencyProtection.isEmergencyProtectionEnabled()) return false;
        return _controller.isProposalsAdoptionAllowed() && _proposals.canScheduleOrExecuteSubmitted(CONFIG, proposalId);
    }

    function canExecuteScheduled(uint256 proposalId) external view returns (bool) {
        if (_emergencyProtection.isEmergencyModeActivated()) return false;
        return _controller.isProposalsAdoptionAllowed() && _proposals.canExecuteScheduled(CONFIG, proposalId);
    }

    // ---
    // Internal Methods
    // ---

    function _setController(address controller) internal {
        address prevController = address(_controller);
        if (prevController != controller) {
            _controller = ITimelockController(controller);
        }
    }

    function _isProposalsAdoptionAllowed() internal view returns (bool) {
        address controller = address(_controller);
        return ITimelockController(controller).isProposalsAdoptionAllowed();
    }
}
