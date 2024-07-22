// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITimelock, IGovernance} from "./interfaces/ITimelock.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";
import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {ExternalCall} from "./libraries/ExternalCalls.sol";
import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";
import {Status, DualGovernanceStateMachine} from "./libraries/DualGovernanceStateMachine.sol";
import {TiebreakerProtection} from "./libraries/TiebreakerProtection.sol";

contract DualGovernance is IGovernance, ConfigurationProvider {
    using Proposers for Proposers.State;
    using TiebreakerProtection for TiebreakerProtection.Tiebreaker;
    using DualGovernanceStateMachine for DualGovernanceStateMachine.State;

    error NotTiebreak();
    error NotResealCommitttee(address account);
    error ProposalSubmissionBlocked();
    error ProposalSchedulingBlocked(uint256 proposalId);
    error ResealIsNotAllowedInNormalState();

    ITimelock public immutable TIMELOCK;

    Proposers.State internal _proposers;
    DualGovernanceStateMachine.State internal _stateMachine;
    EmergencyProtection.State internal _emergencyProtection;
    address internal _resealCommittee;
    IResealManager internal _resealManager;
    TiebreakerProtection.Tiebreaker internal _tiebreaker;

    constructor(
        address config,
        address timelock,
        address escrowMasterCopy,
        address adminProposer
    ) ConfigurationProvider(config) {
        TIMELOCK = ITimelock(timelock);

        _stateMachine.initialize(escrowMasterCopy);
        _proposers.register(adminProposer, CONFIG.ADMIN_EXECUTOR());
    }

    // ---
    // Proposals Flow
    // ---

    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId) {
        _proposers.checkProposer(msg.sender);
        _stateMachine.activateNextState(CONFIG.getDualGovernanceConfig());
        if (!_stateMachine.canSubmitProposal()) {
            revert ProposalSubmissionBlocked();
        }
        Proposer memory proposer = _proposers.get(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function scheduleProposal(uint256 proposalId) external {
        _stateMachine.activateNextState(CONFIG.getDualGovernanceConfig());
        ( /* id */ , /* status */, /* executor */, Timestamp submittedAt, /* scheduledAt */ ) =
            TIMELOCK.getProposalInfo(proposalId);
        if (!_stateMachine.canScheduleProposal(submittedAt)) {
            revert ProposalSchedulingBlocked(proposalId);
        }
        TIMELOCK.schedule(proposalId);
    }

    function cancelAllPendingProposals() external {
        _proposers.checkAdminProposer(CONFIG, msg.sender);
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
        _stateMachine.activateNextState(CONFIG.getDualGovernanceConfig());
    }

    function getCurrentStatus() external view returns (Status) {
        return _stateMachine.getCurrentStatus();
    }

    function getCurrentState() external view returns (DualGovernanceStateMachine.State memory) {
        return _stateMachine.getCurrentState();
    }

    function getDynamicTimelockDuration() external view returns (Duration) {
        return _stateMachine.getDynamicTimelockDuration(CONFIG.getDualGovernanceConfig());
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
    // Tiebreaker Protection
    // ---

    function tiebreakerResumeSealable(address sealable) external {
        _tiebreaker.checkTiebreakerCommittee(msg.sender);
        if (!_stateMachine.isDeadlock(CONFIG.getTiebreakConfig())) {
            revert NotTiebreak();
        }
        _tiebreaker.resumeSealable(sealable);
    }

    function tiebreakerScheduleProposal(uint256 proposalId) external {
        _tiebreaker.checkTiebreakerCommittee(msg.sender);
        if (!_stateMachine.isDeadlock(CONFIG.getTiebreakConfig())) {
            revert NotTiebreak();
        }
        TIMELOCK.schedule(proposalId);
    }

    function setTiebreakerProtection(address newTiebreaker, address resealManager) external {
        _checkAdminExecutor(msg.sender);
        _tiebreaker.setTiebreaker(newTiebreaker, resealManager);
    }

    // ---
    // Reseal executor
    // ---

    function resealSealables(address[] memory sealables) external {
        if (msg.sender != _resealCommittee) {
            revert NotResealCommitttee(msg.sender);
        }
        if (_stateMachine.getCurrentStatus() == Status.Normal) {
            revert ResealIsNotAllowedInNormalState();
        }
        _resealManager.reseal(sealables);
    }

    function setReseal(address resealManager, address resealCommittee) external {
        _checkAdminExecutor(msg.sender);
        _resealCommittee = resealCommittee;
        _resealManager = IResealManager(resealManager);
    }
}
