// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ---
// Type Definition
// ---

type SharesValue is uint128;

// ---
// Assign Global Operations
// ---

using {lt as <, eq as ==} for SharesValue global;
using {toUint256} for SharesValue global;
using {plus as +, minus as -} for SharesValue global;

// ---
// Errors
// ---

error SharesValueOverflow();
error SharesValueUnderflow();

// ---
// Constants
// ---

uint128 constant MAX_SHARES_VALUE = type(uint128).max;

// ---
// Comparison Operations
// ---

function lt(SharesValue v1, SharesValue v2) pure returns (bool) {
    return SharesValue.unwrap(v1) < SharesValue.unwrap(v2);
}

function eq(SharesValue v1, SharesValue v2) pure returns (bool) {
    return SharesValue.unwrap(v1) == SharesValue.unwrap(v2);
}

// ---
// Conversion Operations
// ---

function toUint256(SharesValue v) pure returns (uint256) {
    return SharesValue.unwrap(v);
}

// ---
// Arithmetic Operations
// ---

function plus(SharesValue v1, SharesValue v2) pure returns (SharesValue) {
    unchecked {
        /// @dev Both `v1.toUint256()` and `v2.toUint256()` are <= type(uint128).max. Therefore, their
        ///      sum is <= type(uint256).max.
        return SharesValues.from(v1.toUint256() + v2.toUint256());
    }
}

function minus(SharesValue v1, SharesValue v2) pure returns (SharesValue) {
    uint256 v1Value = v1.toUint256();
    uint256 v2Value = v2.toUint256();

    if (v1Value < v2Value) {
        revert SharesValueUnderflow();
    }

    unchecked {
        /// @dev Subtraction is safe because `v1Value` >= `v2Value`.
        ///      Both `v1Value` and `v2Value` <= `type(uint128).max`, so the difference fits within `uint128`.
        return SharesValue.wrap(uint128(v1Value - v2Value));
    }
}

// ---
// Namespaced Helper Methods
// ---

library SharesValues {
    SharesValue internal constant ZERO = SharesValue.wrap(0);

    function from(uint256 value) internal pure returns (SharesValue) {
        if (value > MAX_SHARES_VALUE) {
            revert SharesValueOverflow();
        }
        /// @dev Casting `value` to `uint128` is safe as the check ensures it is less than or equal
        ///     to `MAX_SHARES_VALUE`, which fits within the `uint128`.
        return SharesValue.wrap(uint128(value));
    }
}
