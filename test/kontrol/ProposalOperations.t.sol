pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/Configuration.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";

import {Status, Proposal} from "contracts/libraries/Proposals.sol";
import {State} from "contracts/libraries/DualGovernanceState.sol";
import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {ProposalOperationsSetup} from "test/kontrol/ProposalOperationsSetup.sol";

contract ProposalOperationsTest is ProposalOperationsSetup {
    function _proposalOperationsInitializeStorage(
        DualGovernance _dualGovernance,
        EmergencyProtectedTimelock _timelock,
        uint256 _proposalId
    ) public {
        _timelockStorageSetup(_dualGovernance, _timelock);
        _proposalIdAssumeBound(_proposalId);
        _proposalStorageSetup(_timelock, _proposalId);
        _storeExecutorCalls(_timelock, _proposalId);
    }

    struct ProposalRecord {
        State state;
        uint256 id;
        uint256 lastCancelledProposalId;
        Timestamp submittedAt;
        Timestamp scheduledAt;
        Timestamp executedAt;
        Timestamp vetoSignallingActivationTime;
    }

    // Record a proposal's details with the current governance state.
    function _recordProposal(uint256 proposalId) internal returns (ProposalRecord memory pr) {
        uint256 baseSlot = _getProposalsSlot(proposalId);
        pr.id = proposalId;
        pr.state = dualGovernance.getCurrentState();
        pr.lastCancelledProposalId = _getLastCancelledProposalId(timelock);
        pr.submittedAt = Timestamp.wrap(_getSubmittedAt(timelock, baseSlot));
        pr.scheduledAt = Timestamp.wrap(_getScheduledAt(timelock, baseSlot));
        pr.executedAt = Timestamp.wrap(_getExecutedAt(timelock, baseSlot));
        pr.vetoSignallingActivationTime = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));
    }

    // Validate that a pending proposal meets the criteria.
    function _validPendingProposal(Mode mode, ProposalRecord memory pr) internal pure {
        _establish(mode, pr.lastCancelledProposalId < pr.id);
        _establish(mode, pr.submittedAt != Timestamp.wrap(0));
        _establish(mode, pr.scheduledAt == Timestamp.wrap(0));
        _establish(mode, pr.executedAt == Timestamp.wrap(0));
    }

    // Validate that a scheduled proposal meets the criteria.
    function _validScheduledProposal(Mode mode, ProposalRecord memory pr) internal {
        _establish(mode, pr.lastCancelledProposalId < pr.id);
        _establish(mode, pr.submittedAt != Timestamp.wrap(0));
        _establish(mode, pr.scheduledAt != Timestamp.wrap(0));
        _establish(mode, pr.executedAt == Timestamp.wrap(0));
        _establish(mode, config.AFTER_SUBMIT_DELAY().addTo(pr.submittedAt) <= Timestamps.now());
    }

    function _validExecutedProposal(Mode mode, ProposalRecord memory pr) internal {
        _establish(mode, pr.lastCancelledProposalId < pr.id);
        _establish(mode, pr.submittedAt != Timestamp.wrap(0));
        _establish(mode, pr.scheduledAt != Timestamp.wrap(0));
        _establish(mode, pr.executedAt != Timestamp.wrap(0));
        _establish(mode, config.AFTER_SUBMIT_DELAY().addTo(pr.submittedAt) <= Timestamps.now());
        _establish(mode, config.AFTER_SCHEDULE_DELAY().addTo(pr.scheduledAt) <= Timestamps.now());
    }

    function _validCanceledProposal(Mode mode, ProposalRecord memory pr) internal pure {
        _establish(mode, pr.id <= pr.lastCancelledProposalId);
        _establish(mode, pr.submittedAt != Timestamp.wrap(0));
        _establish(mode, pr.executedAt == Timestamp.wrap(0));
    }

    function _isExecuted(ProposalRecord memory pr) internal pure returns (bool) {
        return pr.executedAt != Timestamp.wrap(0);
    }

    function _isCancelled(ProposalRecord memory pr) internal pure returns (bool) {
        return pr.lastCancelledProposalId >= pr.id;
    }

    function testCannotProposeInInvalidState() external {
        _initializeAuxDualGovernance();

        _timelockStorageSetup(dualGovernance, timelock);
        uint256 newProposalIndex = timelock.getProposalsCount();

        address proposer = address(uint160(uint256(keccak256("proposer"))));
        uint8 proposerIndexOneBased = uint8(kevm.freshUInt(1));
        vm.assume(proposerIndexOneBased != 0);
        uint160 executor = uint160(kevm.freshUInt(20));
        bytes memory slotAbi = abi.encodePacked(uint88(0), uint160(executor), uint8(proposerIndexOneBased));
        bytes32 slot;
        assembly {
            slot := mload(add(slotAbi, 0x20))
        }
        _storeBytes32(
            address(dualGovernance), 28324487748957058971331294301258181510018269374235438230632061138814754629752, slot
        );

        auxDualGovernance.activateNextState();
        State nextState = auxDualGovernance.getCurrentState();
        vm.assume(nextState != State.Normal);
        vm.assume(nextState != State.VetoSignalling);
        vm.assume(nextState != State.RageQuit);

        vm.prank(proposer);
        vm.expectRevert(DualGovernanceState.ProposalsCreationSuspended.selector);
        dualGovernance.submitProposal(new ExecutorCall[](1));

        assert(timelock.getProposalsCount() == newProposalIndex);
    }

    /**
     * Test that a proposal cannot be scheduled for execution if the Dual Governance state is not Normal or VetoCooldown.
     */
    function testCannotScheduleInInvalidStates(uint256 proposalId) external {
        _timelockStorageSetup(dualGovernance, timelock);
        _proposalIdAssumeBound(proposalId);
        _proposalStorageSetup(timelock, proposalId);

        ProposalRecord memory pre = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assume, pre);
        vm.assume(timelock.canSchedule(proposalId));
        vm.assume(!dualGovernance.isSchedulingEnabled());

        vm.expectRevert(DualGovernanceState.ProposalsAdoptionSuspended.selector);
        dualGovernance.scheduleProposal(proposalId);

        ProposalRecord memory post = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assert, post);
    }

    /**
     * Test that a proposal cannot be scheduled for execution if it was submitted after the last time the VetoSignalling state was entered.
     */
    function testCannotScheduleSubmissionAfterLastVetoSignalling(uint256 proposalId) external {
        _timelockStorageSetup(dualGovernance, timelock);
        _proposalIdAssumeBound(proposalId);
        _proposalStorageSetup(timelock, proposalId);

        ProposalRecord memory pre = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assume, pre);
        vm.assume(timelock.canSchedule(proposalId));
        vm.assume(pre.state == State.VetoCooldown);
        vm.assume(pre.submittedAt > pre.vetoSignallingActivationTime);

        vm.expectRevert(DualGovernanceState.ProposalsAdoptionSuspended.selector);
        dualGovernance.scheduleProposal(proposalId);

        ProposalRecord memory post = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assert, post);
    }

    // Test that actions that are canceled or executed cannot be rescheduled
    function testCanceledOrExecutedActionsCannotBeRescheduled(uint256 proposalId) external {
        _proposalOperationsInitializeStorage(dualGovernance, timelock, proposalId);

        ProposalRecord memory pre = _recordProposal(proposalId);
        vm.assume(pre.submittedAt != Timestamp.wrap(0));
        vm.assume(dualGovernance.isSchedulingEnabled());
        if (pre.state == State.VetoCooldown) {
            vm.assume(pre.submittedAt <= pre.vetoSignallingActivationTime);
        }

        // Check if the proposal has been executed
        if (pre.executedAt != Timestamp.wrap(0)) {
            _validExecutedProposal(Mode.Assume, pre);

            vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, proposalId));
            dualGovernance.scheduleProposal(proposalId);

            ProposalRecord memory post = _recordProposal(proposalId);
            _validExecutedProposal(Mode.Assert, post);
        } else if (pre.lastCancelledProposalId >= proposalId) {
            // Check if the proposal has been cancelled
            _validCanceledProposal(Mode.Assume, pre);

            vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, proposalId));
            dualGovernance.scheduleProposal(proposalId);

            ProposalRecord memory post = _recordProposal(proposalId);
            _validCanceledProposal(Mode.Assert, post);
        }
    }

    /**
     * Test that a proposal cannot be scheduled for execution before ProposalExecutionMinTimelock has passed since its submission.
     */
    function testCannotScheduleBeforeMinTimelock(uint256 proposalId) external {
        _proposalOperationsInitializeStorage(dualGovernance, timelock, proposalId);

        ProposalRecord memory pre = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assume, pre);

        vm.assume(dualGovernance.isSchedulingEnabled());
        if (pre.state == State.VetoCooldown) {
            vm.assume(pre.submittedAt <= pre.vetoSignallingActivationTime);
        }
        vm.assume(Timestamps.now() < addTo(config.AFTER_SUBMIT_DELAY(), pre.submittedAt));

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterSubmitDelayNotPassed.selector, proposalId));
        dualGovernance.scheduleProposal(proposalId);

        ProposalRecord memory post = _recordProposal(proposalId);
        _validPendingProposal(Mode.Assert, post);
    }

    /**
     * Test that a proposal cannot be executed until the emergency protection timelock has passed since it was scheduled.
     */
    function testCannotExecuteBeforeEmergencyProtectionTimelock(uint256 proposalId) external {
        _proposalOperationsInitializeStorage(dualGovernance, timelock, proposalId);

        ProposalRecord memory pre = _recordProposal(proposalId);
        _validScheduledProposal(Mode.Assume, pre);
        vm.assume(_getEmergencyModeEndsAfter(timelock) == 0);
        vm.assume(Timestamps.now() < addTo(config.AFTER_SCHEDULE_DELAY(), pre.scheduledAt));

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterScheduleDelayNotPassed.selector, proposalId));
        timelock.execute(proposalId);

        ProposalRecord memory post = _recordProposal(proposalId);
        _validScheduledProposal(Mode.Assert, post);
    }

    /**
     * Test that only admin proposers can cancel proposals.
     */
    function testOnlyAdminProposersCanCancelProposals() external {
        _timelockStorageSetup(dualGovernance, timelock);

        // Cancel as a non-admin proposer
        address proposer = address(uint160(uint256(keccak256("proposer"))));
        vm.assume(dualGovernance.isProposer(proposer));
        vm.assume(dualGovernance.getProposer(proposer).executor != config.ADMIN_EXECUTOR());

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(Proposers.NotAdminProposer.selector, proposer));
        dualGovernance.cancelAllPendingProposals();

        // Cancel as an admin proposer
        address adminProposer = address(uint160(uint256(keccak256("adminProposer"))));
        vm.assume(dualGovernance.isProposer(adminProposer));
        vm.assume(dualGovernance.getProposer(adminProposer).executor == config.ADMIN_EXECUTOR());

        vm.prank(adminProposer);
        dualGovernance.cancelAllPendingProposals();
    }
}
