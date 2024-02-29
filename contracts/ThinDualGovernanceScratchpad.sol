// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {DualGovernanceState, Status as DualGovernanceStatus} from "./libraries/DualGovernanceState.sol";

import {IOwnable} from "./interfaces/IOwnable.sol";
import {ConfigurationProvider, IConfiguration} from "./ConfigurationProvider.sol";

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

// ---
// Proposers
// ---
struct Proposer {
    bool isAdmin;
    address account;
    address executor;
}

struct ProposerData {
    address proposer;
    address executor;
    bool isAdmin;
}

library Proposers {
    using SafeCast for uint256;

    error NotProposer(address account);
    error NotAdminProposer(address account);
    error ProposerNotRegistered(address proposer);
    error ProposerAlreadyRegistered(address proposer);
    error InvalidAdminExecutor(address executor);
    error ExecutorNotRegistered(address account);
    error LastAdminProposerRemoval();

    event AdminExecutorSet(address indexed adminExecutor);
    event ProposerRegistered(address indexed proposer, address indexed executor);
    event ProposerUnregistered(address indexed proposer, address indexed executor);

    struct ExecutorData {
        uint8 proposerIndexOneBased; // indexed from 1. The count of executors is limited
        address executor;
    }

    struct State {
        address[] proposers;
        mapping(address proposer => ExecutorData) executors;
        mapping(address executor => uint256 usagesCount) executorRefsCounts;
    }

    function register(State storage self, address proposer, address executor) internal {
        if (self.executors[proposer].proposerIndexOneBased != 0) {
            revert ProposerAlreadyRegistered(proposer);
        }
        self.proposers.push(proposer);
        self.executors[proposer] = ExecutorData(self.proposers.length.toUint8(), executor);
        self.executorRefsCounts[executor] += 1;
        emit ProposerRegistered(proposer, executor);
    }

    function unregister(State storage self, IConfiguration config, address proposer) internal {
        uint256 proposerIndexToDelete;
        ExecutorData memory executorData = self.executors[proposer];
        unchecked {
            proposerIndexToDelete = executorData.proposerIndexOneBased - 1;
        }
        if (proposerIndexToDelete == type(uint256).max) {
            revert ProposerNotRegistered(proposer);
        }

        uint256 lastProposerIndex = self.proposers.length - 1;
        if (proposerIndexToDelete != lastProposerIndex) {
            self.proposers[proposerIndexToDelete] = self.proposers[lastProposerIndex];
        }
        self.proposers.pop();
        delete self.executors[proposer];

        address executor = executorData.executor;
        if (executor == config.ADMIN_EXECUTOR() && self.executorRefsCounts[executor] == 1) {
            revert LastAdminProposerRemoval();
        }

        self.executorRefsCounts[executor] -= 1;
        emit ProposerUnregistered(proposer, executor);
    }

    function all(State storage self) internal view returns (Proposer[] memory proposers) {
        proposers = new Proposer[](self.proposers.length);
        for (uint256 i = 0; i < proposers.length; ++i) {
            proposers[i] = get(self, self.proposers[i]);
        }
    }

    function get(State storage self, address account) internal view returns (Proposer memory proposer) {
        ExecutorData memory executorData = self.executors[account];
        if (executorData.proposerIndexOneBased == 0) {
            revert ProposerNotRegistered(account);
        }
        proposer.account = account;
        proposer.executor = executorData.executor;
    }

    function isProposer(State storage self, address account) internal view returns (bool) {
        return self.executors[account].proposerIndexOneBased != 0;
    }

    function isAdminProposer(State storage self, IConfiguration config, address account) internal view returns (bool) {
        ExecutorData memory executorData = self.executors[account];
        return executorData.proposerIndexOneBased != 0 && executorData.executor == config.ADMIN_EXECUTOR();
    }

    function isExecutor(State storage self, address account) internal view returns (bool) {
        return self.executorRefsCounts[account] > 0;
    }

    function checkProposer(State storage self, address account) internal view {
        if (!isProposer(self, account)) {
            revert NotProposer(account);
        }
    }

    function checkAdminProposer(State storage self, IConfiguration config, address account) internal view {
        checkProposer(self, account);
        if (!isAdminProposer(self, config, account)) {
            revert NotAdminProposer(account);
        }
    }
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

    function handleProposalAdoption() external {
        _checkTimelock(msg.sender);
        _state.activateNextState(CONFIG);
        if (!_state.isProposalsAdoptionAllowed()) {
            revert ProposalsAdoptionSuspended();
        }
    }

    function activateNextState() external {
        _state.activateNextState(CONFIG);
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
