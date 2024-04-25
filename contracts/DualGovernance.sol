// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITimelock, IGovernance} from "./interfaces/ITimelock.sol";

import {ConfigurationProvider} from "./ConfigurationProvider.sol";
import {Proposers, Proposer} from "./libraries/Proposers.sol";
import {ExecutorCall} from "./libraries/Proposals.sol";
import {EmergencyProtection} from "./libraries/EmergencyProtection.sol";
import {DualGovernanceState, State as GovernanceState} from "./libraries/DualGovernanceState.sol";

contract DualGovernance is IGovernance, ConfigurationProvider {
    using Proposers for Proposers.State;
    using DualGovernanceState for DualGovernanceState.Store;

    event TiebreakerSet(address tiebreakCommittee);
    event ProposalApprovedForExecition(uint256 proposalId);
    event ProposalScheduled(uint256 proposalId);
    event SealableResumeApproved(address sealable);

    error ProposalNotExecutable(uint256 proposalId);
    error NotTiebreaker(address account, address tiebreakCommittee);
    error ProposalAlreadyApproved(uint256 proposalId);
    error ProposalIsNotApprovedForExecution(uint256 proposalId);
    error TiebreakerTimelockIsNotPassed(uint256 proposalId);
    error SealableResumeAlreadyApproved(address sealable);
    error TieBreakerAddressIsSame();

    ITimelock public immutable TIMELOCK;

    address internal _tiebreaker;
    uint256 internal _tiebreakerProposalApprovalTimelock;
    mapping(uint256 proposalId => uint256) internal _tiebreakerProposalApprovalTimestamp;
    mapping(address sealable => bool) internal _tiebreakerSealableResumeApprovals;

    Proposers.State internal _proposers;
    DualGovernanceState.Store internal _dgState;
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
        _checkTiebreakerCommittee(msg.sender);
        _dgState.checkTiebreak(CONFIG);
        if (_tiebreakerProposalApprovalTimestamp[proposalId] > 0) {
            revert ProposalAlreadyApproved(proposalId);
        }

        _tiebreakerProposalApprovalTimestamp[proposalId] = block.timestamp;
        emit ProposalApprovedForExecition(proposalId);
    }

    function tiebreakerApproveSealableResume(address sealable) external {
        _checkTiebreakerCommittee(msg.sender);
        _dgState.checkTiebreak(CONFIG);
        Proposer memory proposer = _proposers.get(msg.sender);
        ExecutorCall[] memory calls = new ExecutorCall[](1);
        calls[0] = ExecutorCall(sealable, 0, abi.encodeWithSignature("resume()"));
        uint256 proposalId = TIMELOCK.submit(proposer.executor, calls);
        _tiebreakerProposalApprovalTimestamp[proposalId] = block.timestamp;
        emit ProposalApprovedForExecition(proposalId);
        emit SealableResumeApproved(sealable);
    }

    function tiebreakerSchedule(uint256 proposalId) external {
        _dgState.checkTiebreak(CONFIG);
        if (_tiebreakerProposalApprovalTimestamp[proposalId] == 0) {
            revert ProposalIsNotApprovedForExecution(proposalId);
        }
        if (_tiebreakerProposalApprovalTimestamp[proposalId] + _tiebreakerProposalApprovalTimelock > block.timestamp) {
            revert TiebreakerTimelockIsNotPassed(proposalId);
        }
        TIMELOCK.schedule(proposalId);
    }

    function setTiebreakerProtection(address newTiebreaker) external {
        _checkAdminExecutor(msg.sender);
        if (_tiebreaker == newTiebreaker) {
            revert TieBreakerAddressIsSame();
        }
        if (_tiebreaker != address(0)) {
            _proposers.unregister(CONFIG, _tiebreaker);
        }
        _tiebreaker = newTiebreaker;
        _proposers.register(newTiebreaker, CONFIG.ADMIN_EXECUTOR()); // TODO: check what executor should be. Reseal executor?
        emit TiebreakerSet(newTiebreaker);
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
