// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";

/// @title Time Constraints Contract
/// @notice Provides functionality to restrict execution of functions based on time constraints.
contract TimeConstraints {
    // ---
    // Events
    // ---

    event PerformedWithinDayTime(Duration startDayTime, Duration endDayTime);
    event PerformedBeforeTimestamp(Timestamp deadline);
    event PerformedAfterTimestamp(Timestamp requiredTimestamp);

    // ---
    // Errors
    // ---

    error DayTimeOverflow();
    error InvalidDayTimeRange(Duration startDayTime, Duration endDayTime);
    error DayTimeOutOfRange(Duration currentDayTime, Duration startDayTime, Duration endDayTime);
    error TimestampNotReached(Timestamp requiredTimestamp);
    error TimestampExceeded(Timestamp deadline);
    error InvalidTimestampRange(Timestamp startTimestamp, Timestamp endTimestamp);

    // ---
    // Constants
    // ---

    /// @notice Total number of seconds in a day (24 hours).
    Duration public immutable DAY_DURATION = Durations.from(24 hours);

    // ---
    // Time Constraints Checks
    // ---

    /// @notice Checks that the transaction can only be executed within a specific time range during the day.
    /// @param startDayTime The start time of the allowed range in seconds since midnight (UTC).
    /// @param endDayTime The end time of the allowed range in seconds since midnight (UTC).
    function checkTimeWithinDayTime(Duration startDayTime, Duration endDayTime) public view {
        _validateDayTime(startDayTime);
        _validateDayTime(endDayTime);

        if (startDayTime > endDayTime) {
            revert InvalidDayTimeRange(startDayTime, endDayTime);
        }

        Duration currentDayTime = getCurrentDayTime();
        if (currentDayTime < startDayTime || currentDayTime > endDayTime) {
            revert DayTimeOutOfRange(currentDayTime, startDayTime, endDayTime);
        }
    }

    /// @notice Checks that the transaction can only be executed within a specific time range during the day and emits an event.
    /// @param startDayTime The start time of the allowed range in seconds since midnight (UTC).
    /// @param endDayTime The end time of the allowed range in seconds since midnight (UTC).
    function checkTimeWithinDayTimeAndEmit(Duration startDayTime, Duration endDayTime) external {
        checkTimeWithinDayTime(startDayTime, endDayTime);
        emit PerformedWithinDayTime(startDayTime, endDayTime);
    }

    /// @notice Checks that the transaction can only be executed after a specific timestamp.
    /// @param timestamp The Unix timestamp after which the function can be executed.
    function checkTimeAfterTimestamp(Timestamp timestamp) public view {
        if (Timestamps.now() < timestamp) {
            revert TimestampNotReached(timestamp);
        }
    }

    /// @notice Checks that the transaction can only be executed after a specific timestamp and emits an event.
    /// @param timestamp The Unix timestamp after which the function can be executed.
    function checkTimeAfterTimestampAndEmit(Timestamp timestamp) external {
        checkTimeAfterTimestamp(timestamp);
        emit PerformedAfterTimestamp(timestamp);
    }

    /// @notice Checks that the transaction can only be executed before a specific timestamp.
    /// @param timestamp The Unix timestamp before which the function can be executed.
    function checkTimeBeforeTimestamp(Timestamp timestamp) public view {
        if (Timestamps.now() > timestamp) {
            revert TimestampExceeded(timestamp);
        }
    }

    /// @notice Checks that the transaction can only be executed before a specific timestamp and emits an event.
    /// @param timestamp The Unix timestamp before which the function can be executed.
    function checkTimeBeforeTimestampAndEmit(Timestamp timestamp) external {
        checkTimeBeforeTimestamp(timestamp);
        emit PerformedBeforeTimestamp(timestamp);
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
