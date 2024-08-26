// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";

// solhint-disable-next-line
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";
import {IPotentiallyDangerousContract} from "./interfaces/IPotentiallyDangerousContract.sol";
import {TestingAssertEqExtender} from "./testing-assert-eq-extender.sol";

contract UnitTest is TestingAssertEqExtender {
    function _wait(Duration duration) internal {
        vm.warp(block.timestamp + Duration.unwrap(duration));
    }

    function _getMockTargetRegularStaffCalls(address targetMock) internal pure returns (ExternalCall[] memory) {
        return ExternalCallHelpers.create(
            address(targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (42))
        );
    }
}
