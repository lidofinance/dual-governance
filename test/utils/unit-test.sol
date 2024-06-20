// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// solhint-disable-next-line
import {Test} from "forge-std/Test.sol";
import {ExecutorCall} from "contracts/libraries/Proposals.sol";
import {ExecutorCallHelpers} from "test/utils/executor-calls.sol";
import {IDangerousContract} from "test/utils/interfaces.sol";

contract UnitTest is Test {
    function _wait(uint256 duration) internal {
        vm.warp(block.timestamp + duration);
    }

    function _getTargetRegularStaffCalls(address targetMock) internal pure returns (ExecutorCall[] memory) {
        return ExecutorCallHelpers.create(address(targetMock), abi.encodeCall(IDangerousContract.doRegularStaff, (42)));
    }
}