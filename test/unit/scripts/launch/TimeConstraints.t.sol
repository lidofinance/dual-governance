// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";
import {TimeConstraints} from "scripts/launch/TimeConstraints.sol";

contract TimeConstraintsTest is Test {
    TimeConstraints public timeConstraints;

    function setUp() external {
        timeConstraints = new TimeConstraints();
    }

    function test_DAY_DURATION() external view {
        assertEq(timeConstraints.DAY_DURATION().toSeconds(), 24 hours);
    }

    function testFuzz_getCurrentDayTime_HappyPath(uint40 timestampToWarp) external {
        vm.warp(timestampToWarp);
        uint40 dayTime = timestampToWarp % 24 hours;
        assertEq(timeConstraints.getCurrentDayTime().toSeconds(), dayTime);
    }

    // checkTimeWithinDayTime & checkTimeWithinDayTimeAndEmit

    function testFuzz_checkTimeWithinDayTime_HappyPath_Regular(uint32 from, uint32 to, uint40 timeToWarp) external {
        from = from % 24 hours;
        to = to % 24 hours;
        uint256 warpDayTime = timeToWarp % 24 hours;

        vm.assume(from <= to && warpDayTime >= from && warpDayTime <= to);

        vm.warp(timeToWarp);
        timeConstraints.checkTimeWithinDayTime(Durations.from(from), Durations.from(to));

        vm.expectEmit();
        emit TimeConstraints.TimeWithinDayTimeChecked(Durations.from(from), Durations.from(to));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(from), Durations.from(to));
    }

    function testFuzz_checkTimeWithinDayTime_HappyPath_Overnight(uint32 from, uint32 to, uint40 timeToWarp) external {
        from = from % 24 hours;
        to = to % 24 hours;
        uint256 warpDayTime = timeToWarp % 24 hours;

        vm.assume(from > to && (from <= warpDayTime || to >= warpDayTime));

        vm.warp(timeToWarp);
        timeConstraints.checkTimeWithinDayTime(Durations.from(from), Durations.from(to));

        vm.expectEmit();
        emit TimeConstraints.TimeWithinDayTimeChecked(Durations.from(from), Durations.from(to));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(from), Durations.from(to));
    }

    function testFuzz_checkTimeWithinDayTime_HappyPath() external {
        // Time period from 08:00:00 to 17:00:00
        vm.warp(8 hours - 1);
        vm.expectRevert();
        this.external__checkTimeWithinDayTime(Durations.from(8 hours), Durations.from(17 hours));
        vm.expectRevert();
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(8 hours), Durations.from(17 hours));

        vm.warp(8 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(8 hours), Durations.from(17 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(8 hours), Durations.from(17 hours));

        vm.warp(11 hours + 30 minutes);
        timeConstraints.checkTimeWithinDayTime(Durations.from(8 hours), Durations.from(17 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(8 hours), Durations.from(17 hours));

        vm.warp(17 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(8 hours), Durations.from(17 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(8 hours), Durations.from(17 hours));

        vm.warp(17 hours + 1);
        vm.expectRevert();
        this.external__checkTimeWithinDayTime(Durations.from(8 hours), Durations.from(17 hours));
        vm.expectRevert();
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(8 hours), Durations.from(17 hours));
    }

    function testFuzz_checkTimeWithinDayTime_HappyPath_Overnight() external {
        // Time period from 22:00:00 to 06:00:00
        vm.warp(22 hours - 1);
        vm.expectRevert();
        this.external__checkTimeWithinDayTime(Durations.from(22 hours), Durations.from(6 hours));
        vm.expectRevert();
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(22 hours), Durations.from(6 hours));

        vm.warp(22 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(22 hours), Durations.from(6 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(22 hours), Durations.from(6 hours));

        vm.warp(0);
        timeConstraints.checkTimeWithinDayTime(Durations.from(22 hours), Durations.from(6 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(22 hours), Durations.from(6 hours));

        vm.warp(6 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(22 hours), Durations.from(6 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(22 hours), Durations.from(6 hours));

        vm.warp(6 hours + 1);
        vm.expectRevert();
        this.external__checkTimeWithinDayTime(Durations.from(22 hours), Durations.from(6 hours));
        vm.expectRevert();
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(22 hours), Durations.from(6 hours));
    }

    function testFuzz_checkTimeWithinDayTime_HappyPath_EdgeCases() external {
        // Time period from 00:00:00 to 23:59:59
        vm.warp(0);
        timeConstraints.checkTimeWithinDayTime(Durations.from(0), Durations.from(24 hours - 1));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(0), Durations.from(24 hours - 1));

        vm.warp(12 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(0), Durations.from(24 hours - 1));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(0), Durations.from(24 hours - 1));

        vm.warp(24 hours - 1);
        timeConstraints.checkTimeWithinDayTime(Durations.from(0), Durations.from(24 hours - 1));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(0), Durations.from(24 hours - 1));

        // Time period from 12:00:00 to 12:00:00
        vm.warp(12 hours - 1);
        vm.expectRevert();
        this.external__checkTimeWithinDayTime(Durations.from(12 hours), Durations.from(12 hours));
        vm.expectRevert();
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(12 hours), Durations.from(12 hours));

        vm.warp(12 hours);
        timeConstraints.checkTimeWithinDayTime(Durations.from(12 hours), Durations.from(12 hours));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(12 hours), Durations.from(12 hours));

        vm.warp(12 hours + 1);
        vm.expectRevert();
        this.external__checkTimeWithinDayTime(Durations.from(12 hours), Durations.from(12 hours));
        vm.expectRevert();
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(12 hours), Durations.from(12 hours));

        // Time period from 23:59:59 to 00:00:00
        vm.warp(24 hours - 2);
        vm.expectRevert();
        this.external__checkTimeWithinDayTime(Durations.from(24 hours - 1), Durations.from(0));
        vm.expectRevert();
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(24 hours - 1), Durations.from(0));

        vm.warp(24 hours - 1);
        timeConstraints.checkTimeWithinDayTime(Durations.from(24 hours - 1), Durations.from(0));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(24 hours - 1), Durations.from(0));

        vm.warp(0);
        timeConstraints.checkTimeWithinDayTime(Durations.from(24 hours - 1), Durations.from(0));
        timeConstraints.checkTimeWithinDayTimeAndEmit(Durations.from(24 hours - 1), Durations.from(0));

        vm.warp(1);
        vm.expectRevert();
        this.external__checkTimeWithinDayTime(Durations.from(24 hours - 1), Durations.from(0));
        vm.expectRevert();
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(24 hours - 1), Durations.from(0));
    }

    function testFuzz_checkTimeWithinDayTime_RevertOn_OutOfRange_Regular(
        uint32 from,
        uint32 to,
        uint40 timeToWarp
    ) external {
        from = from % 24 hours;
        to = to % 24 hours;
        uint256 warpDayTime = timeToWarp % 24 hours;

        vm.assume(from < to && (warpDayTime < from || warpDayTime > to));
        vm.warp(timeToWarp);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeConstraints.DayTimeOutOfRange.selector,
                Durations.from(warpDayTime),
                Durations.from(from),
                Durations.from(to)
            )
        );
        this.external__checkTimeWithinDayTime(Durations.from(from), Durations.from(to));

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeConstraints.DayTimeOutOfRange.selector,
                Durations.from(warpDayTime),
                Durations.from(from),
                Durations.from(to)
            )
        );
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(from), Durations.from(to));
    }

    function testFuzz_checkTimeWithinDayTime_RevertOn_OutOfRange_Overnight(
        uint32 from,
        uint32 to,
        uint40 timeToWarp
    ) external {
        from = from % 24 hours;
        to = to % 24 hours;
        uint256 warpDayTime = timeToWarp % 24 hours;

        vm.assume(from > to && (warpDayTime < from && warpDayTime > to));

        vm.warp(timeToWarp);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeConstraints.DayTimeOutOfRange.selector,
                Durations.from(warpDayTime),
                Durations.from(from),
                Durations.from(to)
            )
        );
        this.external__checkTimeWithinDayTime(Durations.from(from), Durations.from(to));

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeConstraints.DayTimeOutOfRange.selector,
                Durations.from(warpDayTime),
                Durations.from(from),
                Durations.from(to)
            )
        );
        this.external__checkTimeWithinDayTimeAndEmit(Durations.from(from), Durations.from(to));
    }

    function testFuzz_checkTimeWithinDayTime_RevertOn_TimeOverflow(Duration from, Duration to) external {
        vm.assume(from.toSeconds() >= 24 hours || to.toSeconds() >= 24 hours);

        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.DayTimeOverflow.selector));
        this.external__checkTimeWithinDayTime(from, to);

        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.DayTimeOverflow.selector));
        this.external__checkTimeWithinDayTimeAndEmit(from, to);
    }

    // checkTimeAfterTimestamp & checkTimeAfterTimestampAndEmit

    function testFuzz_checkTimeAfterTimestamp_HappyPath(
        Timestamp timestampToWarp,
        Timestamp timestampToCheck
    ) external {
        vm.assume(timestampToWarp > timestampToCheck);
        vm.warp(timestampToWarp.toSeconds());
        timeConstraints.checkTimeAfterTimestamp(timestampToCheck);

        vm.expectEmit();
        emit TimeConstraints.TimeAfterTimestampChecked(timestampToCheck);
        timeConstraints.checkTimeAfterTimestampAndEmit(timestampToCheck);
    }

    function testFuzz_checkTimeAfterTimestamp_RevertOn_TimestampNotPassed(
        Timestamp timestampToWarp,
        Timestamp timestampToCheck
    ) external {
        vm.assume(timestampToWarp <= timestampToCheck);

        vm.warp(timestampToWarp.toSeconds());
        vm.expectRevert(
            abi.encodeWithSelector(TimeConstraints.TimestampNotPassed.selector, timestampToCheck.toSeconds())
        );
        this.external__checkTimeAfterTimestamp(timestampToCheck);

        vm.warp(timestampToWarp.toSeconds());
        vm.expectRevert(
            abi.encodeWithSelector(TimeConstraints.TimestampNotPassed.selector, timestampToCheck.toSeconds())
        );
        this.external__checkTimeAfterTimestampAndEmit(timestampToCheck);
    }

    // checkTimeBeforeTimestamp & checkTimeBeforeTimestampAndEmit

    function testFuzz_checkTimeBeforeTimestamp_HappyPath(
        Timestamp timestampToWarp,
        Timestamp timestampToCheck
    ) external {
        vm.assume(timestampToWarp < timestampToCheck);
        vm.warp(timestampToWarp.toSeconds());
        timeConstraints.checkTimeBeforeTimestamp(timestampToCheck);

        vm.expectEmit();
        emit TimeConstraints.TimeBeforeTimestampChecked(timestampToCheck);
        timeConstraints.checkTimeBeforeTimestampAndEmit(timestampToCheck);
    }

    function testFuzz_checkTimeBeforeTimestamp_RevertOn_TimestampPassed(
        Timestamp timestampToWarp,
        Timestamp timestampToCheck
    ) external {
        vm.assume(timestampToWarp >= timestampToCheck);
        vm.warp(timestampToWarp.toSeconds());
        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.TimestampPassed.selector, timestampToCheck));
        this.external__checkTimeBeforeTimestamp(timestampToCheck);

        vm.expectRevert(abi.encodeWithSelector(TimeConstraints.TimestampPassed.selector, timestampToCheck));
        this.external__checkTimeBeforeTimestampAndEmit(timestampToCheck);
    }

    // External functions

    function external__checkTimeAfterTimestamp(Timestamp timestampToCheck) external view {
        timeConstraints.checkTimeAfterTimestamp(timestampToCheck);
    }

    function external__checkTimeBeforeTimestamp(Timestamp timestampToCheck) external view {
        timeConstraints.checkTimeBeforeTimestamp(timestampToCheck);
    }

    function external__checkTimeWithinDayTime(Duration start, Duration end) external view {
        timeConstraints.checkTimeWithinDayTime(start, end);
    }

    function external__checkTimeAfterTimestampAndEmit(Timestamp timestampToCheck) external {
        timeConstraints.checkTimeAfterTimestampAndEmit(timestampToCheck);
    }

    function external__checkTimeBeforeTimestampAndEmit(Timestamp timestampToCheck) external {
        timeConstraints.checkTimeBeforeTimestampAndEmit(timestampToCheck);
    }

    function external__checkTimeWithinDayTimeAndEmit(Duration start, Duration end) external {
        timeConstraints.checkTimeWithinDayTimeAndEmit(start, end);
    }
}
