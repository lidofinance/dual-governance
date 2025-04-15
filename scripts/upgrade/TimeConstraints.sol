// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";

/// @title Time Constraints Contract
/// @notice Provides functionality to restrict execution of transactions based on time constraints.
contract TimeConstraints {
    // ---
    // Events
    // ---

    event TimeWithinDayTimeChecked(Duration startDayTime, Duration endDayTime);
    event TimeBeforeTimestampChecked(Timestamp timestamp);
    event TimeAfterTimestampChecked(Timestamp timestamp);

    // ---
    // Errors
    // ---

    error DayTimeOverflow();
    error DayTimeOutOfRange(Duration currentDayTime, Duration startDayTime, Duration endDayTime);
    error TimestampNotReached(Timestamp timestamp);
    error TimestampExceeded(Timestamp timestamp);

    // ---
    // Constants
    // ---

    /// @notice Total number of seconds in a day (24 hours).
    Duration public immutable DAY_DURATION = Durations.from(24 hours);

    // ---
    // Time Constraints Checks
    // ---

    /// @notice Checks that the current day time satisfies specific time range during the day.
    /// @dev Supports two types of time ranges:
    ///      1. Regular range: startDayTime <= endDayTime (e.g. [12:00, 18:00])
    ///      2. Overnight range: startDayTime > endDayTime (e.g. [18:00, 12:00], where the end time is on the next day)
    /// @param startDayTime The start time of the allowed range in seconds since midnight (UTC).
    /// @param endDayTime The end time of the allowed range in seconds since midnight (UTC).
    function checkTimeWithinDayTime(Duration startDayTime, Duration endDayTime) public view {
        _validateDayTime(startDayTime);
        _validateDayTime(endDayTime);

        Duration currentDayTime = getCurrentDayTime();
        if (startDayTime > endDayTime) {
            if (currentDayTime < startDayTime && currentDayTime > endDayTime) {
                revert DayTimeOutOfRange(currentDayTime, startDayTime, endDayTime);
            }
        } else {
            if (currentDayTime < startDayTime || currentDayTime > endDayTime) {
                revert DayTimeOutOfRange(currentDayTime, startDayTime, endDayTime);
            }
        }
    }

    /// @notice Checks that the current day time satisfies specific time range during the day and emits an event.
    /// @dev Supports two types of time ranges:
    ///      1. Regular range: startDayTime <= endDayTime (e.g. [12:00, 18:00])
    ///      2. Overnight range: startDayTime > endDayTime (e.g. [18:00, 12:00], where the end time is on the next day)
    /// @param startDayTime The start time of the allowed range in seconds since midnight (UTC).
    /// @param endDayTime The end time of the allowed range in seconds since midnight (UTC).
    function checkTimeWithinDayTimeAndEmit(Duration startDayTime, Duration endDayTime) external {
        checkTimeWithinDayTime(startDayTime, endDayTime);
        emit TimeWithinDayTimeChecked(startDayTime, endDayTime);
    }

    /// @notice Checks that the current timestamp is after the given specific timestamp.
    /// @param timestamp The Unix timestamp after which the function can be executed.
    function checkTimeAfterTimestamp(Timestamp timestamp) public view {
        if (Timestamps.now() <= timestamp) {
            revert TimestampNotReached(timestamp);
        }
    }

    /// @notice Checks that the current timestamp is after the given specific timestamp and emits an event.
    /// @param timestamp The Unix timestamp after which the function can be executed.
    function checkTimeAfterTimestampAndEmit(Timestamp timestamp) external {
        checkTimeAfterTimestamp(timestamp);
        emit TimeAfterTimestampChecked(timestamp);
    }

    /// @notice Checks that the current timestamp is before the given specific timestamp.
    /// @param timestamp The Unix timestamp before which the function can be executed.
    function checkTimeBeforeTimestamp(Timestamp timestamp) public view {
        if (Timestamps.now() >= timestamp) {
            revert TimestampExceeded(timestamp);
        }
    }

    /// @notice Checks that the current timestamp is before the given specific timestamp and emits an event.
    /// @param timestamp The Unix timestamp before which the function can be executed.
    function checkTimeBeforeTimestampAndEmit(Timestamp timestamp) external {
        checkTimeBeforeTimestamp(timestamp);
        emit TimeBeforeTimestampChecked(timestamp);
    }

    // ---
    // Getters
    // ---

    /// @notice Gets the current time in seconds since midnight (UTC).
    /// @return The current time in seconds since midnight.
    function getCurrentDayTime() public view returns (Duration) {
        return Durations.from(block.timestamp % DAY_DURATION.toSeconds());
    }

    // ---
    // Internal Methods
    // ---

    /// @notice Validates that a provided day time value is within the [0:00:00, 23:59:59] range.
    /// @param dayTime The day time value in seconds to validate.
    /// @dev Reverts with `DayTimeOverflow` if the value exceeds the number of seconds in a day.
    function _validateDayTime(Duration dayTime) internal view {
        if (dayTime >= DAY_DURATION) {
            revert DayTimeOverflow();
        }
    }
}
