// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";

/// @title Time Constraints Contract
/// @notice Provides functionality to restrict execution of functions based on time constraints.
contract TimeConstraints {
    // ---
    // Errors
    // ---

    error DayTimeOverflow();
    error InvalidDayTimeRange(Duration startDayTime, Duration endDayTime);
    error DayTimeOutOfRange(Duration currentDayTime, Duration startDayTime, Duration endDayTime);
    error TimestampNotReached(Timestamp requiredTimestamp);

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
    function checkExecuteWithinDayTime(Duration startDayTime, Duration endDayTime) external view {
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

    /// @notice Checks that the transaction can only be executed after a specific timestamp.
    /// @param timestamp The Unix timestamp after which the function can be executed.
    function checkExecuteAfterTimestamp(Timestamp timestamp) external view {
        if (Timestamps.now() < timestamp) {
            revert TimestampNotReached(timestamp);
        }
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
