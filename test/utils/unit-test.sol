// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

// solhint-disable-next-line
import {Test, console} from "forge-std/Test.sol";
import {ExecutorCall} from "contracts/libraries/Proposals.sol";
import {ExecutorCallHelpers} from "test/utils/executor-calls.sol";
import {IDangerousContract} from "test/utils/interfaces.sol";

contract UnitTest is Test {
    function _wait(Duration duration) internal {
        vm.warp(block.timestamp + Duration.unwrap(duration));
    }

    function _getTargetRegularStaffCalls(address targetMock) internal pure returns (ExecutorCall[] memory) {
        return ExecutorCallHelpers.create(address(targetMock), abi.encodeCall(IDangerousContract.doRegularStaff, (42)));
    }

    function assertEq(Timestamp a, Timestamp b) internal {
        assertEq(uint256(Timestamp.unwrap(a)), uint256(Timestamp.unwrap(b)));
    }

    function assertEq(Duration a, Duration b) internal {
        assertEq(uint256(Duration.unwrap(a)), uint256(Duration.unwrap(b)));
    }
}
