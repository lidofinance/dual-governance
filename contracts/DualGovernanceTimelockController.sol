// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITimelock, ITimelockController} from "./interfaces/ITimelock.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";

import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {DualGovernanceState, Status as DualGovernanceStatus} from "./libraries/DualGovernanceState.sol";

contract DualGovernanceTimelockController is ITimelockController, ConfigurationProvider {
    using Proposers for Proposers.State;
    using DualGovernanceState for DualGovernanceState.State;

    event ProposalScheduled(uint256 proposalId);

    error ProposalNotReady();
    error ProposalNotSubmitted(uint256 proposalId);
    error ProposalNotScheduled();
    error SchedulingDisabled();
    error NotTimelock(address account);
    error ProposalsCreationSuspended();
    error ProposalsAdoptionSuspended();

    ITimelock public immutable TIMELOCK;

    address internal _tiebreakCommittee;
    Proposers.State internal _proposers;
    DualGovernanceState.State internal _state;
    mapping(uint256 proposalId => uint256 executableAfter) internal _scheduledProposals;

    constructor(address config, address timelock, address escrowMasterCopy) ConfigurationProvider(config) {
        TIMELOCK = ITimelock(timelock);
        _state.initialize(escrowMasterCopy);
    }

    function activateNextState() external {
        _state.activateNextState(CONFIG);
    }

    function setTiebreakCommittee(address committee) external {
        _checkAdminExecutor(msg.sender);
        _tiebreakCommittee = committee;
    }

    function scheduleProposal(uint256 proposalId) external {
        _state.activateNextState(CONFIG);
        if (!TIMELOCK.isEmergencyProtectionEnabled()) {
            revert SchedulingDisabled();
        }
        if (!_state.isProposalsAdoptionAllowed()) {
            revert ProposalsAdoptionSuspended();
        }
        if (!TIMELOCK.isProposalSubmitted(proposalId)) {
            revert ProposalNotSubmitted(proposalId);
        }
        _scheduledProposals[proposalId] = block.timestamp + CONFIG.AFTER_SCHEDULE_DELAY();
        emit ProposalScheduled(proposalId);
    }

    function onSubmitProposal(address sender, address executor) external {
        _checkTimelock(msg.sender);
        _state.activateNextState(CONFIG);
        _proposers.checkExecutor(sender, executor);

        if (!_state.isProposalsCreationAllowed()) {
            revert ProposalsCreationSuspended();
        }

        _state.setLastProposalCreationTimestamp();
    }

    function onExecuteProposal(address sender, uint256 proposalId) external {
        if (sender == _tiebreakCommittee) {
            _onExecuteFromTiebreakCommittee();
        } else if (TIMELOCK.isEmergencyProtectionEnabled()) {
            _onExecuteWhenSchedulingEnabled(proposalId);
        } else {
            _onExecute();
        }
    }

    function onCancelAllProposals(address sender) external {
        _checkTimelock(msg.sender);
        _proposers.checkAdminProposer(CONFIG, sender);
        _state.activateNextState(CONFIG);
    }

    // ---
    // View Methods
    // ---

    function currentState() external view returns (DualGovernanceStatus) {
        return _state.currentState();
    }

    function signallingEscrow() external view returns (address) {
        return address(_state.signallingEscrow);
    }

    function rageQuitEscrow() external view returns (address) {
        return address(_state.rageQuitEscrow);
    }

    function isTiebreak() external view returns (bool) {
        return _state.isTiebreak(CONFIG);
    }

    function isProposalsSubmissionAllowed() external view returns (bool) {
        return _state.isProposalsCreationAllowed();
    }

    function isProposalExecutionAllowed(uint256 proposalId) external view returns (bool) {
        if (TIMELOCK.isEmergencyProtectionEnabled()) {
            return _scheduledProposals[proposalId] != 0 && block.timestamp > _scheduledProposals[proposalId];
        }
        return _state.isProposalsAdoptionAllowed();
    }

    function getVetoSignallingState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt)
    {
        (isActive, duration, activatedAt, enteredAt) = _state.getVetoSignallingState(CONFIG);
    }

    function getVetoSignallingDeactivationState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 enteredAt)
    {
        (isActive, duration, enteredAt) = _state.getVetoSignallingDeactivationState(CONFIG);
    }

    function isSchedulingEnabled() external view returns (bool) {
        return TIMELOCK.isEmergencyProtectionEnabled();
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        return TIMELOCK.isEmergencyProtectionEnabled() && TIMELOCK.isProposalSubmitted(proposalId)
            && _state.isProposalsAdoptionAllowed() && TIMELOCK.isDelayPassed(proposalId)
            && _scheduledProposals[proposalId] == 0;
    }

    function isScheduled(uint256 proposalId) external view returns (bool) {
        return _scheduledProposals[proposalId] != 0;
    }

    // ---
    // Proposers & Executors Management
    // ---

    function registerProposer(address proposer, address executor) external {
        _checkAdminExecutor(msg.sender);
        _proposers.register(proposer, executor);
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

    function _onExecuteWhenSchedulingEnabled(uint256 proposalId) internal view {
        _checkTimelock(msg.sender);
        if (_scheduledProposals[proposalId] == 0) {
            revert ProposalNotScheduled();
        }
        if (_scheduledProposals[proposalId] > block.timestamp) {
            revert ProposalNotReady();
        }
    }

    function _onExecuteFromTiebreakCommittee() internal {
        _state.activateNextState(CONFIG);
        _state.checkTiebreak(CONFIG);
    }

    function _onExecute() internal {
        _checkTimelock(msg.sender);
        _state.activateNextState(CONFIG);

        if (!_state.isProposalsAdoptionAllowed()) {
            revert ProposalsAdoptionSuspended();
        }
    }
}
