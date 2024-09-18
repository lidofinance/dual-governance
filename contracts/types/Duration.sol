// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamp, Timestamps} from "./Timestamp.sol";

// ---
// Type definition
// ---

type Duration is uint32;

// ---
// Errors
// ---

error DurationOverflow();
error DurationUnderflow();
error TimestampUnderflow();

// ---
// Assign global operations
// ---

using {plus as +, minus as -} for Duration global;
using {lt as <, lte as <=, eq as ==, neq as !=, gt as >, gte as >=} for Duration global;
using {addTo, plusSeconds, minusSeconds, multipliedBy, dividedBy, toSeconds} for Duration global;

// ---
// Constants
// ---

/// @dev The max possible duration is about 106 years
uint256 constant MAX_DURATION_VALUE = type(uint32).max;

// ---
// Comparison operations
// ---

function lt(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) < Duration.unwrap(d2);
}

function lte(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) <= Duration.unwrap(d2);
}

function eq(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) == Duration.unwrap(d2);
}

function neq(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) != Duration.unwrap(d2);
}

function gte(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) >= Duration.unwrap(d2);
}

function gt(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) > Duration.unwrap(d2);
}

// ---
// Arithmetic operations
// ---

function plus(Duration d1, Duration d2) pure returns (Duration) {
    unchecked {
        return Durations.from(d1.toSeconds() + d2.toSeconds());
    }
}

function minus(Duration d1, Duration d2) pure returns (Duration) {
    if (d1 < d2) {
        revert DurationUnderflow();
    }
    unchecked {
        return Duration.wrap(uint32(d1.toSeconds() - d2.toSeconds()));
    }
}

// ---
// Custom operations
// ---

function plusSeconds(Duration d, uint256 seconds_) pure returns (Duration) {
    return Durations.from(Duration.unwrap(d) + seconds_);
}

function minusSeconds(Duration d, uint256 seconds_) pure returns (Duration) {
    uint256 durationValue = Duration.unwrap(d);
    if (durationValue < seconds_) {
        revert DurationUnderflow();
    }
    return Duration.wrap(uint32(durationValue - seconds_));
}

function dividedBy(Duration d, uint256 divisor) pure returns (Duration) {
    return Duration.wrap(uint32(Duration.unwrap(d) / divisor));
}

function multipliedBy(Duration d, uint256 multiplicand) pure returns (Duration) {
    return Durations.from(multiplicand * d.toSeconds());
}

function addTo(Duration d, Timestamp t) pure returns (Timestamp) {
    return Timestamps.from(t.toSeconds() + d.toSeconds());
}

// ---
// Conversion operations
// ---

function toSeconds(Duration d) pure returns (uint256) {
    return Duration.unwrap(d);
}

// ---
// Namespaced helper methods
// ---

library Durations {
    Duration internal constant ZERO = Duration.wrap(0);

    Duration internal constant MIN = ZERO;
    Duration internal constant MAX = Duration.wrap(uint32(MAX_DURATION_VALUE));

    function from(uint256 seconds_) internal pure returns (Duration res) {
        if (seconds_ > MAX_DURATION_VALUE) {
            revert DurationOverflow();
        }
        res = Duration.wrap(uint32(seconds_));
    }

    function between(Timestamp t1, Timestamp t2) internal pure returns (Duration res) {
        res = from(t1 > t2 ? t1.toSeconds() - t2.toSeconds() : t2.toSeconds() - t1.toSeconds());
    }

    function min(Duration d1, Duration d2) internal pure returns (Duration res) {
        res = d1 < d2 ? d1 : d2;
    }
}
