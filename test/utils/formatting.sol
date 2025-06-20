// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";

import {PercentD16} from "contracts/types/PercentD16.sol";

Vm constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

library DecimalsFormatting {
    function formatEther(uint256 decimal) internal pure returns (string memory res) {
        return format(decimal, 18);
    }

    function formatRay(uint256 decimal) internal pure returns (string memory res) {
        return format(decimal, 27);
    }

    function format(PercentD16 percents) internal pure returns (string memory res) {
        return string.concat(format(percents.toUint256(), 16), "%");
    }

    function format(uint256 decimal, uint256 precision) internal pure returns (string memory res) {
        // format fractional part

        for (uint256 i = 0; i < precision; ++i) {
            res = string.concat(VM.toString(decimal % 10), res);
            decimal /= 10;
        }
        res = string.concat(".", res);

        while (decimal > 0) {
            res = string.concat(VM.toString(decimal % 10), res);
            decimal /= 10;
        }
    }
}
