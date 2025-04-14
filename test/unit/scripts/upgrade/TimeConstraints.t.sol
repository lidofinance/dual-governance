// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";
import {TimeConstraints} from "scripts/upgrade/TimeConstraints.sol";

contract TimeConstraintsTest is Test {
    TimeConstraints public timeConstraints;

    // Monday, 1 January 2024 00:00:00
    uint256 private constant BASE_TIMESTAMP = 1704067200;

    function setUp() external {
        timeConstraints = new TimeConstraints();
    }

    function test_DAY_DURATION() external {
        assertEq(timeConstraints.DAY_DURATION().toSeconds(), 24 hours);
    }

    function test_getCurrentDayTime_HappyPath() external {
        vm.warp(BASE_TIMESTAMP);
        assertEq(timeConstraints.getCurrentDayTime().toSeconds(), 0);

        vm.warp(BASE_TIMESTAMP + 12 hours + 30 minutes + 45 seconds);
        assertEq(timeConstraints.getCurrentDayTime().toSeconds(), 12 hours + 30 minutes + 45 seconds);

        vm.warp(BASE_TIMESTAMP + 23 hours + 59 minutes + 59 seconds);
        assertEq(timeConstraints.getCurrentDayTime().toSeconds(), 23 hours + 59 minutes + 59 seconds);

        vm.warp(BASE_TIMESTAMP + 24 hours);
        assertEq(timeConstraints.getCurrentDayTime().toSeconds(), 0);
    }

    // checkTimeWithinDayTime

    function test_checkTimeWithinDayTime_HappyPath() external {
        vm.warp(BASE_TIMESTAMP + 15 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(12 hours), Durations.from(18 hours));

        vm.warp(BASE_TIMESTAMP + 12 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(12 hours), Durations.from(18 hours));

        vm.warp(BASE_TIMESTAMP + 18 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(12 hours), Durations.from(18 hours));

        vm.warp(BASE_TIMESTAMP + 12 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(12 hours), Durations.from(12 hours));
    }

    function test_checkTimeWithinDayTime_OutOfRange() public {
        uint256 baseTimestamp = BASE_TIMESTAMP;
        vm.warp(baseTimestamp + 10 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeConstraints.DayTimeOutOfRange.selector,
                Durations.from(10 hours),
                Durations.from(12 hours),
                Durations.from(18 hours)
            )
        );

        timeConstraints.checkTimeWithinDayTime(Durations.from(12 hours), Durations.from(18 hours));

        vm.warp(baseTimestamp + 20 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeConstraints.DayTimeOutOfRange.selector,
                Durations.from(20 hours),
                Durations.from(12 hours),
                Durations.from(18 hours)
            )
        );

        timeConstraints.checkTimeWithinDayTime(Durations.from(12 hours), Durations.from(18 hours));
    }

    function test_checkTimeWithinDayTime_TimeOverflow() external {
        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.DayTimeOverflow.selector));
        timeConstraints.checkTimeWithinDayTime(Durations.from(0), Durations.from(24 hours));

        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.DayTimeOverflow.selector));
        timeConstraints.checkTimeWithinDayTime(Durations.from(30 hours), Durations.from(12 hours));
    }

    function test_checkTimeWithinDayTime_InvalidRange() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TimeConstraints.InvalidDayTimeRange.selector, Durations.from(18 hours), Durations.from(12 hours)
            )
        );

        timeConstraints.checkTimeWithinDayTime(Durations.from(18 hours), Durations.from(12 hours));
    }

    // checkTimeWithinDayTimeAndEmit

    function test_checkTimeWithinDayTimeAndEmit_HappyPath() external {
        vm.warp(BASE_TIMESTAMP + 15 hours);
        vm.expectEmit(true, true, true, true);
        emit TimeConstraints.PerformedWithinDayTime(Durations.from(12 hours), Durations.from(18 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(12 hours), Durations.from(18 hours));

        vm.warp(BASE_TIMESTAMP + 12 hours);
        vm.expectEmit(true, true, true, true);
        emit TimeConstraints.PerformedWithinDayTime(Durations.from(12 hours), Durations.from(18 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(12 hours), Durations.from(18 hours));

        vm.warp(BASE_TIMESTAMP + 18 hours);
        vm.expectEmit(true, true, true, true);
        emit TimeConstraints.PerformedWithinDayTime(Durations.from(12 hours), Durations.from(18 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(12 hours), Durations.from(18 hours));

        vm.warp(BASE_TIMESTAMP + 12 hours);
        vm.expectEmit(true, true, true, true);
        emit TimeConstraints.PerformedWithinDayTime(Durations.from(12 hours), Durations.from(12 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(12 hours), Durations.from(12 hours));
    }

    // checkTimeAfterTimestamp

    function testFuzz_checkTimeAfterTimestamp_HappyPath(uint32 secondsAfter) public {
        vm.warp(BASE_TIMESTAMP + secondsAfter);
        timeConstraints.checkTimeAfterTimestamp(Timestamps.from(BASE_TIMESTAMP));
    }

    function testFuzz_checkTimeAfterTimestamp_NotReached(uint32 secondsBefore) public {
        vm.assume(secondsBefore < BASE_TIMESTAMP && secondsBefore > 0);

        vm.warp(BASE_TIMESTAMP - secondsBefore);
        vm.expectRevert(
            abi.encodeWithSelector(TimeConstraints.TimestampNotReached.selector, Timestamps.from(BASE_TIMESTAMP))
        );
        timeConstraints.checkTimeAfterTimestamp(Timestamps.from(BASE_TIMESTAMP));
    }

    // checkTimeAfterTimestampAndEmit

    function testFuzz_checkTimeAfterTimestampAndEmit_HappyPath(uint32 secondsAfter) public {
        vm.warp(BASE_TIMESTAMP + secondsAfter);
        vm.expectEmit(true, true, true, true);
        emit TimeConstraints.PerformedAfterTimestamp(Timestamps.from(BASE_TIMESTAMP));
        timeConstraints.checkTimeAfterTimestampAndEmit(Timestamps.from(BASE_TIMESTAMP));
    }

    // checkTimeBeforeTimestamp

    function test_checkTimeBeforeTimestamp_HappyPath() public {
        vm.warp(BASE_TIMESTAMP);
        timeConstraints.checkTimeBeforeTimestamp(Timestamps.from(BASE_TIMESTAMP));

        vm.warp(BASE_TIMESTAMP - 1 hours);
        timeConstraints.checkTimeBeforeTimestamp(Timestamps.from(BASE_TIMESTAMP));
    }

    function testFuzz_checkTimeBeforeTimestamp_Exceed(uint32 secondsAfter) public {
        vm.assume(secondsAfter > 0);

        vm.warp(BASE_TIMESTAMP + secondsAfter);
        vm.expectRevert(
            abi.encodeWithSelector(TimeConstraints.TimestampExceeded.selector, Timestamps.from(BASE_TIMESTAMP))
        );
        timeConstraints.checkTimeBeforeTimestamp(Timestamps.from(BASE_TIMESTAMP));
    }

    // checkTimeBeforeTimestampAndEmit

    function testFuzz_checkTimeBeforeTimestampAndEmit_HappyPath() public {
        vm.warp(BASE_TIMESTAMP);
        vm.expectEmit(true, true, true, true);
        emit TimeConstraints.PerformedBeforeTimestamp(Timestamps.from(BASE_TIMESTAMP));
        timeConstraints.checkTimeBeforeTimestampAndEmit(Timestamps.from(BASE_TIMESTAMP));

        vm.warp(BASE_TIMESTAMP - 1 hours);
        vm.expectEmit(true, true, true, true);
        emit TimeConstraints.PerformedBeforeTimestamp(Timestamps.from(BASE_TIMESTAMP));
        timeConstraints.checkTimeBeforeTimestampAndEmit(Timestamps.from(BASE_TIMESTAMP));
    }
}
