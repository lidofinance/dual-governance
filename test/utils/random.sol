// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.26;

library Random {
    struct Context {
        bytes32 seed;
        bytes32 value;
    }

    function create(uint256 seed) internal pure returns (Context memory self) {
        self.seed = bytes32(seed);
        self.value = self.seed;
    }

    function nextUint256(Context storage self) internal returns (uint256) {
        return uint256(_nextValue(self));
    }

    /// @param maxValue - exclusive upper bound of the random
    /// @return random uint256 in range [0, maxValue). When maxValue is 0, returns 0
    function nextUint256(Context storage self, uint256 maxValue) internal returns (uint256) {
        if (maxValue == 0) {
            return 0;
        }
        return nextUint256(self) % maxValue;
    }

    /// @param minValue - inclusive lower bound
    /// @param maxValue - exclusive upper bound of the random
    function nextUint256(Context storage self, uint256 minValue, uint256 maxValue) internal returns (uint256) {
        return minValue + nextUint256(self, maxValue - minValue);
    }

    function nextBool(Context storage self) internal returns (bool) {
        return nextUint256(self) % 2 == 0;
    }

    function nextAddress(Context storage self) internal returns (address) {
        return address(uint160(nextUint256(self)));
    }

    function nextPermutation(Context storage self, uint256 size) internal returns (uint256[] memory res) {
        return nextPermutation(self, size, 0);
    }

    function nextPermutation(
        Context storage self,
        uint256 size,
        uint256 startItem
    ) internal returns (uint256[] memory res) {
        res = new uint256[](size);

        for (uint256 i = 0; i < size; ++i) {
            res[i] = startItem + i;
        }

        if (size == 1) {
            return res;
        }

        for (uint256 i = 0; i < size / 2 + 1; ++i) {
            uint256 randIndex = nextUint256(self, size);
            uint256 tmp = res[i];
            res[i] = res[randIndex];
            res[randIndex] = tmp;
        }
    }

    function _nextValue(Context storage self) private returns (bytes32) {
        self.value = keccak256(abi.encode(self.value));
        return self.value;
    }
}
