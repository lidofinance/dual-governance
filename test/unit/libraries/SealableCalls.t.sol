// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SealableCalls} from "contracts/libraries/SealableCalls.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {SealableMock} from "test/mocks/SealableMock.sol";

contract SealableCallsUnitTests is UnitTest {
    SealableMock private _sealableMock;

    function setUp() public {
        _sealableMock = new SealableMock();
    }

    function testCallPauseForSuccess() public {
        (bool success, bytes memory lowLevelError) = SealableCalls.callPauseFor(_sealableMock, 1 days);

        assertTrue(success);
        assertEq(lowLevelError.length, 0);

        (bool isPausedSuccess,, bool isPaused) = SealableCalls.callIsPaused(_sealableMock);
        assertTrue(isPausedSuccess);
        assertTrue(isPaused);
    }

    function testCallPauseForFailure() public {
        _sealableMock.setShouldRevertPauseFor(true);

        (bool success, bytes memory lowLevelError) = SealableCalls.callPauseFor(_sealableMock, 1 days);
        bytes memory expectedError = abi.encodeWithSignature("Error(string)", "pauseFor failed");

        assertFalse(success);
        assertEq(keccak256(lowLevelError), keccak256(expectedError));
    }

    function testCallIsPausedSuccess() public {
        SealableCalls.callPauseFor(_sealableMock, 1 days);

        (bool success, bytes memory lowLevelError, bool isPaused) = SealableCalls.callIsPaused(_sealableMock);

        assertTrue(success);
        assertTrue(isPaused);
        assertEq(lowLevelError.length, 0);
    }

    function testCallIsPausedFailure() public {
        _sealableMock.setShouldRevertIsPaused(true);

        (bool success, bytes memory lowLevelError, bool isPaused) = SealableCalls.callIsPaused(_sealableMock);
        bytes memory expectedError = abi.encodeWithSignature("Error(string)", "isPaused failed");

        assertFalse(success);
        assertFalse(isPaused);
        assertEq(keccak256(lowLevelError), keccak256(expectedError));
    }

    function testCallResumeSuccess() public {
        SealableCalls.callPauseFor(_sealableMock, 1 days);

        (bool success, bytes memory lowLevelError) = SealableCalls.callResume(_sealableMock);

        assertFalse(success);
        assertEq(lowLevelError.length, 0);

        (bool isPausedSuccess,, bool isPaused) = SealableCalls.callIsPaused(_sealableMock);
        assertTrue(isPausedSuccess);
        assertFalse(isPaused);
    }

    function testCallResumeFailure() public {
        _sealableMock.setShouldRevertResume(true);

        (bool success, bytes memory lowLevelError) = SealableCalls.callResume(_sealableMock);
        bytes memory expectedError = abi.encodeWithSignature("Error(string)", "resume failed");

        assertFalse(success);
        assertEq(keccak256(lowLevelError), keccak256(expectedError));
    }
}
