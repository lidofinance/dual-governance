// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// ---
// Type Definition
// ---

type ETHValue is uint128;

// ---
// Assign Global Operations
// ---

using {lt as <, eq as ==, neq as !=, gt as >} for ETHValue global;
using {toUint256, sendTo} for ETHValue global;
using {plus as +, minus as -} for ETHValue global;

// ---
// Errors
// ---

error ETHValueOverflow();
error ETHValueUnderflow();

// ---
// Constants
// ---

uint128 constant MAX_ETH_VALUE = type(uint128).max;

// ---
// Comparison Operations
// ---

function lt(ETHValue v1, ETHValue v2) pure returns (bool) {
    return ETHValue.unwrap(v1) < ETHValue.unwrap(v2);
}

function eq(ETHValue v1, ETHValue v2) pure returns (bool) {
    return ETHValue.unwrap(v1) == ETHValue.unwrap(v2);
}

function neq(ETHValue v1, ETHValue v2) pure returns (bool) {
    return ETHValue.unwrap(v1) != ETHValue.unwrap(v2);
}

function gt(ETHValue v1, ETHValue v2) pure returns (bool) {
    return ETHValue.unwrap(v1) > ETHValue.unwrap(v2);
}

// ---
// Conversion Operations
// ---

function toUint256(ETHValue value) pure returns (uint256) {
    return ETHValue.unwrap(value);
}

// ---
// Arithmetic Operations
// ---

function plus(ETHValue v1, ETHValue v2) pure returns (ETHValue) {
    unchecked {
        /// @dev Both `v1.toUint256()` and `v2.toUint256()` are <= type(uint128).max. Therefore, their
        ///      sum is <= type(uint256).max.
        return ETHValues.from(v1.toUint256() + v2.toUint256());
    }
}

function minus(ETHValue v1, ETHValue v2) pure returns (ETHValue) {
    uint256 v1Value = v1.toUint256();
    uint256 v2Value = v2.toUint256();

    if (v1Value < v2Value) {
        revert ETHValueUnderflow();
    }

    unchecked {
        /// @dev Subtraction is safe because `v1Value` >= `v2Value`.
        ///      Both `v1Value` and `v2Value` <= `type(uint128).max`, so the difference fits within `uint128`.
        return ETHValue.wrap(uint128(v1Value - v2Value));
    }
}

// ---
// Custom Operations
// ---

function sendTo(ETHValue value, address payable recipient) {
    Address.sendValue(recipient, value.toUint256());
}

// ---
// Namespaced Helper Methods
// ---

library ETHValues {
    ETHValue internal constant ZERO = ETHValue.wrap(0);

    function from(uint256 value) internal pure returns (ETHValue) {
        if (value > MAX_ETH_VALUE) {
            revert ETHValueOverflow();
        }
        /// @dev Casting `value` to `uint128` is safe as the check ensures it is less than or equal
        ///     to `MAX_ETH_VALUE`, which fits within the `uint128`.
        return ETHValue.wrap(uint128(value));
    }

    function fromAddressBalance(address account) internal view returns (ETHValue) {
        return from(account.balance);
    }
}
