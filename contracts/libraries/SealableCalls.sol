// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISealable} from "../interfaces/ISealable.sol";

library SealableCalls {
    function callPauseFor(
        ISealable sealable,
        uint256 sealDuration
    ) internal returns (bool success, bytes memory lowLevelError) {
        try sealable.pauseFor(sealDuration) {
            (bool isPausedCallSuccess, bytes memory isPausedLowLevelError, bool isPaused) = callIsPaused(sealable);
            success = isPausedCallSuccess && isPaused;
            lowLevelError = isPausedLowLevelError;
        } catch (bytes memory pauseForLowLevelError) {
            success = false;
            lowLevelError = pauseForLowLevelError;
        }
    }

    function callIsPaused(ISealable sealable)
        internal
        view
        returns (bool success, bytes memory lowLevelError, bool isPaused)
    {
        try sealable.isPaused() returns (bool isPausedResult) {
            success = true;
            isPaused = isPausedResult;
        } catch (bytes memory isPausedLowLevelError) {
            success = false;
            lowLevelError = isPausedLowLevelError;
        }
    }

    function callResume(ISealable sealable) internal returns (bool success, bytes memory lowLevelError) {
        try sealable.resume() {
            (bool isPausedCallSuccess, bytes memory isPausedLowLevelError, bool isPaused) = callIsPaused(sealable);
            success = isPausedCallSuccess && isPaused;
            lowLevelError = isPausedLowLevelError;
        } catch (bytes memory resumeLowLevelError) {
            success = false;
            lowLevelError = resumeLowLevelError;
        }
    }
}
