// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

type Timestamp is uint40;

error TimestampOverflow();
error TimestampUnderflow();

uint256 constant MAX_TIMESTAMP_VALUE = type(uint40).max;

using {lt as <} for Timestamp global;
using {gt as >} for Timestamp global;
using {gte as >=} for Timestamp global;
using {lte as <=} for Timestamp global;
using {eq as ==} for Timestamp global;
using {notEq as !=} for Timestamp global;

using {isZero} for Timestamp global;
using {isNotZero} for Timestamp global;
using {toSeconds} for Timestamp global;

// ---
// Comparison Ops
// ---

function lt(Timestamp t1, Timestamp t2) pure returns (bool) {
    return Timestamp.unwrap(t1) < Timestamp.unwrap(t2);
}

function gt(Timestamp t1, Timestamp t2) pure returns (bool) {
    return Timestamp.unwrap(t1) > Timestamp.unwrap(t2);
}

function gte(Timestamp t1, Timestamp t2) pure returns (bool) {
    return Timestamp.unwrap(t1) >= Timestamp.unwrap(t2);
}

function lte(Timestamp t1, Timestamp t2) pure returns (bool) {
    return Timestamp.unwrap(t1) <= Timestamp.unwrap(t2);
}

function eq(Timestamp t1, Timestamp t2) pure returns (bool) {
    return Timestamp.unwrap(t1) == Timestamp.unwrap(t2);
}

function notEq(Timestamp t1, Timestamp t2) pure returns (bool) {
    return !(t1 == t2);
}

function isZero(Timestamp t) pure returns (bool) {
    return Timestamp.unwrap(t) == 0;
}

function isNotZero(Timestamp t) pure returns (bool) {
    return Timestamp.unwrap(t) != 0;
}

// ---
// Conversion Ops
// ---

function toSeconds(Timestamp t) pure returns (uint256) {
    return Timestamp.unwrap(t);
}

uint256 constant MAX_VALUE = type(uint40).max;

library Timestamps {
    Timestamp internal constant ZERO = Timestamp.wrap(0);

    Timestamp internal constant MIN = ZERO;
    Timestamp internal constant MAX = Timestamp.wrap(uint40(MAX_TIMESTAMP_VALUE));

    function now() internal view returns (Timestamp res) {
        res = Timestamp.wrap(uint40(block.timestamp));
    }

    function from(uint256 value) internal pure returns (Timestamp res) {
        if (value > MAX_TIMESTAMP_VALUE) {
            revert TimestampOverflow();
        }
        return Timestamp.wrap(uint40(value));
    }
}
