// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library ArrayUtils {
    function sum(uint256[] calldata values) internal pure returns (uint256 res) {
        uint256 valuesCount = values.length;
        for (uint256 i = 0; i < valuesCount; ++i) {
            res += values[i];
        }
    }

    function seed(uint256 length, uint256 value) internal pure returns (uint256[] memory res) {
        res = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            res[i] = value;
        }
    }
}
