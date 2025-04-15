// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp, toSeconds} from "contracts/types/Timestamp.sol";
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

    function testFuzz_checkTimeWithinDayTime_HappyPath_Regular(
        Duration from,
        Duration to,
        Duration timeToWarp
    ) external {
        vm.assume(to < timeConstraints.DAY_DURATION());
        vm.assume(from <= timeToWarp && timeToWarp <= to);
        vm.warp(timeToWarp.toSeconds());
        timeConstraints.checkTimeWithinDayTime(from, to);
    }

    function testFuzz_checkTimeWithinDayTime_HappyPath_Overnight(
        Duration from,
        Duration to,
        Duration timeToWarp
    ) external {
        vm.assume(from < timeConstraints.DAY_DURATION() && to < from);
        vm.assume(timeToWarp <= to || timeToWarp >= from);
        vm.assume(timeToWarp < timeConstraints.DAY_DURATION());

        vm.warp(timeToWarp.toSeconds());
        timeConstraints.checkTimeWithinDayTime(from, to);
    }

    function testFuzz_checkTimeWithinDayTime_OutOfRange_Regular(
        Duration startTime,
        Duration endTime,
        Duration currentTime
    ) public {
        vm.assume(startTime < endTime);
        vm.assume(startTime.toSeconds() < 24 hours);
        vm.assume(endTime.toSeconds() < 24 hours);
        vm.assume(currentTime.toSeconds() < 24 hours);
        vm.assume(currentTime < startTime || currentTime > endTime);

        vm.warp(BASE_TIMESTAMP + currentTime.toSeconds());

        vm.expectRevert(
            abi.encodeWithSelector(TimeConstraints.DayTimeOutOfRange.selector, currentTime, startTime, endTime)
        );
        timeConstraints.checkTimeWithinDayTime(startTime, endTime);
    }

    function testFuzz_checkTimeWithinDayTime_OutOfRange_Overnight(
        Duration startTime,
        Duration endTime,
        Duration currentTime
    ) public {
        vm.assume(startTime > endTime);
        vm.assume(startTime.toSeconds() < 24 hours);
        vm.assume(endTime.toSeconds() < 24 hours);
        vm.assume(currentTime.toSeconds() < 24 hours);
        vm.assume(currentTime > endTime && currentTime < startTime);

        vm.warp(BASE_TIMESTAMP + currentTime.toSeconds());

        vm.expectRevert(
            abi.encodeWithSelector(TimeConstraints.DayTimeOutOfRange.selector, currentTime, startTime, endTime)
        );
        this.external__checkTimeWithinDayTime(startTime, endTime);
    }

    function test_checkTimeWithinDayTime_TimeOverflow() external {
        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.DayTimeOverflow.selector));
        this.external__checkTimeWithinDayTime(Durations.from(0), Durations.from(24 hours));

        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.DayTimeOverflow.selector));
        this.external__checkTimeWithinDayTime(Durations.from(30 hours), Durations.from(12 hours));
    }

    // checkTimeWithinDayTimeAndEmit

    function testFuzz_checkTimeWithinDayTimeAndEmit_HappyPath_Regular(
        Duration from,
        Duration to,
        Duration timeToWarp
    ) external {
        vm.assume(to < timeConstraints.DAY_DURATION());
        vm.assume(from <= timeToWarp && timeToWarp <= to);
        vm.warp(timeToWarp.toSeconds());
        vm.expectEmit();
        emit TimeConstraints.TimeWithinDayTimeChecked(from, to);
        timeConstraints.checkTimeWithinDayTimeAndEmit(from, to);
    }

    function testFuzz_checkTimeWithinDayTimeAndEmit_HappyPath_Overnight(
        Duration from,
        Duration to,
        Duration timeToWarp
    ) external {
        vm.assume(from < timeConstraints.DAY_DURATION() && to < from);
        vm.assume(timeToWarp <= to || timeToWarp >= from);
        vm.assume(timeToWarp < timeConstraints.DAY_DURATION());
        vm.warp(timeToWarp.toSeconds());
        vm.expectEmit();
        emit TimeConstraints.TimeWithinDayTimeChecked(from, to);
        timeConstraints.checkTimeWithinDayTimeAndEmit(from, to);
    }

    // checkTimeAfterTimestamp

    function testFuzz_checkTimeAfterTimestamp_HappyPath(Timestamp timestampToWarp, Timestamp timestampToCheck) public {
        vm.assume(timestampToWarp > timestampToCheck);
        vm.warp(timestampToWarp.toSeconds());
        timeConstraints.checkTimeAfterTimestamp(timestampToCheck);
    }

    function testFuzz_checkTimeAfterTimestamp_NotReached(
        Timestamp timestampToWarp,
        Timestamp timestampToCheck
    ) public {
        vm.assume(timestampToWarp <= timestampToCheck);

        vm.warp(timestampToWarp.toSeconds());
        vm.expectRevert(
            abi.encodeWithSelector(TimeConstraints.TimestampNotReached.selector, timestampToCheck.toSeconds())
        );
        this.external__checkTimeAfterTimestamp(timestampToCheck);
    }

    // checkTimeAfterTimestampAndEmit

    function testFuzz_checkTimeAfterTimestampAndEmit_HappyPath(
        Timestamp timestampToWarp,
        Timestamp timestampToCheck
    ) public {
        vm.assume(timestampToWarp > timestampToCheck);
        vm.warp(timestampToWarp.toSeconds());

        vm.expectEmit();
        emit TimeConstraints.TimeAfterTimestampChecked(timestampToCheck);
        timeConstraints.checkTimeAfterTimestampAndEmit(timestampToCheck);
    }

    // checkTimeBeforeTimestamp

    function testFuzz_checkTimeBeforeTimestamp_HappyPath(
        Timestamp timestampToWarp,
        Timestamp timestampToCheck
    ) public {
        vm.assume(timestampToWarp < timestampToCheck);
        vm.warp(timestampToWarp.toSeconds());
        timeConstraints.checkTimeBeforeTimestamp(timestampToCheck);
    }

    function testFuzz_checkTimeBeforeTimestamp_Exceed(Timestamp timestampToWarp, Timestamp timestampToCheck) public {
        vm.assume(timestampToWarp >= timestampToCheck);
        vm.warp(timestampToWarp.toSeconds());
        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.TimestampExceeded.selector, timestampToCheck));
        this.external__checkTimeBeforeTimestamp(timestampToCheck);
    }

    // checkTimeBeforeTimestampAndEmit

    function testFuzz_checkTimeBeforeTimestampAndEmit_HappyPath(
        Timestamp timestampToWarp,
        Timestamp timestampToCheck
    ) public {
        vm.assume(timestampToWarp < timestampToCheck);
        vm.warp(timestampToWarp.toSeconds());
        vm.expectEmit();
        emit TimeConstraints.TimeBeforeTimestampChecked(timestampToCheck);
        timeConstraints.checkTimeBeforeTimestampAndEmit(timestampToCheck);
    }

    function external__checkTimeAfterTimestamp(Timestamp timestampToCheck) external view {
        timeConstraints.checkTimeAfterTimestamp(timestampToCheck);
    }

    function external__checkTimeBeforeTimestamp(Timestamp timestampToCheck) external view {
        timeConstraints.checkTimeBeforeTimestamp(timestampToCheck);
    }

    function external__checkTimeWithinDayTime(Duration start, Duration end) external view {
        timeConstraints.checkTimeWithinDayTime(start, end);
    }
}
