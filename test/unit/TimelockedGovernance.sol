// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";

import {Executor} from "contracts/Executor.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {IConfiguration, Configuration} from "contracts/Configuration.sol";
import {ExecutorCall} from "contracts/libraries/Proposals.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {TargetMock} from "test/utils/utils.sol";

import {TimelockMock} from "./mocks/TimelockMock.sol";

contract SingleGovernanceUnitTests is UnitTest {
    TimelockMock private _timelock;
    TimelockedGovernance private _timelockedGovernance;
    Configuration private _config;

    address private _emergencyGovernance = makeAddr("EMERGENCY_GOVERNANCE");
    address private _governance = makeAddr("GOVERNANCE");

    function setUp() external {
        Executor _executor = new Executor(address(this));
        _config = new Configuration(address(_executor), _emergencyGovernance, new address[](0));
        _timelock = new TimelockMock();
        _timelockedGovernance = new TimelockedGovernance(address(_config), _governance, address(_timelock));
    }

    function testFuzz_constructor(address governance, address timelock) external {
        TimelockedGovernance instance = new TimelockedGovernance(address(_config), governance, timelock);

        assertEq(instance.GOVERNANCE(), governance);
        assertEq(address(instance.TIMELOCK()), address(timelock));
    }

    function test_submit_proposal() external {
        assertEq(_timelock.getSubmittedProposals().length, 0);

        vm.prank(_governance);
        _timelockedGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        assertEq(_timelock.getSubmittedProposals().length, 1);
    }

    function testFuzz_stranger_cannot_submit_proposal(address stranger) external {
        vm.assume(stranger != address(0) && stranger != _governance);

        assertEq(_timelock.getSubmittedProposals().length, 0);

        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockedGovernance.NotGovernance.selector, [stranger]));
        _timelockedGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        assertEq(_timelock.getSubmittedProposals().length, 0);
    }

    function test_schedule_proposal() external {
        assertEq(_timelock.getScheduledProposals().length, 0);

        vm.prank(_governance);
        _timelockedGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        _timelock.setSchedule(1);
        _timelockedGovernance.scheduleProposal(1);

        assertEq(_timelock.getScheduledProposals().length, 1);
    }

    function test_execute_proposal() external {
        assertEq(_timelock.getExecutedProposals().length, 0);

        vm.prank(_governance);
        _timelockedGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        _timelock.setSchedule(1);
        _timelockedGovernance.scheduleProposal(1);

        _timelockedGovernance.executeProposal(1);

        assertEq(_timelock.getExecutedProposals().length, 1);
    }

    function test_cancel_all_pending_proposals() external {
        assertEq(_timelock.getLastCancelledProposalId(), 0);

        vm.startPrank(_governance);
        _timelockedGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));
        _timelockedGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        _timelock.setSchedule(1);
        _timelockedGovernance.scheduleProposal(1);

        _timelockedGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getLastCancelledProposalId(), 2);
    }

    function testFuzz_stranger_cannot_cancel_all_pending_proposals(address stranger) external {
        vm.assume(stranger != address(0) && stranger != _governance);

        assertEq(_timelock.getLastCancelledProposalId(), 0);

        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockedGovernance.NotGovernance.selector, [stranger]));
        _timelockedGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getLastCancelledProposalId(), 0);
    }

    function test_can_schedule() external {
        vm.prank(_governance);
        _timelockedGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        assertFalse(_timelockedGovernance.canSchedule(1));

        _timelock.setSchedule(1);

        assertTrue(_timelockedGovernance.canSchedule(1));
    }
}
