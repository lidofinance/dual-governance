// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ---
// Type definition
// ---

type Timestamp is uint40;

// ---
// Errors
// ---

error TimestampOverflow();

// ---
// Assign global operations
// ---

using {lt as <, lte as <=, eq as ==, neq as !=, gt as >, gte as >=} for Timestamp global;
using {isZero, isNotZero, toSeconds} for Timestamp global;

// ---
// Constants
// ---

uint256 constant MAX_TIMESTAMP_VALUE = type(uint40).max;

// ---
// Comparison operations
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

function neq(Timestamp t1, Timestamp t2) pure returns (bool) {
    return !(t1 == t2);
}

// ---
// Custom operations
// ---

function isZero(Timestamp t) pure returns (bool) {
    return Timestamp.unwrap(t) == 0;
}

function isNotZero(Timestamp t) pure returns (bool) {
    return Timestamp.unwrap(t) != 0;
}

// ---
// Conversion operations
// ---

function toSeconds(Timestamp t) pure returns (uint256) {
    return Timestamp.unwrap(t);
}

// ---
// Namespaced helper methods
// ---

library Timestamps {
    Timestamp internal constant ZERO = Timestamp.wrap(0);

    Timestamp internal constant MIN = ZERO;
    Timestamp internal constant MAX = Timestamp.wrap(uint40(MAX_TIMESTAMP_VALUE));

    function max(Timestamp t1, Timestamp t2) internal pure returns (Timestamp) {
        return t1 > t2 ? t1 : t2;
    }

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
