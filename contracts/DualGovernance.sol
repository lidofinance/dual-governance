// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITimelock, IGovernance} from "./interfaces/ITimelock.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";
import {IConfigurableTimelock, IGovernance} from "./interfaces/ITimelock.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";

import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {ExternalCall} from "./libraries/ExternalCalls.sol";
import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";
import {State, DualGovernanceStateMachine} from "./libraries/DualGovernanceStateMachine.sol";
import {TiebreakerProtection} from "./libraries/TiebreakerProtection.sol";

import {AdminExecutorConfigUtils} from "./configuration/AdminExecutorConfig.sol";
import {IDualGovernanceConfig} from "./configuration/DualGovernanceConfig.sol";

contract DualGovernance is IGovernance {
    using Proposers for Proposers.State;
    using TiebreakerProtection for TiebreakerProtection.Tiebreaker;
    using DualGovernanceStateMachine for DualGovernanceStateMachine.Context;

    error NotDeadlock();
    error NotResealCommitttee(address account);
    error ProposalSubmissionBlocked();
    error ProposalSchedulingBlocked(uint256 proposalId);
    error ResealIsNotAllowedInNormalState();

    IConfigurableTimelock public immutable TIMELOCK;
    IDualGovernanceConfig public immutable CONFIG;

    Proposers.State internal _proposers;
    DualGovernanceStateMachine.Context internal _stateMachine;
    EmergencyProtection.State internal _emergencyProtection;
    address internal _resealCommittee;
    IResealManager internal _resealManager;
    TiebreakerProtection.Tiebreaker internal _tiebreaker;

    constructor(address config, address timelock, address escrowMasterCopy, address adminProposer) {
        TIMELOCK = IConfigurableTimelock(timelock);
        CONFIG = IDualGovernanceConfig(config);

        _proposers.register(adminProposer, TIMELOCK.CONFIG().ADMIN_EXECUTOR());
        _stateMachine.initialize(escrowMasterCopy);
    }

    // ---
    // Proposals Flow
    // ---

    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId) {
        _proposers.checkProposer(msg.sender);
        _stateMachine.activateNextState(CONFIG.getDualGovernanceStateMachineConfig());
        if (!_stateMachine.canSubmitProposal()) {
            revert ProposalSubmissionBlocked();
        }
        Proposer memory proposer = _proposers.get(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function scheduleProposal(uint256 proposalId) external {
        _stateMachine.activateNextState(CONFIG.getDualGovernanceStateMachineConfig());
        ( /* id */ , /* status */, /* executor */, Timestamp submittedAt, /* scheduledAt */ ) =
            TIMELOCK.getProposalInfo(proposalId);
        if (!_stateMachine.canScheduleProposal(submittedAt)) {
            revert ProposalSchedulingBlocked(proposalId);
        }
        TIMELOCK.schedule(proposalId);
    }

    function cancelAllPendingProposals() external {
        _proposers.checkAdminProposer(TIMELOCK.CONFIG().getAdminExecutionConfig(), msg.sender);
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

    function getVetoSignallingEscrow() external view returns (address) {
        return address(_stateMachine.signallingEscrow);
    }

    function getRageQuitEscrow() external view returns (address) {
        return address(_stateMachine.rageQuitEscrow);
    }

    function activateNextState() external {
        _stateMachine.activateNextState(CONFIG.getDualGovernanceStateMachineConfig());
    }

    function getCurrentState() external view returns (State currentState) {
        currentState = _stateMachine.getCurrentState();
    }

    function getCurrentStateContext() external view returns (DualGovernanceStateMachine.Context memory) {
        return _stateMachine.getCurrentContext();
    }

    function getDynamicDelayDuration() external view returns (Duration) {
        return _stateMachine.getDynamicDelayDuration(CONFIG.getDualGovernanceStateMachineConfig());
    }

    // ---
    // Proposers & Executors Management
    // ---

    function registerProposer(address proposer, address executor) external {
        AdminExecutorConfigUtils.checkAdminExecutor(TIMELOCK.CONFIG(), msg.sender);
        _proposers.register(proposer, executor);
    }

    function unregisterProposer(address proposer) external {
        AdminExecutorConfigUtils.checkAdminExecutor(TIMELOCK.CONFIG(), msg.sender);
        _proposers.unregister(TIMELOCK.CONFIG().getAdminExecutionConfig(), proposer);
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

    function tiebreakerResumeSealable(address sealable) external {
        _tiebreaker.checkTiebreakerCommittee(msg.sender);
        if (!_stateMachine.isDeadlock(CONFIG.getTiebreakerConfig())) {
            revert NotDeadlock();
        }
        _tiebreaker.resumeSealable(sealable);
    }

    function tiebreakerScheduleProposal(uint256 proposalId) external {
        _tiebreaker.checkTiebreakerCommittee(msg.sender);
        if (!_stateMachine.isDeadlock(CONFIG.getTiebreakerConfig())) {
            revert NotDeadlock();
        }
        TIMELOCK.schedule(proposalId);
    }

    function setTiebreakerProtection(address newTiebreaker, address resealManager) external {
        AdminExecutorConfigUtils.checkAdminExecutor(TIMELOCK.CONFIG(), msg.sender);
        _tiebreaker.setTiebreaker(newTiebreaker, resealManager);
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
        AdminExecutorConfigUtils.checkAdminExecutor(TIMELOCK.CONFIG(), msg.sender);
        _resealCommittee = resealCommittee;
        _resealManager = IResealManager(resealManager);
    }
}
