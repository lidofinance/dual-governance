// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITimelock, IGovernance} from "./interfaces/ITimelock.sol";
import {ISealable} from "./interfaces/ISealable.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";
import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {ExecutorCall} from "./libraries/Proposals.sol";
import {DualGovernanceState, State as GovernanceState} from "./libraries/DualGovernanceState.sol";
import {TiebreakerProtection} from "./libraries/TiebreakerProtection.sol";

contract DualGovernance is IGovernance, ConfigurationProvider {
    using Proposers for Proposers.State;
    using DualGovernanceState for DualGovernanceState.Store;
    using TiebreakerProtection for TiebreakerProtection.Tiebreaker;

    event ProposalScheduled(uint256 proposalId);

    ITimelock public immutable TIMELOCK;

    TiebreakerProtection.Tiebreaker internal _tiebreaker;
    Proposers.State internal _proposers;
    DualGovernanceState.Store internal _dgState;

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
        _dgState.activateNextState(CONFIG);
        _dgState.checkProposalsCreationAllowed();
        _dgState.setLastProposalCreationTimestamp();
        Proposer memory proposer = _proposers.get(msg.sender);
        proposalId = TIMELOCK.submit(proposer.executor, calls);
    }

    function schedule(uint256 proposalId) external {
        _dgState.activateNextState(CONFIG);
        _dgState.checkProposalsAdoptionAllowed();
        TIMELOCK.schedule(proposalId);
        emit ProposalScheduled(proposalId);
    }

    function cancelAll() external {
        _proposers.checkAdminProposer(CONFIG, msg.sender);
        TIMELOCK.cancelAll();
    }

    function signallingEscrow() external view returns (address) {
        return address(_dgState.signallingEscrow);
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        return _dgState.isProposalsAdoptionAllowed() && TIMELOCK.canSchedule(proposalId);
    }

    // ---
    // Dual Governance State
    // ---

    function activateNextState() external {
        _dgState.activateNextState(CONFIG);
    }

    function currentState() external view returns (GovernanceState) {
        return _dgState.currentState();
    }

    function getVetoSignallingState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt)
    {
        (isActive, duration, activatedAt, enteredAt) = _dgState.getVetoSignallingState(CONFIG);
    }

    function getVetoSignallingDeactivationState()
        external
        view
        returns (bool isActive, uint256 duration, uint256 enteredAt)
    {
        (isActive, duration, enteredAt) = _dgState.getVetoSignallingDeactivationState(CONFIG);
    }

    function getVetoSignallingDuration() external view returns (uint256) {
        return _dgState.getVetoSignallingDuration(CONFIG);
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

    function tiebreakerApproveProposal(uint256 proposalId) external {
        _tiebreaker.checkTiebreakerCommittee(msg.sender);
        _dgState.checkTiebreak(CONFIG);
        _tiebreaker.approveProposal(proposalId);
    }

    function tiebreakerApproveSealableResume(address sealable) external {
        _tiebreaker.checkTiebreakerCommittee(msg.sender);
        _dgState.checkTiebreak(CONFIG);
        Proposer memory proposer = _proposers.get(msg.sender);
        ExecutorCall[] memory calls = new ExecutorCall[](1);
        calls[0] = ExecutorCall(sealable, 0, abi.encodeWithSelector(ISealable.resume.selector));
        uint256 proposalId = TIMELOCK.submit(proposer.executor, calls);
        _tiebreaker.approveSealableResume(proposalId, sealable);
    }

    function tiebreakerSchedule(uint256 proposalId) external {
        _dgState.checkTiebreak(CONFIG);
        _tiebreaker.canSchedule(proposalId);
        TIMELOCK.schedule(proposalId);
    }

    function setTiebreakerProtection(address newTiebreaker) external {
        _checkAdminExecutor(msg.sender);
        if (_tiebreaker.tiebreaker != address(0)) {
            _proposers.unregister(CONFIG, _tiebreaker.tiebreaker);
        }
        _proposers.register(newTiebreaker, CONFIG.ADMIN_EXECUTOR()); // TODO: check what executor should be. Reseal executor?
        _tiebreaker.setTiebreaker(newTiebreaker);
    }
}
