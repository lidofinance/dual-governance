// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

type ETHValue is uint128;

error ETHValueOverflow();
error ETHValueUnderflow();

using {plus as +, minus as -, lt as <, gt as >, eq as ==, neq as !=} for ETHValue global;
using {toUint256} for ETHValue global;
using {sendTo} for ETHValue global;

function sendTo(ETHValue value, address payable recipient) {
    Address.sendValue(recipient, value.toUint256());
}

function plus(ETHValue v1, ETHValue v2) pure returns (ETHValue) {
    return ETHValues.from(ETHValue.unwrap(v1) + ETHValue.unwrap(v2));
}

function minus(ETHValue v1, ETHValue v2) pure returns (ETHValue) {
    if (v1 < v2) {
        revert ETHValueUnderflow();
    }
    return ETHValues.from(ETHValue.unwrap(v1) + ETHValue.unwrap(v2));
}

function lt(ETHValue v1, ETHValue v2) pure returns (bool) {
    return ETHValue.unwrap(v1) < ETHValue.unwrap(v2);
}

function gt(ETHValue v1, ETHValue v2) pure returns (bool) {
    return ETHValue.unwrap(v1) > ETHValue.unwrap(v2);
}

function eq(ETHValue v1, ETHValue v2) pure returns (bool) {
    return ETHValue.unwrap(v1) == ETHValue.unwrap(v2);
}

function neq(ETHValue v1, ETHValue v2) pure returns (bool) {
    return ETHValue.unwrap(v1) != ETHValue.unwrap(v2);
}

function toUint256(ETHValue value) pure returns (uint256) {
    return ETHValue.unwrap(value);
}

library ETHValues {
    ETHValue internal constant ZERO = ETHValue.wrap(0);

    function from(uint256 value) internal pure returns (ETHValue) {
        if (value > type(uint128).max) {
            revert ETHValueOverflow();
        }
        return ETHValue.wrap(uint128(value));
    }
}
