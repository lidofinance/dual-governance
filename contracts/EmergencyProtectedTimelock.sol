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

    error ControllerNotSet();
    error ControllerNotLocked();
    error NotGovernance(address account);
    error NotTiebreakCommittee(address sender);
    error SchedulingDisabled();
    error UnscheduledExecutionForbidden();

    ITimelockController internal _controller;
    address internal _tiebreakCommittee;
    address internal _governance;

    Proposals.State internal _proposals;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(address config) ConfigurationProvider(config) {}

    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _checkGovernance(msg.sender);
        _controllerHandleProposalCreation();
        newProposalId = _proposals.submit(executor, calls);
    }

    function schedule(uint256 proposalId) external {
        if (!_emergencyProtection.isEmergencyProtectionEnabled()) {
            revert SchedulingDisabled();
        }
        _controllerHandleProposalAdoption();
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
        _controllerHandleProposalAdoption();
        _proposals.executeSubmitted(CONFIG, proposalId);
    }

    function cancelAll() external {
        _checkGovernance(msg.sender);
        _controllerHandleProposalsRevocation();
        _proposals.cancelAll();
    }

    function transferExecutorOwnership(address executor, address owner) external {
        _checkAdminExecutor(msg.sender);
        IOwnable(executor).transferOwnership(owner);
    }

    function setGovernance(address governance) external {
        _checkAdminExecutor(msg.sender);
        _setGovernance(governance);
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
        _setController(address(0));
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
    // Tiebreak Protection
    // ---

    function tiebreakExecute(uint256 proposalId) external {
        if (msg.sender != _tiebreakCommittee) {
            revert NotTiebreakCommittee(msg.sender);
        }
        if (address(_controller) == address(0)) {
            revert ControllerNotSet();
        }
        if (!_controller.isTiebreak()) {
            revert ControllerNotLocked();
        }
        _executeScheduledOrSubmittedProposal(proposalId);
    }

    function setTiebreakCommittee(address committee) external {
        _checkAdminExecutor(msg.sender);
        _tiebreakCommittee = committee;
    }

    // ---
    // Timelock View Methods
    // ---

    function getController() external view returns (address) {
        return address(_controller);
    }

    function getGovernance() external view returns (address) {
        return address(_governance);
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
        return _isProposalsAdoptionAllowed() && _proposals.canScheduleOrExecuteSubmitted(CONFIG, proposalId);
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        if (!_emergencyProtection.isEmergencyProtectionEnabled()) return false;
        return _isProposalsAdoptionAllowed() && _proposals.canScheduleOrExecuteSubmitted(CONFIG, proposalId);
    }

    function canExecuteScheduled(uint256 proposalId) external view returns (bool) {
        if (_emergencyProtection.isEmergencyModeActivated()) return false;
        return _isProposalsAdoptionAllowed() && _proposals.canExecuteScheduled(CONFIG, proposalId);
    }

    // ---
    // Internal Methods
    // ---

    function _setGovernance(address governance) internal {
        address prevGovernance = _governance;
        if (prevGovernance != governance) {
            _governance = governance;
        }
    }

    function _setController(address controller) internal {
        address prevController = address(_controller);
        if (prevController != controller) {
            _controller = ITimelockController(controller);
        }
    }

    function _executeScheduledOrSubmittedProposal(uint256 proposalId) internal {
        if (_proposals.canExecuteScheduled(CONFIG, proposalId)) {
            _proposals.executeScheduled(CONFIG, proposalId);
        } else {
            _proposals.executeSubmitted(CONFIG, proposalId);
        }
    }

    function _isProposalsAdoptionAllowed() internal view returns (bool) {
        address controller = address(_controller);
        return controller == address(0) || ITimelockController(controller).isProposalsAdoptionAllowed();
    }

    function _controllerHandleProposalCreation() internal {
        address controller = address(_controller);
        if (controller != address(0)) {
            ITimelockController(controller).handleProposalCreation();
        }
    }

    function _controllerHandleProposalAdoption() internal {
        address controller = address(_controller);
        if (controller != address(0)) {
            ITimelockController(controller).handleProposalAdoption();
        }
    }

    function _controllerHandleProposalsRevocation() internal {
        address controller = address(_controller);
        if (controller != address(0)) {
            ITimelockController(controller).handleProposalsRevocation();
        }
    }

    function _checkGovernance(address account) internal view {
        if (account != _governance) {
            revert NotGovernance(account);
        }
    }
}
