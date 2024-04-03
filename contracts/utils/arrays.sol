// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library ArrayUtils {
    function seed(uint256 length, uint256 value) internal pure returns (uint256[] memory res) {
        res = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            res[i] = value;
        }
    }
}
