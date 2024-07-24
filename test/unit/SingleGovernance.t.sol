// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";

import {Executor} from "contracts/Executor.sol";
import {SingleGovernance} from "contracts/SingleGovernance.sol";
import {IConfigurableTimelock, IEmergencyProtectedTimelockConfig} from "contracts/interfaces/ITimelock.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {TargetMock} from "test/utils/utils.sol";

import {TimelockMock} from "./mocks/TimelockMock.sol";
import {TimelockedGovernanceSubsystemConfig} from "contracts/configuration/TimelockedGovernanceSubsystemConfig.sol";

contract ConfigurableTimelockMock is TimelockMock, IConfigurableTimelock {
    IEmergencyProtectedTimelockConfig public immutable CONFIG;

    constructor(IEmergencyProtectedTimelockConfig config) {
        CONFIG = config;
    }
}

contract SingleGovernanceUnitTests is UnitTest {
    TimelockMock private _timelock;
    SingleGovernance private _singleGovernance;
    TimelockedGovernanceSubsystemConfig private _config;

    address private _emergencyGovernance = makeAddr("EMERGENCY_GOVERNANCE");
    address private _governance = makeAddr("GOVERNANCE");

    function setUp() external {
        Executor _executor = new Executor(address(this));
        _config =
            new TimelockedGovernanceSubsystemConfig(address(_executor), _emergencyGovernance, address(0), address(0));
        _timelock = new ConfigurableTimelockMock(_config);
        _singleGovernance = new SingleGovernance(_governance, address(_timelock));
    }

    function testFuzz_constructor(address governance, address timelock) external {
        SingleGovernance instance = new SingleGovernance(governance, timelock);

        assertEq(instance.GOVERNANCE(), governance);
        assertEq(address(instance.TIMELOCK()), address(timelock));
    }

    function test_submit_proposal() external {
        assertEq(_timelock.getSubmittedProposals().length, 0);

        vm.prank(_governance);
        _singleGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        assertEq(_timelock.getSubmittedProposals().length, 1);
    }

    function testFuzz_stranger_cannot_submit_proposal(address stranger) external {
        vm.assume(stranger != address(0) && stranger != _governance);

        assertEq(_timelock.getSubmittedProposals().length, 0);

        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(SingleGovernance.NotGovernance.selector, [stranger]));
        _singleGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        assertEq(_timelock.getSubmittedProposals().length, 0);
    }

    function test_schedule_proposal() external {
        assertEq(_timelock.getScheduledProposals().length, 0);

        vm.prank(_governance);
        _singleGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        _timelock.setSchedule(1);
        _singleGovernance.scheduleProposal(1);

        assertEq(_timelock.getScheduledProposals().length, 1);
    }

    function test_execute_proposal() external {
        assertEq(_timelock.getExecutedProposals().length, 0);

        vm.prank(_governance);
        _singleGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        _timelock.setSchedule(1);
        _singleGovernance.scheduleProposal(1);

        _singleGovernance.executeProposal(1);

        assertEq(_timelock.getExecutedProposals().length, 1);
    }

    function test_cancel_all_pending_proposals() external {
        assertEq(_timelock.getLastCancelledProposalId(), 0);

        vm.startPrank(_governance);
        _singleGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));
        _singleGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        _timelock.setSchedule(1);
        _singleGovernance.scheduleProposal(1);

        _singleGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getLastCancelledProposalId(), 2);
    }

    function testFuzz_stranger_cannot_cancel_all_pending_proposals(address stranger) external {
        vm.assume(stranger != address(0) && stranger != _governance);

        assertEq(_timelock.getLastCancelledProposalId(), 0);

        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(SingleGovernance.NotGovernance.selector, [stranger]));
        _singleGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getLastCancelledProposalId(), 0);
    }

    function test_can_schedule() external {
        vm.prank(_governance);
        _singleGovernance.submitProposal(_getTargetRegularStaffCalls(address(0x1)));

        assertFalse(_singleGovernance.canScheduleProposal(1));

        _timelock.setSchedule(1);

        assertTrue(_singleGovernance.canScheduleProposal(1));
    }
}
