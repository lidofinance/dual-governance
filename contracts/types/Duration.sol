// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Timestamp, Timestamps} from "./Timestamp.sol";

type Duration is uint32;

error DurationOverflow();
error DurationUnderflow();

// the max possible duration is ~ 106 years
uint256 constant MAX_VALUE = type(uint32).max;

using {lt as <} for Duration global;
using {lte as <=} for Duration global;
using {gt as >} for Duration global;
using {eq as ==} for Duration global;
using {notEq as !=} for Duration global;

using {plus as +} for Duration global;
using {minus as -} for Duration global;

using {addTo} for Duration global;
using {plusSeconds} for Duration global;
using {minusSeconds} for Duration global;
using {multipliedBy} for Duration global;
using {dividedBy} for Duration global;
using {toSeconds} for Duration global;

// ---
// Comparison Ops
// ---

function lt(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) < Duration.unwrap(d2);
}

function lte(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) <= Duration.unwrap(d2);
}

function gt(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) > Duration.unwrap(d2);
}

function eq(Duration d1, Duration d2) pure returns (bool) {
    return Duration.unwrap(d1) == Duration.unwrap(d2);
}

function notEq(Duration d1, Duration d2) pure returns (bool) {
    return !(d1 == d2);
}

// ---
// Arithmetic Operations
// ---

function plus(Duration d1, Duration d2) pure returns (Duration) {
    return toDuration(Duration.unwrap(d1) + Duration.unwrap(d2));
}

function minus(Duration d1, Duration d2) pure returns (Duration) {
    if (d1 < d2) {
        revert DurationUnderflow();
    }
    return Duration.wrap(Duration.unwrap(d1) - Duration.unwrap(d2));
}

function plusSeconds(Duration d, uint256 seconds_) pure returns (Duration) {
    return toDuration(Duration.unwrap(d) + seconds_);
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
    return toDuration(Duration.unwrap(d) * multiplicand);
}

function addTo(Duration d, Timestamp t) pure returns (Timestamp) {
    return Timestamps.from(t.toSeconds() + d.toSeconds());
}

// ---
// Conversion Ops
// ---

function toDuration(uint256 value) pure returns (Duration) {
    if (value > MAX_VALUE) {
        revert DurationOverflow();
    }
    return Duration.wrap(uint32(value));
}

function toSeconds(Duration d) pure returns (uint256) {
    return Duration.unwrap(d);
}

library Durations {
    Duration internal constant ZERO = Duration.wrap(0);

    Duration internal constant MIN = ZERO;
    Duration internal constant MAX = Duration.wrap(uint32(MAX_VALUE));

    function from(uint256 seconds_) internal pure returns (Duration res) {
        res = toDuration(seconds_);
    }

    function between(Timestamp t1, Timestamp t2) internal pure returns (Duration res) {
        res = toDuration(t1.toSeconds() - t2.toSeconds());
    }
}
