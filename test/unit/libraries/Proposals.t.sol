// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Vm} from "forge-std/Test.sol";

import {Executor} from "contracts/Executor.sol";
import {Proposals, ExecutorCall, Proposal, Status} from "contracts/libraries/Proposals.sol";

import {TargetMock} from "test/utils/utils.sol";
import {UnitTest, Timestamps, Timestamp, Durations, Duration} from "test/utils/unit-test.sol";

contract ProposalsUnitTests is UnitTest {
    using Proposals for Proposals.State;

    TargetMock private _targetMock;
    Proposals.State internal _proposals;
    Executor private _executor;

    uint256 private constant PROPOSAL_ID_OFFSET = 1;

    function setUp() external {
        _targetMock = new TargetMock();
        _executor = new Executor(address(this));
    }

    function test_submit_reverts_if_empty_proposals() external {
        vm.expectRevert(Proposals.EmptyCalls.selector);
        Proposals.submit(_proposals, address(0), new ExecutorCall[](0));
    }

    function test_submit_proposal() external {
        uint256 proposalsCount = _proposals.count();

        ExecutorCall[] memory calls = _getTargetRegularStaffCalls(address(_targetMock));

        vm.expectEmit();
        emit Proposals.ProposalSubmitted(proposalsCount + PROPOSAL_ID_OFFSET, address(_executor), calls);

        vm.recordLogs();

        Proposals.submit(_proposals, address(_executor), calls);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);

        proposalsCount = _proposals.count();

        Proposals.ProposalPacked memory proposal = _proposals.proposals[proposalsCount - PROPOSAL_ID_OFFSET];

        assertEq(proposal.executor, address(_executor));
        assertEq(proposal.submittedAt, Timestamps.now());
        assertEq(proposal.executedAt, Timestamps.ZERO);
        assertEq(proposal.scheduledAt, Timestamps.ZERO);
        assertEq(proposal.calls.length, 1);

        for (uint256 i = 0; i < proposal.calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }
    }

    function testFuzz_schedule_proposal(Duration delay) external {
        vm.assume(delay > Durations.ZERO && delay <= Durations.MAX);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        Proposals.ProposalPacked memory proposal = _proposals.proposals[0];

        Timestamp submittedAt = Timestamps.now();

        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, Timestamps.ZERO);
        assertEq(proposal.executedAt, Timestamps.ZERO);

        uint256 proposalId = _proposals.count();

        _wait(delay);

        vm.expectEmit();
        emit Proposals.ProposalScheduled(proposalId);
        Proposals.schedule(_proposals, proposalId, delay);

        proposal = _proposals.proposals[0];

        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, Timestamps.now());
        assertEq(proposal.executedAt, Timestamps.ZERO);
    }

    function testFuzz_cannot_schedule_unsubmitted_proposal(uint256 proposalId) external {
        vm.assume(proposalId > 0);

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, proposalId));
        Proposals.schedule(_proposals, proposalId, Durations.ZERO);
    }

    function test_cannot_schedule_proposal_twice() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = 1;
        Proposals.schedule(_proposals, proposalId, Durations.ZERO);

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, proposalId));
        Proposals.schedule(_proposals, proposalId, Durations.ZERO);
    }

    function testFuzz_cannot_schedule_proposal_before_delay_passed(Duration delay) external {
        vm.assume(delay > Durations.ZERO && delay <= Durations.MAX);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));

        _wait(delay.minusSeconds(1 seconds));

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterSubmitDelayNotPassed.selector, PROPOSAL_ID_OFFSET));
        Proposals.schedule(_proposals, PROPOSAL_ID_OFFSET, delay);
    }

    function test_cannot_schedule_cancelled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        Proposals.cancelAll(_proposals);

        uint256 proposalId = _proposals.count();

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, proposalId));
        Proposals.schedule(_proposals, proposalId, Durations.ZERO);
    }

    function testFuzz_execute_proposal(Duration delay) external {
        vm.assume(delay > Durations.ZERO && delay <= Durations.MAX);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, Durations.ZERO);

        Timestamp submittedAndScheduledAt = Timestamps.now();

        assertEq(_proposals.proposals[0].submittedAt, submittedAndScheduledAt);
        assertEq(_proposals.proposals[0].scheduledAt, submittedAndScheduledAt);
        assertEq(_proposals.proposals[0].executedAt, Timestamps.ZERO);

        _wait(delay);

        // TODO: figure out why event is not emitted
        // vm.expectEmit();
        // emit Proposals.ProposalExecuted();
        Proposals.execute(_proposals, proposalId, delay);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        Proposals.ProposalPacked memory proposal = _proposals.proposals[0];

        assertEq(_proposals.proposals[0].submittedAt, submittedAndScheduledAt);
        assertEq(_proposals.proposals[0].scheduledAt, submittedAndScheduledAt);
        assertEq(proposal.executedAt, Timestamps.now());
    }

    function testFuzz_cannot_execute_unsubmitted_proposal(uint256 proposalId) external {
        vm.assume(proposalId > 0);
        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotScheduled.selector, proposalId));
        Proposals.execute(_proposals, proposalId, Durations.ZERO);
    }

    function test_cannot_execute_unscheduled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotScheduled.selector, proposalId));
        Proposals.execute(_proposals, proposalId, Durations.ZERO);
    }

    function test_cannot_execute_twice() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, Durations.ZERO);
        Proposals.execute(_proposals, proposalId, Durations.ZERO);

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotScheduled.selector, proposalId));
        Proposals.execute(_proposals, proposalId, Durations.ZERO);
    }

    function test_cannot_execute_cancelled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, Durations.ZERO);
        Proposals.cancelAll(_proposals);

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotScheduled.selector, proposalId));
        Proposals.execute(_proposals, proposalId, Durations.ZERO);
    }

    function testFuzz_cannot_execute_before_delay_passed(Duration delay) external {
        vm.assume(delay > Durations.ZERO && delay <= Durations.MAX);
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, Durations.ZERO);

        _wait(delay.minusSeconds(1 seconds));

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterScheduleDelayNotPassed.selector, proposalId));
        Proposals.execute(_proposals, proposalId, delay);
    }

    function test_cancel_all_proposals() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));

        uint256 proposalsCount = _proposals.count();

        Proposals.schedule(_proposals, proposalsCount, Durations.ZERO);

        vm.expectEmit();
        emit Proposals.ProposalsCancelledTill(proposalsCount);
        Proposals.cancelAll(_proposals);

        assertEq(_proposals.lastCancelledProposalId, proposalsCount);
    }

    function test_get_proposal() external {
        ExecutorCall[] memory calls = _getTargetRegularStaffCalls(address(_targetMock));
        Proposals.submit(_proposals, address(_executor), calls);
        uint256 proposalId = _proposals.count();

        Proposal memory proposal = _proposals.get(proposalId);

        Timestamp submittedAt = Timestamps.now();

        assertEq(proposal.id, proposalId);
        assertEq(proposal.executor, address(_executor));
        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, Timestamps.ZERO);
        assertEq(proposal.executedAt, Timestamps.ZERO);
        assertEq(proposal.calls.length, 1);
        assert(proposal.status == Status.Submitted);

        for (uint256 i = 0; i < proposal.calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }

        Proposals.schedule(_proposals, proposalId, Durations.ZERO);

        Timestamp scheduledAt = Timestamps.now();

        proposal = _proposals.get(proposalId);

        assertEq(proposal.id, proposalId);
        assertEq(proposal.executor, address(_executor));
        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, scheduledAt);
        assertEq(proposal.executedAt, Timestamps.ZERO);
        assertEq(proposal.calls.length, 1);
        assert(proposal.status == Status.Scheduled);

        for (uint256 i = 0; i < proposal.calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }

        Proposals.execute(_proposals, proposalId, Durations.ZERO);

        Timestamp executedAt = Timestamps.now();

        proposal = _proposals.get(proposalId);

        assertEq(proposal.id, proposalId);
        assertEq(proposal.executor, address(_executor));
        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, scheduledAt);
        assertEq(proposal.executedAt, executedAt);
        assertEq(proposal.calls.length, 1);
        assert(proposal.status == Status.Executed);

        for (uint256 i = 0; i < proposal.calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }
    }

    function test_get_cancelled_proposal() external {
        ExecutorCall[] memory calls = _getTargetRegularStaffCalls(address(_targetMock));
        Proposals.submit(_proposals, address(_executor), calls);
        uint256 proposalId = _proposals.count();

        Proposal memory proposal = _proposals.get(proposalId);

        Timestamp submittedAt = Timestamps.now();

        assertEq(proposal.id, proposalId);
        assertEq(proposal.executor, address(_executor));
        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, Timestamps.ZERO);
        assertEq(proposal.executedAt, Timestamps.ZERO);
        assertEq(proposal.calls.length, 1);
        assert(proposal.status == Status.Submitted);

        for (uint256 i = 0; i < proposal.calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }

        Proposals.cancelAll(_proposals);

        proposal = _proposals.get(proposalId);

        assertEq(proposal.id, proposalId);
        assertEq(proposal.executor, address(_executor));
        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, Timestamps.ZERO);
        assertEq(proposal.executedAt, Timestamps.ZERO);
        assertEq(proposal.calls.length, 1);
        assert(proposal.status == Status.Cancelled);

        for (uint256 i = 0; i < proposal.calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }
    }

    function testFuzz_get_not_existing_proposal(uint256 proposalId) external {
        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotFound.selector, proposalId));
        _proposals.get(proposalId);
    }

    function test_count_proposals() external {
        assertEq(_proposals.count(), 0);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        assertEq(_proposals.count(), 1);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        assertEq(_proposals.count(), 2);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        assertEq(_proposals.count(), 3);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        assertEq(_proposals.count(), 4);

        Proposals.schedule(_proposals, 1, Durations.ZERO);
        assertEq(_proposals.count(), 4);

        Proposals.schedule(_proposals, 2, Durations.ZERO);
        assertEq(_proposals.count(), 4);

        Proposals.execute(_proposals, 1, Durations.ZERO);
        assertEq(_proposals.count(), 4);

        Proposals.cancelAll(_proposals);
        assertEq(_proposals.count(), 4);
    }

    function test_can_execute_proposal() external {
        Duration delay = Durations.from(100 seconds);
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();

        assert(!_proposals.canExecute(proposalId, Durations.ZERO));

        Proposals.schedule(_proposals, proposalId, Durations.ZERO);

        assert(!_proposals.canExecute(proposalId, delay));

        _wait(delay);

        assert(_proposals.canExecute(proposalId, delay));

        Proposals.execute(_proposals, proposalId, Durations.ZERO);

        assert(!_proposals.canExecute(proposalId, delay));
    }

    function test_can_not_execute_cancelled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, Durations.ZERO);

        assert(_proposals.canExecute(proposalId, Durations.ZERO));
        Proposals.cancelAll(_proposals);

        assert(!_proposals.canExecute(proposalId, Durations.ZERO));
    }

    function test_can_schedule_proposal() external {
        Duration delay = Durations.from(100 seconds);
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        assert(!_proposals.canSchedule(proposalId, delay));

        _wait(delay);

        assert(_proposals.canSchedule(proposalId, delay));

        Proposals.schedule(_proposals, proposalId, delay);
        Proposals.execute(_proposals, proposalId, Durations.ZERO);

        assert(!_proposals.canSchedule(proposalId, delay));
    }

    function test_can_not_schedule_cancelled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        assert(_proposals.canSchedule(proposalId, Durations.ZERO));

        Proposals.cancelAll(_proposals);

        assert(!_proposals.canSchedule(proposalId, Durations.ZERO));
    }
}
