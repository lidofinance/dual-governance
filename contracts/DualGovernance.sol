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
import {IDualGovernanceConfigProvider} from "./configuration/DualGovernanceConfigProvider.sol";
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

    event ConfigProviderSet(address newConfigProvider);

    ITimelock public immutable TIMELOCK;

    IDualGovernanceConfigProvider internal _configProvider;

    Proposers.State internal _proposers;
    Tiebreaker.Context internal _tiebreaker;
    DualGovernanceStateMachine.Context internal _stateMachine;

    address internal _resealCommittee;
    IResealManager internal _resealManager;

    constructor(address configProvider, address timelock, address escrowMasterCopy) {
        TIMELOCK = ITimelock(timelock);
        _configProvider = IDualGovernanceConfigProvider(configProvider);
        _stateMachine.initialize(escrowMasterCopy);
    }

    // ---
    // Proposals Flow
    // ---

    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId) {
        _stateMachine.activateNextState(_configProvider.getDualGovernanceStateMachineConfig());
        _proposers.checkProposer(msg.sender);
        if (!_stateMachine.canSubmitProposal()) {
            revert ProposalSubmissionBlocked();
        }
        Proposer memory proposer = _proposers.get(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function scheduleProposal(uint256 proposalId) external {
        _stateMachine.activateNextState(_configProvider.getDualGovernanceStateMachineConfig());
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
        _stateMachine.activateNextState(_configProvider.getDualGovernanceStateMachineConfig());
    }

    function setConfigProvider(address newConfigProvider) external {
        _checkAdminExecutor(msg.sender);
        if (newConfigProvider == address(0)) {
            revert InvalidConfig(address(0));
        }
        if (newConfigProvider == address(_configProvider)) {
            return;
        }
        _configProvider = IDualGovernanceConfigProvider(newConfigProvider);
        _stateMachine.signallingEscrow.setConfigProvider(newConfigProvider);
        emit ConfigProviderSet(newConfigProvider);
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
        return _stateMachine.getDynamicDelayDuration(_configProvider.getDualGovernanceStateMachineConfig());
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
        Tiebreaker.Config memory config = _configProvider.getTiebreakerConfig();
        _tiebreaker.setResealManager(resealManager);
        _tiebreaker.setTiebreakerCommittee(tiebreakerCommittee);
        _tiebreaker.setTiebreakerActivationTimeout(config, tiebreakerActivationTimeout);
        _tiebreaker.setSealableWithdrawalBlockers(config, sealableWithdrawalBlockers);
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
