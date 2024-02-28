// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IOwnable} from "./interfaces/IOwnable.sol";

import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {Proposal, Proposals, ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection, EmergencyState} from "./libraries/EmergencyProtection.sol";

interface ITimelockController {
    function handleProposalCreation() external;
    function handleProposalAdoption() external;
    function handleProposalsRevocation() external;

    function isBlocked() external view returns (bool);
    function isProposalsAdoptionAllowed() external view returns (bool);
}

contract ControllerEnhancedTimelock {
    using Proposers for Proposers.State;
    using Proposals for Proposals.State;
    using EmergencyProtection for EmergencyProtection.State;

    error ControllerNotSet();
    error ControllerNotLocked();
    error NotTiebreakCommittee(address sender);
    error SchedulingDisabled();
    error UnscheduledExecutionForbidden();
    error InvalidAfterProposeDelayDuration(
        uint256 minDelayDuration, uint256 maxDelayDuration, uint256 afterProposeDelayDuration
    );
    error InvalidAfterScheduleDelayDuration(
        uint256 minDelayDuration, uint256 maxDelayDuration, uint256 afterScheduleDelayDuration
    );

    uint256 public immutable MIN_DELAY_DURATION = 2 days;
    uint256 public immutable MAX_DELAY_DURATION = 30 days;

    address internal _tiebreakCommittee;
    ITimelockController internal _controller;

    Proposers.State internal _proposers;
    Proposals.State internal _proposals;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(
        address adminProposer,
        address adminExecutor,
        uint256 minDelayDuration,
        uint256 maxDelayDuration,
        uint256 afterProposeDelay,
        uint256 afterScheduleDelay
    ) {
        MIN_DELAY_DURATION = minDelayDuration;
        MAX_DELAY_DURATION = maxDelayDuration;

        _proposers.register(adminProposer, adminExecutor);
        _proposers.setAdminExecutor(adminExecutor);

        _setDelays(afterProposeDelay, afterScheduleDelay);
    }

    function submit(ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _controllerHandleProposalCreation();
        Proposer memory proposer = _proposers.get(msg.sender);
        newProposalId = _proposals.submit(proposer.executor, calls);
    }

    function schedule(uint256 proposalId) external {
        if (!_emergencyProtection.isEmergencyProtectionEnabled()) {
            revert SchedulingDisabled();
        }
        _controllerHandleProposalAdoption();
        _proposals.schedule(proposalId);
    }

    function executeScheduled(uint256 proposalId) external {
        _emergencyProtection.checkEmergencyModeNotActivated();
        _proposals.executeScheduled(proposalId);
    }

    function executeSubmitted(uint256 proposalId) external {
        if (_emergencyProtection.isEmergencyProtectionEnabled()) {
            revert UnscheduledExecutionForbidden();
        }
        _emergencyProtection.checkEmergencyModeNotActivated();
        _controllerHandleProposalAdoption();
        _proposals.executeSubmitted(proposalId);
    }

    function cancelAll() external {
        _proposers.checkAdminProposer(msg.sender);
        _controllerHandleProposalsRevocation();
        _proposals.cancelAll();
    }

    function transferExecutorOwnership(address executor, address owner) external {
        _proposers.checkAdminExecutor(msg.sender);
        IOwnable(executor).transferOwnership(owner);
    }

    function setController(address controller) external {
        _proposers.checkAdminExecutor(msg.sender);
        _setController(controller);
    }

    function setDelays(uint256 afterProposeDelay, uint256 afterScheduleDelay) external {
        _proposers.checkAdminExecutor(msg.sender);
        _setDelays(afterProposeDelay, afterScheduleDelay);
    }

    // ---
    // Proposers & Executors Management
    // ---

    function setAdminExecutor(address adminExecutor) external {
        _proposers.checkAdminExecutor(msg.sender);
        _proposers.setAdminExecutor(adminExecutor);
    }

    function registerProposer(address proposer, address executor) external {
        _proposers.checkAdminExecutor(msg.sender);
        return _proposers.register(proposer, executor);
    }

    function unregisterProposer(address proposer) external {
        _proposers.checkAdminExecutor(msg.sender);
        _proposers.unregister(proposer);
    }

    function getAdminExecutor() external view returns (address) {
        return _proposers.adminExecutor;
    }

    function isAdminExecutor(address account) external view returns (bool) {
        return _proposers.isAdminExecutor(account);
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
        if (_proposals.canExecuteScheduled(proposalId)) {
            _proposals.executeScheduled(proposalId);
        } else {
            _proposals.executeSubmitted(proposalId);
        }
    }

    function emergencyDeactivate() external {
        if (!_emergencyProtection.isEmergencyModePassed()) {
            _proposers.checkAdminExecutor(msg.sender);
        }
        _emergencyProtection.deactivate();
        _proposals.cancelAll();
    }

    function emergencyResetController() external {
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
        _proposers.checkAdminExecutor(msg.sender);
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
        if (!_controller.isBlocked()) {
            revert ControllerNotLocked();
        }
        _executeScheduledOrSubmittedProposal(proposalId);
    }

    function setTiebreakCommittee(address committee) external {
        _proposers.checkAdminExecutor(msg.sender);
        _tiebreakCommittee = committee;
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
        return _isProposalsAdoptionAllowed() && _proposals.canScheduleOrExecuteSubmitted(proposalId);
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        if (_emergencyProtection.isEmergencyModeActivated()) return false;
        if (!_emergencyProtection.isEmergencyProtectionEnabled()) return false;
        return _isProposalsAdoptionAllowed() && _proposals.canScheduleOrExecuteSubmitted(proposalId);
    }

    function canExecuteScheduled(uint256 proposalId) external view returns (bool) {
        if (_emergencyProtection.isEmergencyModeActivated()) return false;
        return _isProposalsAdoptionAllowed() && _proposals.canExecuteScheduled(proposalId);
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

    function _setDelays(uint256 afterProposeDelay, uint256 afterScheduleDelay) internal {
        if (afterProposeDelay < MIN_DELAY_DURATION || afterProposeDelay > MAX_DELAY_DURATION) {
            revert InvalidAfterProposeDelayDuration(afterProposeDelay, MIN_DELAY_DURATION, MAX_DELAY_DURATION);
        }

        if (afterScheduleDelay < MIN_DELAY_DURATION || afterScheduleDelay > MAX_DELAY_DURATION) {
            revert InvalidAfterScheduleDelayDuration(afterScheduleDelay, MIN_DELAY_DURATION, MAX_DELAY_DURATION);
        }

        _proposals.setDelays(afterProposeDelay, afterScheduleDelay);
    }

    function _executeScheduledOrSubmittedProposal(uint256 proposalId) internal {
        if (_proposals.canExecuteScheduled(proposalId)) {
            _proposals.executeScheduled(proposalId);
        } else {
            _proposals.executeSubmitted(proposalId);
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
}
