// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

// solhint-disable-next-line
import {Test, console} from "forge-std/Test.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";
import {IDangerousContract} from "test/utils/interfaces.sol";
import {Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";

contract UnitTest is Test {
    function _wait(Duration duration) internal {
        vm.warp(block.timestamp + Duration.unwrap(duration));
    }

    function _getTargetRegularStaffCalls(address targetMock) internal pure returns (ExternalCall[] memory) {
        return ExternalCallHelpers.create(address(targetMock), abi.encodeCall(IDangerousContract.doRegularStaff, (42)));
    }

    function assertEq(Timestamp a, Timestamp b) internal {
        assertEq(uint256(Timestamp.unwrap(a)), uint256(Timestamp.unwrap(b)));
    }

    function assertEq(Timestamp a, Timestamp b, string memory message) internal {
        assertEq(uint256(Timestamp.unwrap(a)), uint256(Timestamp.unwrap(b)), message);
    }

    function assertEq(Duration a, Duration b) internal {
        assertEq(uint256(Duration.unwrap(a)), uint256(Duration.unwrap(b)));
    }

    function assertEq(Duration a, Duration b, string memory message) internal {
        assertEq(uint256(Duration.unwrap(a)), uint256(Duration.unwrap(b)), message);
    }

    function assertEq(ProposalStatus a, ProposalStatus b) internal {
        assertEq(uint256(a), uint256(b));
    }

    function assertEq(ProposalStatus a, ProposalStatus b, string memory message) internal {
        assertEq(uint256(a), uint256(b), message);
    }
}
