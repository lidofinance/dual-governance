// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// solhint-disable-next-line
import {Test} from "forge-std/Test.sol";
import {ExecutorCall} from "contracts/libraries/Proposals.sol";

contract UnitTest is Test {
    function _wait(uint256 duration) internal {
        vm.warp(block.timestamp + duration);
    }
}
