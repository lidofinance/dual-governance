pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/ImmutableDualGovernanceConfigProvider.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import {Escrow} from "contracts/Escrow.sol";

import {Status, ExecutableProposals as Proposals} from "contracts/libraries/ExecutableProposals.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {DualGovernanceSetUp} from "test/kontrol/DualGovernanceSetUp.sol";

contract ProposalOperationsTest is DualGovernanceSetUp {
    function _proposalOperationsInitializeStorage(
        DualGovernance _dualGovernance,
        EmergencyProtectedTimelock _timelock,
        uint256 _proposalId
    ) public {
        _proposalIdAssumeBound(_timelock, _proposalId);
        _proposalStorageSetup(_timelock, _proposalId);
        _storeExecutorCalls(_timelock, _proposalId);
    }

    struct ProposalRecord {
        State state;
        uint256 id;
        uint256 lastCancelledProposalId;
        Timestamp submittedAt;
        Timestamp scheduledAt;
        Timestamp vetoSignallingActivationTime;
    }

    // Record a proposal's details with the current governance state.
    function _recordProposal(uint256 proposalId) internal returns (ProposalRecord memory pr) {
        uint256 baseSlot = _getProposalsSlot(proposalId);
        pr.id = proposalId;
        pr.state = dualGovernance.getPersistedState();
        pr.lastCancelledProposalId = _getLastCancelledProposalId(timelock);
        pr.submittedAt = Timestamp.wrap(_getSubmittedAt(timelock, baseSlot));
        pr.scheduledAt = Timestamp.wrap(_getScheduledAt(timelock, baseSlot));
        pr.vetoSignallingActivationTime = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));
    }

    // Validate that a pending proposal meets the criteria.
    function _validPendingProposal(Mode mode, ProposalRecord memory pr) internal pure {
        _establish(mode, pr.lastCancelledProposalId < pr.id);
        _establish(mode, pr.submittedAt != Timestamp.wrap(0));
        _establish(mode, pr.scheduledAt == Timestamp.wrap(0));
    }

    // Validate that a scheduled proposal meets the criteria.
    function _validScheduledProposal(Mode mode, ProposalRecord memory pr) internal {
        _establish(mode, pr.lastCancelledProposalId < pr.id);
        _establish(mode, pr.submittedAt != Timestamp.wrap(0));
        _establish(mode, pr.scheduledAt != Timestamp.wrap(0));
    }

    function _validExecutedProposal(Mode mode, ProposalRecord memory pr) internal {
        _establish(mode, pr.lastCancelledProposalId < pr.id);
        _establish(mode, pr.submittedAt != Timestamp.wrap(0));
        _establish(mode, pr.scheduledAt != Timestamp.wrap(0));
    }

    function _validCanceledProposal(Mode mode, ProposalRecord memory pr) internal pure {
        _establish(mode, pr.id <= pr.lastCancelledProposalId);
        _establish(mode, pr.submittedAt != Timestamp.wrap(0));
    }

    function _isCancelled(ProposalRecord memory pr) internal pure returns (bool) {
        return pr.lastCancelledProposalId >= pr.id;
    }

    /**
     * Test that a proposal cannot be submitted in the VetoSignallingDeactivation or VetoCooldown states.
     */
    function testCannotProposeInInvalidState() external {
        uint256 proposalsCount = timelock.getProposalsCount();

        address proposer = _getArbitraryUserAddress();

        State nextState = dualGovernance.getEffectiveState();
        vm.assume(nextState != State.Normal);
        vm.assume(nextState != State.VetoSignalling);
        vm.assume(nextState != State.RageQuit);

        vm.prank(proposer);
        vm.expectRevert(DualGovernance.ProposalSubmissionBlocked.selector);
        dualGovernance.submitProposal(new ExternalCall[](1), "Proposal metadata.");

        assert(timelock.getProposalsCount() == proposalsCount);
    }

    /**
     * Test that a proposal cannot be scheduled for execution if the Dual Governance state is not Normal or VetoCooldown.
     */
    function testCannotScheduleInInvalidStates(uint256 proposalId) external {
        _proposalIdAssumeBound(timelock, proposalId);
        _proposalStorageSetup(timelock, proposalId);

        ProposalRecord memory pre = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assume, pre);
        vm.assume(timelock.canSchedule(proposalId));

        State state = dualGovernance.getEffectiveState();
        vm.assume(state != State.Normal);
        vm.assume(state != State.VetoCooldown);

        vm.expectRevert(abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, proposalId));
        dualGovernance.scheduleProposal(proposalId);

        ProposalRecord memory post = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assert, post);
    }

    /**
     * Test that a proposal cannot be scheduled for execution if it was submitted after the last time the VetoSignalling state was entered.
     */
    function testCannotScheduleSubmissionAfterLastVetoSignalling(uint256 proposalId) external {
        _proposalIdAssumeBound(timelock, proposalId);
        _proposalStorageSetup(timelock, proposalId);

        ProposalRecord memory pre = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assume, pre);
        vm.assume(timelock.canSchedule(proposalId));
        vm.assume(dualGovernance.getEffectiveState() == State.VetoCooldown);
        vm.assume(pre.submittedAt > pre.vetoSignallingActivationTime);

        vm.expectRevert(abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, proposalId));
        dualGovernance.scheduleProposal(proposalId);

        ProposalRecord memory post = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assert, post);
    }

    /**
     * Test that only proposals canceller can cancel proposals.
     */
    function testOnlyProposalsCancellerCanCancelProposals() external {
        address sender = _getArbitraryUserAddress();
        vm.assume(sender != dualGovernance.getProposalsCanceller());

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotProposalsCanceller.selector, sender));
        dualGovernance.cancelAllPendingProposals();
        vm.stopPrank();
    }
}
