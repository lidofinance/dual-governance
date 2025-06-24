// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";

// solhint-disable-next-line
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";
import {IPotentiallyDangerousContract} from "./interfaces/IPotentiallyDangerousContract.sol";
import {TestingAssertEqExtender} from "./testing-assert-eq-extender.sol";

contract UnitTest is TestingAssertEqExtender {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    function _wait(Duration duration) internal {
        vm.warp(block.timestamp + Duration.unwrap(duration));
    }

    function _getMockTargetRegularStaffCalls(address targetMock) internal pure returns (ExternalCall[] memory) {
        ExternalCallsBuilder.Context memory builder = ExternalCallsBuilder.create({callsCount: 1});
        builder.addCall(address(targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (42)));
        return builder.getResult();
    }
}
