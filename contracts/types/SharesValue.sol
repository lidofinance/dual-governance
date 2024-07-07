// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ETHValue, ETHValues} from "./ETHValue.sol";

type SharesValue is uint128;

error SharesValueOverflow();

using {plus as +, minus as -, eq as ==, lt as <} for SharesValue global;
using {toUint256} for SharesValue global;

function plus(SharesValue v1, SharesValue v2) pure returns (SharesValue) {
    return SharesValue.wrap(SharesValue.unwrap(v1) + SharesValue.unwrap(v2));
}

function minus(SharesValue v1, SharesValue v2) pure returns (SharesValue) {
    return SharesValue.wrap(SharesValue.unwrap(v1) - SharesValue.unwrap(v2));
}

function lt(SharesValue v1, SharesValue v2) pure returns (bool) {
    return SharesValue.unwrap(v1) < SharesValue.unwrap(v2);
}

function eq(SharesValue v1, SharesValue v2) pure returns (bool) {
    return SharesValue.unwrap(v1) == SharesValue.unwrap(v2);
}

function toUint256(SharesValue v) pure returns (uint256) {
    return SharesValue.unwrap(v);
}

library SharesValues {
    SharesValue internal constant ZERO = SharesValue.wrap(0);

    function from(uint256 value) internal pure returns (SharesValue) {
        if (value > type(uint128).max) {
            revert SharesValueOverflow();
        }
        return SharesValue.wrap(uint128(value));
    }

    function calcETHValue(
        ETHValue totalPooled,
        SharesValue share,
        SharesValue total
    ) internal pure returns (ETHValue) {
        return ETHValues.from(totalPooled.toUint256() * share.toUint256() / total.toUint256());
    }
}
