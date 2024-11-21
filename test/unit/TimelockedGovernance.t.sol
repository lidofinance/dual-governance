// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";

import {UnitTest} from "test/utils/unit-test.sol";

import {TimelockMock} from "../mocks/TimelockMock.sol";

contract TimelockedGovernanceUnitTests is UnitTest {
    TimelockMock private _timelock;
    TimelockedGovernance private _timelockedGovernance;

    address private _emergencyGovernance = makeAddr("EMERGENCY_GOVERNANCE");
    address private _governance = makeAddr("GOVERNANCE");
    address private _adminExecutor = makeAddr("ADMIN_EXECUTOR");

    function setUp() external {
        _timelock = new TimelockMock(_adminExecutor);
        _timelockedGovernance = new TimelockedGovernance(_governance, _timelock);
    }

    function testFuzz_constructor(address governance, ITimelock timelock) external {
        TimelockedGovernance instance = new TimelockedGovernance(governance, timelock);

        assertEq(instance.GOVERNANCE(), governance);
        assertEq(address(instance.TIMELOCK()), address(timelock));
    }

    function test_submit_proposal() external {
        assertEq(_timelock.getSubmittedProposals().length, 0);

        vm.prank(_governance);
        _timelockedGovernance.submitProposal(_getMockTargetRegularStaffCalls(address(0x1)), "");

        assertEq(_timelock.getSubmittedProposals().length, 1);
    }

    function testFuzz_stranger_cannot_submit_proposal(address stranger) external {
        vm.assume(stranger != address(0) && stranger != _governance);

        assertEq(_timelock.getSubmittedProposals().length, 0);

        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockedGovernance.CallerIsNotGovernance.selector, [stranger]));
        _timelockedGovernance.submitProposal(_getMockTargetRegularStaffCalls(address(0x1)), "");

        assertEq(_timelock.getSubmittedProposals().length, 0);
    }

    function test_schedule_proposal() external {
        assertEq(_timelock.getScheduledProposals().length, 0);

        vm.prank(_governance);
        _timelockedGovernance.submitProposal(_getMockTargetRegularStaffCalls(address(0x1)), "");

        _timelock.setSchedule(1);
        _timelockedGovernance.scheduleProposal(1);

        assertEq(_timelock.getScheduledProposals().length, 1);
    }

    function test_execute_proposal() external {
        assertEq(_timelock.getExecutedProposals().length, 0);

        vm.prank(_governance);
        _timelockedGovernance.submitProposal(_getMockTargetRegularStaffCalls(address(0x1)), "");

        _timelock.setSchedule(1);
        _timelockedGovernance.scheduleProposal(1);

        _timelock.setExecutable(1);
        _timelockedGovernance.executeProposal(1);

        assertEq(_timelock.getExecutedProposals().length, 1);
    }

    function test_cancel_all_pending_proposals() external {
        assertEq(_timelock.getLastCancelledProposalId(), 0);

        vm.startPrank(_governance);
        _timelockedGovernance.submitProposal(_getMockTargetRegularStaffCalls(address(0x1)), "");
        _timelockedGovernance.submitProposal(_getMockTargetRegularStaffCalls(address(0x1)), "");

        _timelock.setSchedule(1);
        _timelockedGovernance.scheduleProposal(1);

        bool isProposalsCancelled = _timelockedGovernance.cancelAllPendingProposals();

        assertTrue(isProposalsCancelled);
        assertEq(_timelock.getLastCancelledProposalId(), 2);
    }

    function testFuzz_stranger_cannot_cancel_all_pending_proposals(address stranger) external {
        vm.assume(stranger != address(0) && stranger != _governance);

        assertEq(_timelock.getLastCancelledProposalId(), 0);

        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockedGovernance.CallerIsNotGovernance.selector, [stranger]));
        _timelockedGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getLastCancelledProposalId(), 0);
    }

    function test_can_schedule() external {
        vm.prank(_governance);
        _timelockedGovernance.submitProposal(_getMockTargetRegularStaffCalls(address(0x1)), "");

        assertFalse(_timelockedGovernance.canScheduleProposal(1));

        _timelock.setSchedule(1);

        assertTrue(_timelockedGovernance.canScheduleProposal(1));
    }
}
