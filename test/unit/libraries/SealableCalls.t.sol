// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SealableCalls} from "contracts/libraries/SealableCalls.sol";
import {ISealable} from "contracts/interfaces/ISealable.sol";

import {UnitTest} from "test/utils/unit-test.sol";

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

contract SealableMock is ISealable {
    bool private paused;
    bool private shouldRevertPauseFor;
    bool private shouldRevertIsPaused;
    bool private shouldRevertResume;

    function getResumeSinceTimestamp() external view override returns (uint256) {
        revert("Not implemented");
    }

    function setShouldRevertPauseFor(bool _shouldRevert) external {
        shouldRevertPauseFor = _shouldRevert;
    }

    function setShouldRevertIsPaused(bool _shouldRevert) external {
        shouldRevertIsPaused = _shouldRevert;
    }

    function setShouldRevertResume(bool _shouldRevert) external {
        shouldRevertResume = _shouldRevert;
    }

    function pauseFor(uint256) external override {
        if (shouldRevertPauseFor) {
            revert("pauseFor failed");
        }
        paused = true;
    }

    function isPaused() external view override returns (bool) {
        if (shouldRevertIsPaused) {
            revert("isPaused failed");
        }
        return paused;
    }

    function resume() external override {
        if (shouldRevertResume) {
            revert("resume failed");
        }
        paused = false;
    }
}
