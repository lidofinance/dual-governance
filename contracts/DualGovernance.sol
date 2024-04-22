// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITimelock, IGovernance} from "./interfaces/ITimelock.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";
import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";
import {
    State,
    DualGovernanceState,
    DualGovernanceStateTransitions,
    DualGovernanceStateViews
} from "./libraries/DualGovernanceState.sol";

contract DualGovernance is IGovernance, ConfigurationProvider {
    using Proposers for Proposers.State;
    using DualGovernanceStateViews for DualGovernanceState;
    using DualGovernanceStateTransitions for DualGovernanceState;

    event TiebreakerSet(address tiebreakCommittee);
    event ProposalScheduled(uint256 proposalId);

    error ProposalNotExecutable(uint256 proposalId);
    error NotTiebreaker(address account, address tiebreakCommittee);

    ITimelock public immutable TIMELOCK;

    address internal _tiebreaker;

    Proposers.State internal _proposers;
    DualGovernanceState internal _dgState;
    EmergencyProtection.State internal _emergencyProtection;
    mapping(uint256 proposalId => uint256 executableAfter) internal _scheduledProposals;

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

    function submit(ExecutorCall[] calldata calls) external returns (uint256 proposalId) {
        _proposers.checkProposer(msg.sender);
        _dgState.activateNextState(CONFIG.getDualGovernanceConfig());
        _dgState.checkProposalsCreationAllowed();
        _dgState.setLastProposalCreationTimestamp();
        Proposer memory proposer = _proposers.get(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function schedule(uint256 proposalId) external {
        _dgState.activateNextState(CONFIG.getDualGovernanceConfig());
        _dgState.checkProposalsAdoptionAllowed();
        TIMELOCK.schedule(proposalId);
        emit ProposalScheduled(proposalId);
    }

    function cancelAllPendingProposals() external {
        _proposers.checkAdminProposer(CONFIG, msg.sender);
        TIMELOCK.cancelAllNonExecutedProposals();
    }

    function vetoSignallingEscrow() external view returns (address) {
        return address(_dgState.signallingEscrow);
    }

    function isScheduled(uint256 proposalId) external view returns (bool) {
        return _scheduledProposals[proposalId] != 0;
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

    function currentState() external view returns (State) {
        return _dgState.currentState();
    }

    function getVetoSignallingState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt)
    {
        (isActive, duration, activatedAt, enteredAt) = _dgState.getVetoSignallingState(CONFIG.getDualGovernanceConfig());
    }

    function getVetoSignallingDeactivationState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 enteredAt)
    {
        (isActive, duration, enteredAt) = _dgState.getVetoSignallingDeactivationState(CONFIG.getDualGovernanceConfig());
    }

    function getVetoSignallingDuration() external view returns (uint256) {
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

    function tiebreakerSchedule(uint256 proposalId) external {
        _checkTiebreakerCommittee(msg.sender);
        _dgState.checkTiebreak(CONFIG);
        TIMELOCK.schedule(proposalId);
    }

    function setTiebreakerCommittee(address newTiebreaker) external {
        _checkAdminExecutor(msg.sender);
        address oldTiebreaker = _tiebreaker;
        if (newTiebreaker != oldTiebreaker) {
            _tiebreaker = newTiebreaker;
            emit TiebreakerSet(newTiebreaker);
        }
    }

    // ---
    // Internal Helper Methods
    // ---

    function _checkTiebreakerCommittee(address account) internal view {
        if (account != _tiebreaker) {
            revert NotTiebreaker(account, _tiebreaker);
        }
    }
}
