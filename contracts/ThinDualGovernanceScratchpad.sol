// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {DualGovernanceState, Status as DualGovernanceStatus} from "./libraries/DualGovernanceState.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ConfigurationProvider} from "./ConfigurationProvider.sol";

import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {Proposal, Proposals, ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection, EmergencyState} from "./libraries/EmergencyProtection.sol";

interface ITimelock {
    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId);
    function cancelAll() external;
}

interface ITimelockController {
    function handleProposalAdoption() external;

    function isBlocked() external view returns (bool);
    function isProposalsAdoptionAllowed() external view returns (bool);
}

contract DualGovernance is ITimelockController, ConfigurationProvider {
    using Proposers for Proposers.State;
    using DualGovernanceState for DualGovernanceState.State;

    error NotTimelock(address account);
    error ProposalsCreationSuspended();
    error ProposalsAdoptionSuspended();

    ITimelock public immutable TIMELOCK;

    Proposers.State internal _proposers;
    DualGovernanceState.State internal _state;

    constructor(
        address timelock,
        address escrowMasterCopy,
        address config,
        address adminProposer
    ) ConfigurationProvider(config) {
        TIMELOCK = ITimelock(timelock);
        _state.initialize(escrowMasterCopy);
        _proposers.register(adminProposer, CONFIG.ADMIN_EXECUTOR());
    }

    function submit(ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _proposers.checkProposer(msg.sender);
        _state.activateNextState(CONFIG);

        if (!_state.isProposalsCreationAllowed()) {
            revert ProposalsCreationSuspended();
        }

        Proposer memory proposer = _proposers.get(msg.sender);
        newProposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function cancelAll() external {
        _proposers.checkAdminProposer(CONFIG, msg.sender);
        _state.activateNextState(CONFIG);
        _state.haltProposalsCreation();
        TIMELOCK.cancelAll();
    }

    function activateNextState() external {
        _state.activateNextState(CONFIG);
    }

    function handleProposalAdoption() external {
        _checkTimelock(msg.sender);
        _state.activateNextState(CONFIG);
        if (!_state.isProposalsAdoptionAllowed()) {
            revert ProposalsAdoptionSuspended();
        }
    }

    function currentState() external view returns (DualGovernanceStatus) {
        return _state.currentState();
    }

    function signallingEscrow() external view returns (address) {
        return address(_state.signallingEscrow);
    }

    function rageQuitEscrow() external view returns (address) {
        return address(_state.rageQuitEscrow);
    }

    function isBlocked() external view returns (bool) {
        return _state.isDeadLockedOrFrozen(CONFIG);
    }

    function isProposalsAdoptionAllowed() external view returns (bool) {
        return _state.isProposalsAdoptionAllowed();
    }

    // ---
    // Proposers & Executors Management
    // ---

    function registerProposer(address proposer, address executor) external {
        _checkAdminExecutor(msg.sender);
        return _proposers.register(proposer, executor);
    }

    function unregisterProposer(address proposer) external {
        _checkAdminExecutor(msg.sender);
        _proposers.unregister(CONFIG, proposer);
    }

    function getProposer(address account) external view returns (Proposer memory proposer) {
        proposer = _proposers.get(account);
    }

    function getProposers() external view returns (Proposer[] memory proposers) {
        proposers = _proposers.all();
    }

    function isProposer(address account) external view returns (bool) {
        return _proposers.isProposer(account);
    }

    function isExecutor(address account) external view returns (bool) {
        return _proposers.isExecutor(account);
    }

    // ---
    // Internal Helper Methods
    // ---

    function _checkTimelock(address account) internal view {
        if (account != address(TIMELOCK)) {
            revert NotTimelock(account);
        }
    }
}

contract Timelock is ITimelock, ConfigurationProvider {
    using Proposals for Proposals.State;
    using EmergencyProtection for EmergencyProtection.State;

    error NotGovernance(address account);
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

    address internal _governance;
    ITimelockController internal _controller;
    address internal _tiebreakCommittee;

    Proposers.State internal _proposers;
    Proposals.State internal _proposals;
    EmergencyProtection.State internal _emergencyProtection;

    constructor(
        address config,
        uint256 minDelayDuration,
        uint256 maxDelayDuration,
        uint256 afterProposeDelay,
        uint256 afterScheduleDelay
    ) ConfigurationProvider(config) {
        MIN_DELAY_DURATION = minDelayDuration;
        MAX_DELAY_DURATION = maxDelayDuration;

        _setDelays(afterProposeDelay, afterScheduleDelay);
    }

    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId) {
        _checkGovernance(msg.sender);
        newProposalId = _proposals.submit(executor, calls);
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
        _checkGovernance(msg.sender);
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

    function setDelays(uint256 afterProposeDelay, uint256 afterScheduleDelay) external {
        _checkAdminExecutor(msg.sender);
        _setDelays(afterProposeDelay, afterScheduleDelay);
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
        _setGovernance(CONFIG.EMERGENCY_GOVERNANCE());
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
        if (!_controller.isBlocked()) {
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

    function getGovernance() external view returns (address) {
        return _governance;
    }

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

    function _controllerHandleProposalAdoption() internal {
        address controller = address(_controller);
        if (controller != address(0)) {
            ITimelockController(controller).handleProposalAdoption();
        }
    }

    function _checkGovernance(address account) internal view {
        if (account != _governance) {
            revert NotGovernance(account);
        }
    }
}
