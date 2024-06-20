// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Vm} from "forge-std/Test.sol";

import {Executor} from "contracts/Executor.sol";
import {Proposals, ExecutorCall, Proposal, Status} from "contracts/libraries/Proposals.sol";

import {TargetMock} from "test/utils/utils.sol";
import {UnitTest} from "test/utils/unit-test.sol";
import {IDangerousContract} from "test/utils/interfaces.sol";
import {ExecutorCallHelpers} from "test/utils/executor-calls.sol";

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
        assertEq(proposal.submittedAt, block.timestamp);
        assertEq(proposal.executedAt, 0);
        assertEq(proposal.scheduledAt, 0);
        assertEq(proposal.calls.length, 1);

        for (uint256 i = 0; i < proposal.calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }
    }

    function testFuzz_schedule_proposal(uint256 delay) external {
        vm.assume(delay > 0 && delay < type(uint40).max);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        Proposals.ProposalPacked memory proposal = _proposals.proposals[0];

        uint256 submittedAt = block.timestamp;

        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, 0);
        assertEq(proposal.executedAt, 0);

        uint256 proposalId = _proposals.count();

        _wait(delay);

        vm.expectEmit();
        emit Proposals.ProposalScheduled(proposalId);
        Proposals.schedule(_proposals, proposalId, delay);

        proposal = _proposals.proposals[0];

        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, block.timestamp);
        assertEq(proposal.executedAt, 0);
    }

    function testFuzz_cannot_schedule_unsubmitted_proposal(uint256 proposalId) external {
        vm.assume(proposalId > 0);

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, proposalId));
        Proposals.schedule(_proposals, proposalId, 0);
    }

    function test_cannot_schedule_proposal_twice() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = 1;
        Proposals.schedule(_proposals, proposalId, 0);

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, proposalId));
        Proposals.schedule(_proposals, proposalId, 0);
    }

    function testFuzz_cannot_schedule_proposal_before_delay_passed(uint256 delay) external {
        vm.assume(delay > 0 && delay < type(uint40).max);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));

        _wait(delay - 1);

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterSubmitDelayNotPassed.selector, PROPOSAL_ID_OFFSET));
        Proposals.schedule(_proposals, PROPOSAL_ID_OFFSET, delay);
    }

    function test_cannot_schedule_cancelled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        Proposals.cancelAll(_proposals);

        uint256 proposalId = _proposals.count();

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, proposalId));
        Proposals.schedule(_proposals, proposalId, 0);
    }

    function testFuzz_execute_proposal(uint256 delay) external {
        vm.assume(delay > 0 && delay < type(uint40).max);

        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, 0);

        uint256 submittedAndScheduledAt = block.timestamp;

        assertEq(_proposals.proposals[0].submittedAt, submittedAndScheduledAt);
        assertEq(_proposals.proposals[0].scheduledAt, submittedAndScheduledAt);
        assertEq(_proposals.proposals[0].executedAt, 0);

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
        assertEq(proposal.executedAt, block.timestamp);
    }

    function testFuzz_cannot_execute_unsubmitted_proposal(uint256 proposalId) external {
        vm.assume(proposalId > 0);
        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotScheduled.selector, proposalId));
        Proposals.execute(_proposals, proposalId, 0);
    }

    function test_cannot_execute_unscheduled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotScheduled.selector, proposalId));
        Proposals.execute(_proposals, proposalId, 0);
    }

    function test_cannot_execute_twice() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, 0);
        Proposals.execute(_proposals, proposalId, 0);

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotScheduled.selector, proposalId));
        Proposals.execute(_proposals, proposalId, 0);
    }

    function test_cannot_execute_cancelled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, 0);
        Proposals.cancelAll(_proposals);

        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotScheduled.selector, proposalId));
        Proposals.execute(_proposals, proposalId, 0);
    }

    function testFuzz_cannot_execute_before_delay_passed(uint256 delay) external {
        vm.assume(delay > 0 && delay < type(uint40).max);
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, 0);

        _wait(delay - 1);

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterScheduleDelayNotPassed.selector, proposalId));
        Proposals.execute(_proposals, proposalId, delay);
    }

    function test_cancel_all_proposals() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));

        uint256 proposalsCount = _proposals.count();

        Proposals.schedule(_proposals, proposalsCount, 0);

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

        uint256 submittedAt = block.timestamp;

        assertEq(proposal.id, proposalId);
        assertEq(proposal.executor, address(_executor));
        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, 0);
        assertEq(proposal.executedAt, 0);
        assertEq(proposal.calls.length, 1);
        assert(proposal.status == Status.Submitted);

        for (uint256 i = 0; i < proposal.calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }

        Proposals.schedule(_proposals, proposalId, 0);

        uint256 scheduledAt = block.timestamp;

        proposal = _proposals.get(proposalId);

        assertEq(proposal.id, proposalId);
        assertEq(proposal.executor, address(_executor));
        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, scheduledAt);
        assertEq(proposal.executedAt, 0);
        assertEq(proposal.calls.length, 1);
        assert(proposal.status == Status.Scheduled);

        for (uint256 i = 0; i < proposal.calls.length; i++) {
            assertEq(proposal.calls[i].target, address(_targetMock));
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }

        Proposals.execute(_proposals, proposalId, 0);

        uint256 executedAt = block.timestamp;

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

        uint256 submittedAt = block.timestamp;

        assertEq(proposal.id, proposalId);
        assertEq(proposal.executor, address(_executor));
        assertEq(proposal.submittedAt, submittedAt);
        assertEq(proposal.scheduledAt, 0);
        assertEq(proposal.executedAt, 0);
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
        assertEq(proposal.scheduledAt, 0);
        assertEq(proposal.executedAt, 0);
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

        Proposals.schedule(_proposals, 1, 0);
        assertEq(_proposals.count(), 4);

        Proposals.schedule(_proposals, 2, 0);
        assertEq(_proposals.count(), 4);

        Proposals.execute(_proposals, 1, 0);
        assertEq(_proposals.count(), 4);

        Proposals.cancelAll(_proposals);
        assertEq(_proposals.count(), 4);
    }

    function test_can_execute_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();

        assert(!_proposals.canExecute(proposalId, 0));

        Proposals.schedule(_proposals, proposalId, 0);

        assert(!_proposals.canExecute(proposalId, 100));

        _wait(100);

        assert(_proposals.canExecute(proposalId, 100));

        Proposals.execute(_proposals, proposalId, 0);

        assert(!_proposals.canExecute(proposalId, 100));
    }

    function test_can_not_execute_cancelled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        Proposals.schedule(_proposals, proposalId, 0);

        assert(_proposals.canExecute(proposalId, 0));
        Proposals.cancelAll(_proposals);

        assert(!_proposals.canExecute(proposalId, 0));
    }

    function test_can_schedule_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        assert(!_proposals.canSchedule(proposalId, 100));

        _wait(100);

        assert(_proposals.canSchedule(proposalId, 100));

        Proposals.schedule(_proposals, proposalId, 100);
        Proposals.execute(_proposals, proposalId, 0);

        assert(!_proposals.canSchedule(proposalId, 100));
    }

    function test_can_not_schedule_cancelled_proposal() external {
        Proposals.submit(_proposals, address(_executor), _getTargetRegularStaffCalls(address(_targetMock)));
        uint256 proposalId = _proposals.count();
        assert(_proposals.canSchedule(proposalId, 0));

        Proposals.cancelAll(_proposals);

        assert(!_proposals.canSchedule(proposalId, 0));
    }
}
