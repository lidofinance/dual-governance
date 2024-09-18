// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// ---
// Type definition
// ---

type ETHValue is uint128;

// ---
// Errors
// ---

error ETHValueOverflow();
error ETHValueUnderflow();

// ---
// Assign global operations
// ---

using {lt as <, gt as >, eq as ==, neq as !=} for ETHValue global;
using {plus as +, minus as -} for ETHValue global;
using {toUint256, sendTo} for ETHValue global;

// ---
// Comparison operations
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
// Arithmetic operations
// ---

function plus(ETHValue v1, ETHValue v2) pure returns (ETHValue) {
    unchecked {
        return ETHValues.from(v1.toUint256() + v2.toUint256());
    }
}

function minus(ETHValue v1, ETHValue v2) pure returns (ETHValue) {
    if (v1 < v2) {
        revert ETHValueUnderflow();
    }
    unchecked {
        return ETHValues.from(ETHValue.unwrap(v1) - ETHValue.unwrap(v2));
    }
}

// ---
// Custom operations
// ---

function sendTo(ETHValue value, address payable recipient) {
    Address.sendValue(recipient, value.toUint256());
}

// ---
// Conversion operations
// ---

function toUint256(ETHValue value) pure returns (uint256) {
    return ETHValue.unwrap(value);
}

// ---
// Namespaced helper methods
// ---

library ETHValues {
    ETHValue internal constant ZERO = ETHValue.wrap(0);

    function from(uint256 value) internal pure returns (ETHValue) {
        if (value > type(uint128).max) {
            revert ETHValueOverflow();
        }
        return ETHValue.wrap(uint128(value));
    }

    function fromAddressBalance(address account) internal view returns (ETHValue) {
        return from(account.balance);
    }
}
