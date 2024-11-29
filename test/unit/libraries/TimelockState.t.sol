// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TimelockState} from "contracts/libraries/TimelockState.sol";
import {Duration, Durations, MAX_DURATION_VALUE, DurationOverflow} from "contracts/types/Duration.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract TimelockStateUnitTests is UnitTest {
    using TimelockState for TimelockState.Context;

    TimelockState.Context internal _timelockState;

    address internal governance = makeAddr("governance");
    Duration internal afterSubmitDelay = Durations.from(1 days);
    Duration internal afterScheduleDelay = Durations.from(2 days);

    Duration internal maxAfterSubmitDelay = Durations.from(10 days);
    Duration internal maxAfterScheduleDelay = Durations.from(20 days);

    function setUp() external {
        TimelockState.setGovernance(_timelockState, governance);
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

    // ---
    // checkExecutionDelay()
    // ---

    function test_checkExecutionDelay_HappyPath_Positive() external {
        assertTrue(_timelockState.afterSubmitDelay > Durations.ZERO);
        assertTrue(_timelockState.afterScheduleDelay > Durations.ZERO);

        // regular case
        Duration minExecutionDelay = (_timelockState.afterSubmitDelay + _timelockState.afterScheduleDelay).dividedBy(2);
        this.external__checkExecutionDelay(minExecutionDelay);

        // edge case, when minExecutionDelay equal to sum of after submit and after schedule delays
        minExecutionDelay = _timelockState.afterSubmitDelay + _timelockState.afterScheduleDelay;
        this.external__checkExecutionDelay(minExecutionDelay);

        // edge case, when minExecutionDelay is zero while after submit and after schedule is not
        minExecutionDelay = Durations.ZERO;
        this.external__checkExecutionDelay(minExecutionDelay);

        // edge case, when minExecutionDelay, afterSubmitDelay and afterScheduleDelay is zero
        minExecutionDelay = Durations.ZERO;
        _timelockState.afterSubmitDelay = Durations.ZERO;
        _timelockState.afterScheduleDelay = Durations.ZERO;
        this.external__checkExecutionDelay(minExecutionDelay);

        // edge case with MAX_DURATION_VALUE
        minExecutionDelay = Durations.from(MAX_DURATION_VALUE);

        _timelockState.afterSubmitDelay = Durations.ZERO;
        _timelockState.afterScheduleDelay = Durations.from(MAX_DURATION_VALUE);
        this.external__checkExecutionDelay(minExecutionDelay);

        _timelockState.afterSubmitDelay = Durations.from(MAX_DURATION_VALUE);
        _timelockState.afterScheduleDelay = Durations.ZERO;
        this.external__checkExecutionDelay(minExecutionDelay);
    }

    function test_checkExecutionDelay_HappyPath_Negative() external {
        assertTrue(_timelockState.afterSubmitDelay > Durations.ZERO);
        assertTrue(_timelockState.afterScheduleDelay > Durations.ZERO);

        // regular case
        Duration minExecutionDelay =
            _timelockState.afterSubmitDelay + _timelockState.afterScheduleDelay + Durations.from(1 seconds);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockState.InvalidExecutionDelay.selector,
                _timelockState.afterSubmitDelay + _timelockState.afterScheduleDelay
            )
        );
        this.external__checkExecutionDelay(minExecutionDelay);

        // edge case afterSubmitDelay and afterScheduleDelay is zero while minExecutionDelay is not
        minExecutionDelay = Durations.from(1 seconds);
        _timelockState.afterSubmitDelay = Durations.ZERO;
        _timelockState.afterScheduleDelay = Durations.ZERO;

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockState.InvalidExecutionDelay.selector,
                _timelockState.afterSubmitDelay + _timelockState.afterScheduleDelay
            )
        );
        this.external__checkExecutionDelay(minExecutionDelay);

        // edge case afterSubmitDelay + afterScheduleDelay sum overflows Duration max value
        minExecutionDelay = Durations.from(MAX_DURATION_VALUE);
        _timelockState.afterSubmitDelay = Durations.from(1 seconds);
        _timelockState.afterScheduleDelay = Durations.from(MAX_DURATION_VALUE);

        vm.expectRevert(abi.encodeWithSelector(DurationOverflow.selector));
        this.external__checkExecutionDelay(minExecutionDelay);
    }

    function testFuzz_checkExecutionDelay_Positive(
        Duration minExecutionDelay,
        Duration afterSubmitDelay,
        Duration afterScheduleDelay
    ) external {
        vm.assume(afterSubmitDelay.toSeconds() + afterScheduleDelay.toSeconds() <= MAX_DURATION_VALUE);
        vm.assume(minExecutionDelay <= afterSubmitDelay + afterScheduleDelay);

        _timelockState.afterSubmitDelay = afterSubmitDelay;
        _timelockState.afterScheduleDelay = afterScheduleDelay;
        this.external__checkExecutionDelay(minExecutionDelay);
    }

    function testFuzz_checkExecutionDelay_Negative(
        Duration minExecutionDelay,
        Duration afterSubmitDelay,
        Duration afterScheduleDelay
    ) external {
        vm.assume(afterSubmitDelay.toSeconds() + afterScheduleDelay.toSeconds() <= MAX_DURATION_VALUE);
        vm.assume(minExecutionDelay > afterSubmitDelay + afterScheduleDelay);

        _timelockState.afterSubmitDelay = afterSubmitDelay;
        _timelockState.afterScheduleDelay = afterScheduleDelay;

        vm.expectRevert(
            abi.encodeWithSelector(TimelockState.InvalidExecutionDelay.selector, afterSubmitDelay + afterScheduleDelay)
        );
        this.external__checkExecutionDelay(minExecutionDelay);
    }

    function testFuzz_checkExecutionDelay_DurationOverflow(
        Duration minExecutionDelay,
        Duration afterSubmitDelay,
        Duration afterScheduleDelay
    ) external {
        vm.assume(afterSubmitDelay.toSeconds() + afterScheduleDelay.toSeconds() > MAX_DURATION_VALUE);

        _timelockState.afterSubmitDelay = afterSubmitDelay;
        _timelockState.afterScheduleDelay = afterScheduleDelay;

        vm.expectRevert(abi.encodeWithSelector(DurationOverflow.selector));
        this.external__checkExecutionDelay(minExecutionDelay);
    }

    // ---
    // Helper Methods
    // ---

    function external__checkCallerIsGovernance() external {
        TimelockState.checkCallerIsGovernance(_timelockState);
    }

    function external__checkExecutionDelay(Duration minExecutionDelay) external {
        _timelockState.checkExecutionDelay(minExecutionDelay);
    }
}
