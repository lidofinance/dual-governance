// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";
import {ITimelock, IGovernance} from "./interfaces/ITimelock.sol";
import {ISealable} from "./interfaces/ISealable.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";
import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";
import {State, DualGovernanceState} from "./libraries/DualGovernanceState.sol";
import {TiebreakerProtection} from "./libraries/TiebreakerProtection.sol";

contract DualGovernance is IGovernance, ConfigurationProvider {
    using Proposers for Proposers.State;
    using DualGovernanceState for DualGovernanceState.Store;
    using TiebreakerProtection for TiebreakerProtection.Tiebreaker;

    event ProposalScheduled(uint256 proposalId);

    error NotResealCommitttee(address account);

    ITimelock public immutable TIMELOCK;

    TiebreakerProtection.Tiebreaker internal _tiebreaker;
    Proposers.State internal _proposers;
    DualGovernanceState.Store internal _dgState;
    EmergencyProtection.State internal _emergencyProtection;
    address internal _resealCommittee;
    IResealManager internal _resealManager;

    constructor(
        address config,
        address timelock,
        address escrowMasterCopy,
        address adminProposer
    ) ConfigurationProvider(config) {
        TIMELOCK = ITimelock(timelock);

        _dgState.initialize(escrowMasterCopy);
        _proposers.register(adminProposer, CONFIG.ADMIN_EXECUTOR());
    }

    function submitProposal(ExecutorCall[] calldata calls) external returns (uint256 proposalId) {
        _proposers.checkProposer(msg.sender);
        _dgState.activateNextState(CONFIG.getDualGovernanceConfig());
        _dgState.checkProposalsCreationAllowed();
        Proposer memory proposer = _proposers.get(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function scheduleProposal(uint256 proposalId) external {
        _dgState.activateNextState(CONFIG.getDualGovernanceConfig());

        Timestamp proposalSubmissionTime = TIMELOCK.getProposalSubmissionTime(proposalId);
        _dgState.checkCanScheduleProposal(proposalSubmissionTime);

        TIMELOCK.schedule(proposalId);

        emit ProposalScheduled(proposalId);
    }

    function cancelAllPendingProposals() external {
        _proposers.checkAdminProposer(CONFIG, msg.sender);
        TIMELOCK.cancelAllNonExecutedProposals();
    }

    function getVetoSignallingEscrow() external view returns (address) {
        return address(_dgState.signallingEscrow);
    }

    function getRageQuitEscrow() external view returns (address) {
        return address(_dgState.rageQuitEscrow);
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        return _dgState.isProposalsAdoptionAllowed() && TIMELOCK.canSchedule(proposalId);
    }

    // ---
    // Dual Governance State
    // ---

    function activateNextState() external {
        _dgState.activateNextState(CONFIG.getDualGovernanceConfig());
    }

    function getCurrentState() external view returns (State) {
        return _dgState.currentState();
    }

    function getVetoSignallingState()
        external
        view
        returns (bool isActive, Duration duration, Timestamp activatedAt, Timestamp enteredAt)
    {
        (isActive, duration, activatedAt, enteredAt) = _dgState.getVetoSignallingState(CONFIG.getDualGovernanceConfig());
    }

    function getVetoSignallingDeactivationState()
        external
        view
        returns (bool isActive, Duration duration, Timestamp enteredAt)
    {
        (isActive, duration, enteredAt) = _dgState.getVetoSignallingDeactivationState(CONFIG.getDualGovernanceConfig());
    }

    function getVetoSignallingDuration() external view returns (Duration) {
        return _dgState.getVetoSignallingDuration(CONFIG.getDualGovernanceConfig());
    }

    function isSchedulingEnabled() external view returns (bool) {
        return _dgState.isProposalsAdoptionAllowed();
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
        _dgState.checkTiebreak(CONFIG);
        _tiebreaker.resumeSealable(sealable);
    }

    function tiebreakerScheduleProposal(uint256 proposalId) external {
        _tiebreaker.checkTiebreakerCommittee(msg.sender);
        _dgState.checkTiebreak(CONFIG);
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
        _dgState.checkResealState();
        _resealManager.reseal(sealables);
    }

    function setReseal(address resealManager, address resealCommittee) external {
        _checkAdminExecutor(msg.sender);
        _resealCommittee = resealCommittee;
        _resealManager = IResealManager(resealManager);
    }
}
