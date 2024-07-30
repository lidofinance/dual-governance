// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGovernance} from "./interfaces/ITimelock.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";
import {ITimelock, IGovernance} from "./interfaces/ITimelock.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";

import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {ExternalCall} from "./libraries/ExternalCalls.sol";
import {State, DualGovernanceStateMachine} from "./libraries/DualGovernanceStateMachine.sol";
import {Tiebreaker} from "./libraries/Tiebreaker.sol";

contract DualGovernance is IGovernance {
    using Proposers for Proposers.State;
    using Tiebreaker for Tiebreaker.Context;
    using DualGovernanceStateMachine for DualGovernanceStateMachine.Context;

    error NotDeadlock();
    error NotAdminExecutor();
    error InvalidConfig(address config);
    error NotResealCommitttee(address account);
    error ProposalSubmissionBlocked();
    error InvalidAdminExecutor(address value);
    error ProposalSchedulingBlocked(uint256 proposalId);
    error ResealIsNotAllowedInNormalState();
    error InvalidTiebreakerActivationTimeout(Duration value);
    error InvalidSealableWithdrawalBlockersCount(uint256 value);

    event ConfigProviderSet(address newConfigProvider);

    ITimelock public immutable TIMELOCK;

    uint256 public immutable MAX_SEALABLE_WITHDRAWAL_BLOCKERS;
    Duration public immutable MIN_TIEBREAKER_ACTIVATION_TIMEOUT;
    Duration public immutable MAX_TIEBREAKER_ACTIVATION_TIMEOUT;

    Proposers.State internal _proposers;
    Tiebreaker.Context internal _tiebreaker;
    DualGovernanceStateMachine.Context internal _stateMachine;

    address internal _resealCommittee;
    IResealManager internal _resealManager;

    constructor(
        uint256 maxSealableWithdrawalBlockers,
        Duration minTiebreakerActivationTimeout,
        Duration maxTiebreakerActivationTimeout,
        address timelock,
        address escrowMasterCopy
    ) {
        TIMELOCK = ITimelock(timelock);
        MAX_SEALABLE_WITHDRAWAL_BLOCKERS = maxSealableWithdrawalBlockers;
        MIN_TIEBREAKER_ACTIVATION_TIMEOUT = minTiebreakerActivationTimeout;
        MAX_TIEBREAKER_ACTIVATION_TIMEOUT = maxTiebreakerActivationTimeout;
        _stateMachine.initialize(escrowMasterCopy);
    }

    // ---
    // Proposals Flow
    // ---

    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId) {
        _stateMachine.activateNextState();
        _proposers.checkProposer(msg.sender);
        if (!_stateMachine.canSubmitProposal()) {
            revert ProposalSubmissionBlocked();
        }
        Proposer memory proposer = _proposers.get(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function scheduleProposal(uint256 proposalId) external {
        _stateMachine.activateNextState();
        ( /* id */ , /* status */, /* executor */, Timestamp submittedAt, /* scheduledAt */ ) =
            TIMELOCK.getProposalInfo(proposalId);
        if (!_stateMachine.canScheduleProposal(submittedAt)) {
            revert ProposalSchedulingBlocked(proposalId);
        }
        TIMELOCK.schedule(proposalId);
    }

    function cancelAllPendingProposals() external {
        _proposers.checkAdminProposer(TIMELOCK.getAdminExecutor(), msg.sender);
        TIMELOCK.cancelAllNonExecutedProposals();
    }

    function canSubmitProposal() public view returns (bool) {
        return _stateMachine.canSubmitProposal();
    }

    function canScheduleProposal(uint256 proposalId) external view returns (bool) {
        ( /* id */ , /* status */, /* executor */, Timestamp submittedAt, /* scheduledAt */ ) =
            TIMELOCK.getProposalInfo(proposalId);
        return _stateMachine.canScheduleProposal(submittedAt) && TIMELOCK.canSchedule(proposalId);
    }

    // ---
    // Dual Governance State
    // ---

    function activateNextState() external {
        _stateMachine.activateNextState();
    }

    function setDualGovernanceStateMachineConfig(DualGovernanceStateMachine.Config calldata config) external {
        _checkAdminExecutor(msg.sender);
        _stateMachine.setConfig(config);
    }

    function getVetoSignallingEscrow() external view returns (address) {
        return address(_stateMachine.signallingEscrow);
    }

    function getRageQuitEscrow() external view returns (address) {
        return address(_stateMachine.rageQuitEscrow);
    }

    function getCurrentState() external view returns (State currentState) {
        currentState = _stateMachine.getCurrentState();
    }

    function getCurrentStateContext() external view returns (DualGovernanceStateMachine.Context memory) {
        return _stateMachine.getCurrentContext();
    }

    function getDynamicDelayDuration() external view returns (Duration) {
        return _stateMachine.getDynamicDelayDuration();
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
        _proposers.unregister(TIMELOCK.getAdminExecutor(), proposer);
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
    // Tiebreaker Protection
    // ---

    function setupTiebreaker(
        address resealManager,
        address tiebreakerCommittee,
        Duration tiebreakerActivationTimeout,
        address[] memory sealableWithdrawalBlockers
    ) external {
        if (
            tiebreakerActivationTimeout > MIN_TIEBREAKER_ACTIVATION_TIMEOUT
                || tiebreakerActivationTimeout < MAX_TIEBREAKER_ACTIVATION_TIMEOUT
        ) {
            revert InvalidTiebreakerActivationTimeout(tiebreakerActivationTimeout);
        }
        if (sealableWithdrawalBlockers.length > MAX_SEALABLE_WITHDRAWAL_BLOCKERS) {
            revert InvalidSealableWithdrawalBlockersCount(sealableWithdrawalBlockers.length);
        }
        _tiebreaker.setResealManager(resealManager);
        _tiebreaker.setTiebreakerCommittee(tiebreakerCommittee);
        _tiebreaker.setTiebreakerActivationTimeout(tiebreakerActivationTimeout);
        _tiebreaker.setSealableWithdrawalBlockers(sealableWithdrawalBlockers);
    }

    function tiebreakerResumeSealable(address sealable) external {
        Tiebreaker.Context memory tiebreaker = _tiebreaker;
        tiebreaker.checkTiebreakerCommittee(msg.sender);
        tiebreaker.checkTie(_stateMachine.getCurrentState(), _stateMachine.getNormalOrVetoCooldownStateExitedAt());
        tiebreaker.resumeSealable(sealable);
    }

    function tiebreakerScheduleProposal(uint256 proposalId) external {
        Tiebreaker.Context memory tiebreaker = _tiebreaker;
        tiebreaker.checkTiebreakerCommittee(msg.sender);
        tiebreaker.checkTie(_stateMachine.getCurrentState(), _stateMachine.getNormalOrVetoCooldownStateExitedAt());
        TIMELOCK.schedule(proposalId);
    }

    // ---
    // Reseal executor
    // ---

    function resealSealables(address[] memory sealables) external {
        if (msg.sender != _resealCommittee) {
            revert NotResealCommitttee(msg.sender);
        }
        if (_stateMachine.getCurrentState() == State.Normal) {
            revert ResealIsNotAllowedInNormalState();
        }
        _resealManager.reseal(sealables);
    }

    function setReseal(address resealManager, address resealCommittee) external {
        _checkAdminExecutor(msg.sender);
        _resealCommittee = resealCommittee;
        _resealManager = IResealManager(resealManager);
    }

    function _checkAdminExecutor(address account) internal view {
        if (TIMELOCK.getAdminExecutor() != account) {
            revert InvalidAdminExecutor(account);
        }
    }
}
