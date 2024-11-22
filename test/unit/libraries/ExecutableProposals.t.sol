// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";

import {Duration, Durations, MAX_DURATION_VALUE} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {Executor} from "contracts/Executor.sol";
import {
    ExecutableProposals, ExternalCall, Status as ProposalStatus
} from "contracts/libraries/ExecutableProposals.sol";

import {TargetMock} from "test/utils/target-mock.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract ExecutableProposalsUnitTests is UnitTest {
    using ExecutableProposals for ExecutableProposals.Context;

    Executor private _executor;
    TargetMock private _targetMock;
    ExecutableProposals.Context internal _proposals;

    uint256 private constant PROPOSAL_ID_OFFSET = 1;

    function setUp() external {
        _targetMock = new TargetMock();
        _executor = new Executor(address(this));
    }

    function test_submit_reverts_if_empty_proposals() external {
        vm.expectRevert(ExecutableProposals.EmptyCalls.selector);
        _proposals.submit(address(0), new ExternalCall[](0), "Empty calls");
    }

    function test_submit_proposal() external {
        uint256 proposalsCount = _proposals.getProposalsCount();

        ExternalCall[] memory calls = _getMockTargetRegularStaffCalls(address(_targetMock));

        uint256 expectedProposalId = proposalsCount + PROPOSAL_ID_OFFSET;
        string memory description = "Regular staff calls";

        vm.expectEmit();
        emit ExecutableProposals.ProposalSubmitted(expectedProposalId, address(_executor), calls, description);

        vm.recordLogs();

        _proposals.submit(address(_executor), calls, description);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);

        proposalsCount = _proposals.getProposalsCount();

        ExecutableProposals.Proposal memory proposal = _proposals.proposals[expectedProposalId];

        assertEq(proposal.data.status, ProposalStatus.Submitted);
        assertEq(proposal.data.executor, address(_executor));
        assertEq(proposal.data.submittedAt, Timestamps.now());
        assertEq(proposal.data.scheduledAt, Timestamps.ZERO);

        assertEq(proposal.calls.length, 1);

        for (uint256 i = 0; i < calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }
    }

    function testFuzz_schedule_proposal(Duration delay) external {
        vm.assume(delay > Durations.ZERO && delay.toSeconds() <= MAX_DURATION_VALUE);

        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");

        uint256 expectedProposalId = 1;
        ExecutableProposals.Proposal memory proposal = _proposals.proposals[expectedProposalId];

        Timestamp submittedAt = Timestamps.now();

        assertEq(proposal.data.status, ProposalStatus.Submitted);
        assertEq(proposal.data.submittedAt, submittedAt);
        assertEq(proposal.data.scheduledAt, Timestamps.ZERO);

        _wait(delay);

        vm.expectEmit();
        emit ExecutableProposals.ProposalScheduled(expectedProposalId);
        _proposals.schedule(expectedProposalId, delay);

        proposal = _proposals.proposals[expectedProposalId];

        assertEq(proposal.data.status, ProposalStatus.Scheduled);
        assertEq(proposal.data.submittedAt, submittedAt);
        assertEq(proposal.data.scheduledAt, Timestamps.now());
    }

    function testFuzz_cannot_schedule_unsubmitted_proposal(uint256 proposalId) external {
        vm.assume(proposalId > 0);

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.ProposalNotSubmitted.selector, proposalId));
        _proposals.schedule(proposalId, Durations.ZERO);
    }

    function test_cannot_schedule_proposal_twice() external {
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = 1;
        _proposals.schedule(proposalId, Durations.ZERO);

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.ProposalNotSubmitted.selector, proposalId));
        _proposals.schedule(proposalId, Durations.ZERO);
    }

    function testFuzz_cannot_schedule_proposal_before_delay_passed(Duration delay) external {
        vm.assume(delay > Durations.ZERO && delay.toSeconds() <= MAX_DURATION_VALUE);

        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");

        _wait(delay.minusSeconds(1 seconds));

        vm.expectRevert(
            abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, PROPOSAL_ID_OFFSET)
        );
        _proposals.schedule(PROPOSAL_ID_OFFSET, delay);
    }

    function test_cannot_schedule_cancelled_proposal() external {
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        _proposals.cancelAll();

        uint256 proposalId = _proposals.getProposalsCount();

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.ProposalNotSubmitted.selector, proposalId));
        _proposals.schedule(proposalId, Durations.ZERO);
    }

    function testFuzz_execute_proposal(Duration delay) external {
        vm.assume(delay > Durations.ZERO && delay.toSeconds() <= MAX_DURATION_VALUE);

        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = _proposals.getProposalsCount();
        _proposals.schedule(proposalId, Durations.ZERO);

        Timestamp submittedAndScheduledAt = Timestamps.now();

        ExecutableProposals.Proposal memory proposal = _proposals.proposals[proposalId];

        assertEq(proposal.data.status, ProposalStatus.Scheduled);
        assertEq(proposal.data.submittedAt, submittedAndScheduledAt);
        assertEq(proposal.data.scheduledAt, submittedAndScheduledAt);

        _wait(delay);

        // TODO: figure out why event is not emitted
        // vm.expectEmit();
        // emit ExecutableProposals.ProposalExecuted();
        _proposals.execute(proposalId, delay);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        proposal = _proposals.proposals[proposalId];

        assertEq(proposal.data.status, ProposalStatus.Executed);
        assertEq(proposal.data.submittedAt, submittedAndScheduledAt);
        assertEq(proposal.data.scheduledAt, submittedAndScheduledAt);
    }

    function testFuzz_cannot_execute_unsubmitted_proposal(uint256 proposalId) external {
        vm.assume(proposalId > 0);
        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.ProposalNotScheduled.selector, proposalId));
        _proposals.execute(proposalId, Durations.ZERO);
    }

    function test_cannot_execute_unscheduled_proposal() external {
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = _proposals.getProposalsCount();

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.ProposalNotScheduled.selector, proposalId));
        _proposals.execute(proposalId, Durations.ZERO);
    }

    function test_cannot_execute_twice() external {
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = _proposals.getProposalsCount();
        _proposals.schedule(proposalId, Durations.ZERO);
        _proposals.execute(proposalId, Durations.ZERO);

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.ProposalNotScheduled.selector, proposalId));
        _proposals.execute(proposalId, Durations.ZERO);
    }

    function test_cannot_execute_cancelled_proposal() external {
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = _proposals.getProposalsCount();
        _proposals.schedule(proposalId, Durations.ZERO);
        _proposals.cancelAll();

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.ProposalNotScheduled.selector, proposalId));
        _proposals.execute(proposalId, Durations.ZERO);
    }

    function testFuzz_cannot_execute_before_delay_passed(Duration delay) external {
        vm.assume(delay > Durations.ZERO && delay.toSeconds() <= MAX_DURATION_VALUE);
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = _proposals.getProposalsCount();
        _proposals.schedule(proposalId, Durations.ZERO);

        _wait(delay.minusSeconds(1 seconds));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterScheduleDelayNotPassed.selector, proposalId));
        _proposals.execute(proposalId, delay);
    }

    function test_cancel_all_proposals() external {
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");

        uint256 proposalsCount = _proposals.getProposalsCount();

        _proposals.schedule(proposalsCount, Durations.ZERO);

        vm.expectEmit();
        emit ExecutableProposals.ProposalsCancelledTill(proposalsCount);
        _proposals.cancelAll();

        assertEq(_proposals.lastCancelledProposalId, proposalsCount);
    }

    // TODO: change this test completely to use getters
    function test_get_proposal_info_and_external_calls() external {
        ExternalCall[] memory expectedCalls = _getMockTargetRegularStaffCalls(address(_targetMock));
        _proposals.submit(address(_executor), expectedCalls, "");
        uint256 proposalId = _proposals.getProposalsCount();

        ITimelock.ProposalDetails memory proposalDetails = _proposals.getProposalDetails(proposalId);

        Timestamp expectedSubmittedAt = Timestamps.now();

        assertEq(proposalDetails.status, ProposalStatus.Submitted);
        assertEq(proposalDetails.executor, address(_executor));
        assertEq(proposalDetails.submittedAt, expectedSubmittedAt);
        assertEq(proposalDetails.scheduledAt, Timestamps.ZERO);

        ExternalCall[] memory calls = _proposals.getProposalCalls(proposalId);

        assertEq(calls.length, expectedCalls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(calls[i].value, expectedCalls[i].value);
            assertEq(calls[i].target, expectedCalls[i].target);
            assertEq(calls[i].payload, expectedCalls[i].payload);
        }

        _proposals.schedule(proposalId, Durations.ZERO);

        Timestamp expectedScheduledAt = Timestamps.now();

        proposalDetails = _proposals.getProposalDetails(proposalId);

        assertEq(proposalDetails.status, ProposalStatus.Scheduled);
        assertEq(proposalDetails.executor, address(_executor));
        assertEq(proposalDetails.submittedAt, expectedSubmittedAt);
        assertEq(proposalDetails.scheduledAt, expectedScheduledAt);

        calls = _proposals.getProposalCalls(proposalId);

        assertEq(calls.length, expectedCalls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(calls[i].value, expectedCalls[i].value);
            assertEq(calls[i].target, expectedCalls[i].target);
            assertEq(calls[i].payload, expectedCalls[i].payload);
        }

        _proposals.execute(proposalId, Durations.ZERO);

        proposalDetails = _proposals.getProposalDetails(proposalId);

        assertEq(proposalDetails.status, ProposalStatus.Executed);
        assertEq(proposalDetails.executor, address(_executor));
        assertEq(proposalDetails.submittedAt, expectedSubmittedAt);
        assertEq(proposalDetails.scheduledAt, expectedScheduledAt);

        calls = _proposals.getProposalCalls(proposalId);

        assertEq(calls.length, expectedCalls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(calls[i].value, expectedCalls[i].value);
            assertEq(calls[i].target, expectedCalls[i].target);
            assertEq(calls[i].payload, expectedCalls[i].payload);
        }
    }

    function test_get_cancelled_proposal() external {
        ExternalCall[] memory expectedCalls = _getMockTargetRegularStaffCalls(address(_targetMock));
        _proposals.submit(address(_executor), expectedCalls, "");
        uint256 proposalId = _proposals.getProposalsCount();

        ITimelock.ProposalDetails memory proposalDetails = _proposals.getProposalDetails(proposalId);

        Timestamp expectedSubmittedAt = Timestamps.now();

        assertEq(proposalDetails.status, ProposalStatus.Submitted);
        assertEq(proposalDetails.executor, address(_executor));
        assertEq(proposalDetails.submittedAt, expectedSubmittedAt);
        assertEq(proposalDetails.scheduledAt, Timestamps.ZERO);

        ExternalCall[] memory calls = _proposals.getProposalCalls(proposalId);

        assertEq(calls.length, expectedCalls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(calls[i].value, expectedCalls[i].value);
            assertEq(calls[i].target, expectedCalls[i].target);
            assertEq(calls[i].payload, expectedCalls[i].payload);
        }

        ExecutableProposals.cancelAll(_proposals);

        proposalDetails = _proposals.getProposalDetails(proposalId);

        assertEq(proposalDetails.status, ProposalStatus.Cancelled);
        assertEq(proposalDetails.executor, address(_executor));
        assertEq(proposalDetails.submittedAt, expectedSubmittedAt);
        assertEq(proposalDetails.scheduledAt, Timestamps.ZERO);

        calls = _proposals.getProposalCalls(proposalId);

        assertEq(calls.length, expectedCalls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(calls[i].value, expectedCalls[i].value);
            assertEq(calls[i].target, expectedCalls[i].target);
            assertEq(calls[i].payload, expectedCalls[i].payload);
        }
    }

    function testFuzz_get_not_existing_proposal(uint256 proposalId) external {
        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.ProposalNotFound.selector, proposalId));
        _proposals.getProposalDetails(proposalId);

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.ProposalNotFound.selector, proposalId));
        _proposals.getProposalCalls(proposalId);
    }

    function test_count_proposals() external {
        assertEq(_proposals.getProposalsCount(), 0);

        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        assertEq(_proposals.getProposalsCount(), 1);

        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        assertEq(_proposals.getProposalsCount(), 2);

        _proposals.schedule(1, Durations.ZERO);
        assertEq(_proposals.getProposalsCount(), 2);

        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        assertEq(_proposals.getProposalsCount(), 3);

        _proposals.schedule(2, Durations.ZERO);
        assertEq(_proposals.getProposalsCount(), 3);

        _proposals.execute(1, Durations.ZERO);
        assertEq(_proposals.getProposalsCount(), 3);

        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        assertEq(_proposals.getProposalsCount(), 4);

        _proposals.cancelAll();
        assertEq(_proposals.getProposalsCount(), 4);
    }

    function test_can_execute_proposal() external {
        Duration delay = Durations.from(100 seconds);
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = _proposals.getProposalsCount();

        assert(!_proposals.canExecute(proposalId, Durations.ZERO));

        _proposals.schedule(proposalId, Durations.ZERO);

        assert(!_proposals.canExecute(proposalId, delay));

        _wait(delay);

        assert(_proposals.canExecute(proposalId, delay));

        _proposals.execute(proposalId, Durations.ZERO);

        assert(!_proposals.canExecute(proposalId, delay));
    }

    function test_can_not_execute_cancelled_proposal() external {
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = _proposals.getProposalsCount();
        _proposals.schedule(proposalId, Durations.ZERO);

        assert(_proposals.canExecute(proposalId, Durations.ZERO));
        _proposals.cancelAll();

        assert(!_proposals.canExecute(proposalId, Durations.ZERO));
    }

    function test_cancelAll_DoesNotModifyStateOfExecutedProposals() external {
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        assertEq(_proposals.getProposalsCount(), 1);
        uint256 executedProposalId = 1;
        _proposals.schedule(executedProposalId, Durations.ZERO);
        _proposals.execute(executedProposalId, Durations.ZERO);

        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        assertEq(_proposals.getProposalsCount(), 2);
        uint256 scheduledProposalId = 2;
        _proposals.schedule(scheduledProposalId, Durations.ZERO);

        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        assertEq(_proposals.getProposalsCount(), 3);
        uint256 submittedProposalId = 3;

        // Validate the state of the proposals is correct before proceeding with cancellation.

        assertEq(_proposals.getProposalDetails(executedProposalId).status, ProposalStatus.Executed);
        assertEq(_proposals.getProposalDetails(scheduledProposalId).status, ProposalStatus.Scheduled);
        assertEq(_proposals.getProposalDetails(submittedProposalId).status, ProposalStatus.Submitted);

        // After canceling the proposals, both submitted and scheduled proposals should transition to the Cancelled state.
        // However, executed proposals should remain in the Executed state.

        _proposals.cancelAll();

        assertEq(_proposals.getProposalDetails(executedProposalId).status, ProposalStatus.Executed);
        assertEq(_proposals.getProposalDetails(scheduledProposalId).status, ProposalStatus.Cancelled);
        assertEq(_proposals.getProposalDetails(submittedProposalId).status, ProposalStatus.Cancelled);
    }

    function test_can_schedule_proposal() external {
        Duration delay = Durations.from(100 seconds);
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = _proposals.getProposalsCount();
        assert(!_proposals.canSchedule(proposalId, delay));

        _wait(delay);

        assert(_proposals.canSchedule(proposalId, delay));

        _proposals.schedule(proposalId, delay);
        _proposals.execute(proposalId, Durations.ZERO);

        assert(!_proposals.canSchedule(proposalId, delay));
    }

    function test_can_not_schedule_cancelled_proposal() external {
        _proposals.submit(address(_executor), _getMockTargetRegularStaffCalls(address(_targetMock)), "");
        uint256 proposalId = _proposals.getProposalsCount();
        assert(_proposals.canSchedule(proposalId, Durations.ZERO));

        _proposals.cancelAll();

        assert(!_proposals.canSchedule(proposalId, Durations.ZERO));
    }
}
