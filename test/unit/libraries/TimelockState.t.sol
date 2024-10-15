// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TimelockState} from "contracts/libraries/TimelockState.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract TimelockStateUnitTests is UnitTest {
    using TimelockState for TimelockState.Context;

    TimelockState.Context internal _timelockState;

    address internal governance = makeAddr("governance");
    address internal adminExecutor = makeAddr("adminExecutor");
    Duration internal afterSubmitDelay = Durations.from(1 days);
    Duration internal afterScheduleDelay = Durations.from(2 days);

    Duration internal maxAfterSubmitDelay = Durations.from(10 days);
    Duration internal maxAfterScheduleDelay = Durations.from(20 days);

    function setUp() external {
        TimelockState.setGovernance(_timelockState, governance);
        TimelockState.setAdminExecutor(_timelockState, adminExecutor);
        TimelockState.setAfterSubmitDelay(_timelockState, afterSubmitDelay, maxAfterSubmitDelay);
        TimelockState.setAfterScheduleDelay(_timelockState, afterScheduleDelay, maxAfterScheduleDelay);
    }

    function testFuzz_setGovernance_HappyPath(address newGovernance) external {
        vm.assume(newGovernance != address(0) && newGovernance != governance);

        vm.expectEmit();
        emit TimelockState.GovernanceSet(newGovernance);

        TimelockState.setGovernance(_timelockState, newGovernance);
    }

    function test_setGovernance_RevertOn_ZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidGovernance.selector, address(0)));
        TimelockState.setGovernance(_timelockState, address(0));
    }

    function test_setGovernance_RevertOn_SameAddress() external {
        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidGovernance.selector, governance));
        TimelockState.setGovernance(_timelockState, governance);
    }

    function testFuzz_setAfterSubmitDelay_HappyPath(Duration newAfterSubmitDelay) external {
        vm.assume(newAfterSubmitDelay <= maxAfterSubmitDelay && newAfterSubmitDelay != afterSubmitDelay);

        vm.expectEmit();
        emit TimelockState.AfterSubmitDelaySet(newAfterSubmitDelay);

        TimelockState.setAfterSubmitDelay(_timelockState, newAfterSubmitDelay, maxAfterSubmitDelay);
    }

    function test_setAfterSubmitDelay_RevertOn_GreaterThanMax() external {
        vm.expectRevert(
            abi.encodeWithSelector(TimelockState.InvalidAfterSubmitDelay.selector, maxAfterSubmitDelay.plusSeconds(1))
        );
        TimelockState.setAfterSubmitDelay(_timelockState, maxAfterSubmitDelay.plusSeconds(1), maxAfterSubmitDelay);
    }

    function test_setAfterSubmitDelay_RevertOn_SameValue() external {
        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidAfterSubmitDelay.selector, afterSubmitDelay));
        TimelockState.setAfterSubmitDelay(_timelockState, afterSubmitDelay, maxAfterSubmitDelay);
    }

    function testFuzz_setAfterScheduleDelay_HappyPath(Duration newAfterScheduleDelay) external {
        vm.assume(newAfterScheduleDelay <= maxAfterScheduleDelay && newAfterScheduleDelay != afterScheduleDelay);

        vm.expectEmit();
        emit TimelockState.AfterScheduleDelaySet(newAfterScheduleDelay);

        TimelockState.setAfterScheduleDelay(_timelockState, newAfterScheduleDelay, maxAfterScheduleDelay);
    }

    function test_setAfterScheduleDelay_RevertOn_GreaterThanMax() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockState.InvalidAfterScheduleDelay.selector, maxAfterScheduleDelay.plusSeconds(1)
            )
        );
        TimelockState.setAfterScheduleDelay(_timelockState, maxAfterScheduleDelay.plusSeconds(1), maxAfterScheduleDelay);
    }

    function test_setAfterScheduleDelay_RevertOn_SameValue() external {
        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidAfterScheduleDelay.selector, afterScheduleDelay));
        TimelockState.setAfterScheduleDelay(_timelockState, afterScheduleDelay, maxAfterScheduleDelay);
    }

    function testFuzz_setAdminExecutor_HappyPath(address newAdminExecutor) external {
        vm.assume(newAdminExecutor != address(0) && newAdminExecutor != adminExecutor);

        vm.expectEmit();
        emit TimelockState.AdminExecutorSet(newAdminExecutor);

        TimelockState.setAdminExecutor(_timelockState, newAdminExecutor);
    }

    function test_setAdminExecutor_RevertOn_ZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidAdminExecutor.selector, address(0)));
        TimelockState.setAdminExecutor(_timelockState, address(0));
    }

    function test_setAdminExecutor_RevertOn_SameAddress() external {
        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidAdminExecutor.selector, adminExecutor));
        TimelockState.setAdminExecutor(_timelockState, adminExecutor);
    }

    function testFuzz_getAfterSubmitDelay_HappyPath(Duration newAfterSubmitDelay) external {
        TimelockState.setAfterSubmitDelay(_timelockState, newAfterSubmitDelay, newAfterSubmitDelay);
        assertEq(TimelockState.getAfterSubmitDelay(_timelockState), newAfterSubmitDelay);
    }

    function testFuzz_getAfterScheduleDelay_HappyPath(Duration newAfterScheduleDelay) external {
        TimelockState.setAfterScheduleDelay(_timelockState, newAfterScheduleDelay, newAfterScheduleDelay);
        assertEq(TimelockState.getAfterScheduleDelay(_timelockState), newAfterScheduleDelay);
    }

    function test_checkCallerIsGovernance_HappyPath() external {
        vm.prank(governance);
        this.external__checkCallerIsGovernance();
    }

    function testFuzz_checkCallerIsGovernance_RevertOn_NonGovernance(address caller) external {
        vm.assume(caller != governance);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, caller));
        vm.prank(caller);
        this.external__checkCallerIsGovernance();
    }

    function external__checkCallerIsGovernance() external {
        TimelockState.checkCallerIsGovernance(_timelockState);
    }
}
