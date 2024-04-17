// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library TimeUtils {
    function timestamp() internal view returns (uint40) {
        return timestamp(block.timestamp);
    }

    function timestamp(uint256 value) internal pure returns (uint40) {
        return SafeCast.toUint40(value);
    }

    function duration(uint256 value) internal pure returns (uint32) {
        return SafeCast.toUint32(value);
    }
}
