// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

function timestamp() view returns (uint40) {
    return timestamp(block.timestamp);
}

function timestamp(uint256 value) pure returns (uint40) {
    return SafeCast.toUint40(value);
}

function duration(uint256 value) pure returns (uint32) {
    return SafeCast.toUint32(value);
}
