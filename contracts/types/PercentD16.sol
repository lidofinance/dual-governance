// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ---
// Type Definition
// ---

type PercentD16 is uint128;

// ---
// Assign Global Operations
// ---

using {lt as <, lte as <=, eq as ==, gte as >=, gt as >} for PercentD16 global;
using {toUint256} for PercentD16 global;
using {minus as -, plus as +} for PercentD16 global;

// ---
// Errors
// ---

error DivisionByZero();
error PercentD16Overflow();
error PercentD16Underflow();

// ---
// Constants
// ---

uint128 constant HUNDRED_PERCENT_BP = 100_00;
uint128 constant MAX_PERCENT_D16 = type(uint128).max;
uint128 constant HUNDRED_PERCENT_D16 = 100 * 10 ** 16;

// ---
// Comparison Operations
// ---

function lt(PercentD16 a, PercentD16 b) pure returns (bool) {
    return PercentD16.unwrap(a) < PercentD16.unwrap(b);
}

function lte(PercentD16 a, PercentD16 b) pure returns (bool) {
    return PercentD16.unwrap(a) <= PercentD16.unwrap(b);
}

function eq(PercentD16 a, PercentD16 b) pure returns (bool) {
    return PercentD16.unwrap(a) == PercentD16.unwrap(b);
}

function gte(PercentD16 a, PercentD16 b) pure returns (bool) {
    return PercentD16.unwrap(a) >= PercentD16.unwrap(b);
}

function gt(PercentD16 a, PercentD16 b) pure returns (bool) {
    return PercentD16.unwrap(a) > PercentD16.unwrap(b);
}

// ---
// Conversion Operations
// ---

function toUint256(PercentD16 value) pure returns (uint256) {
    return PercentD16.unwrap(value);
}

// ---
// Arithmetic Operations
// ---

function plus(PercentD16 a, PercentD16 b) pure returns (PercentD16) {
    unchecked {
        /// @dev Both `a.toUint256()` and `b.toUint256()` are <= type(uint128).max. Therefore, their
        ///      sum is <= type(uint256).max.
        return PercentsD16.from(a.toUint256() + b.toUint256());
    }
}

function minus(PercentD16 a, PercentD16 b) pure returns (PercentD16) {
    uint256 aValue = a.toUint256();
    uint256 bValue = b.toUint256();

    if (aValue < bValue) {
        revert PercentD16Underflow();
    }

    unchecked {
        /// @dev Subtraction is safe because `aValue` >= `bValue`.
        ///      Both `aValue` and `bValue` <= `type(uint128).max`, so the difference fits within `uint128`.
        return PercentD16.wrap(uint128(aValue - bValue));
    }
}

// ---
// Namespaced Helper Methods
// ---

library PercentsD16 {
    function from(uint256 value) internal pure returns (PercentD16) {
        if (value > MAX_PERCENT_D16) {
            revert PercentD16Overflow();
        }
        /// @dev Casting `value` to `uint128` is safe as the check ensures it is less than or equal
        ///     to `MAX_PERCENT_D16`, which fits within the `uint128`.
        return PercentD16.wrap(uint128(value));
    }

    function fromFraction(uint256 numerator, uint256 denominator) internal pure returns (PercentD16) {
        if (denominator == 0) {
            revert DivisionByZero();
        }
        return from(HUNDRED_PERCENT_D16 * numerator / denominator);
    }

    function fromBasisPoints(uint256 bpValue) internal pure returns (PercentD16) {
        return from(HUNDRED_PERCENT_D16 * bpValue / HUNDRED_PERCENT_BP);
    }
}
