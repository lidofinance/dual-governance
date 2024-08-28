// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISealable} from "../interfaces/ISealable.sol";

/// @title SealableCalls Library
/// @dev A library for making calls to a contract implementing the ISealable interface.
library SealableCalls {
    /// @dev Calls the `pauseFor` function on a `Sealable` contract with the specified `sealDuration`.
    /// If the call is successful and the contract is paused, it returns `true` and low-level error message, if any.
    /// If the call fails, it returns `false` and the low-level error message.
    ///
    /// @param sealable The `Sealable` contract to call the `pauseFor` function on.
    /// @param sealDuration The duration for which the contract should be paused.
    ///
    /// @return success A boolean indicating whether the call to `pauseFor` was successful and the contract is paused.
    /// @return lowLevelError The low-level error message, if any, encountered during the call to `pauseFor`.
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

    /// @dev Calls the `isPaused` function on a `Sealable` contract to check if the contract is currently paused.
    /// If the call is successful, it returns `true` indicating that the contract is paused, along with a low-level error message if any.
    /// If the call fails, it returns `false` and the low-level error message encountered during the call.
    ///
    /// @param sealable The `Sealable` contract to call the `isPaused` function on.
    ///
    /// @return success A boolean indicating whether the call to `isPaused` was successful.
    /// @return lowLevelError The low-level error message, if any, encountered during the call to `isPaused`.
    /// @return isPaused A boolean indicating whether the contract is currently paused.
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

    /// @dev Calls the `resume` function on a `Sealable` contract to resume the contract's functionality.
    /// If the call is successful and the contract is resumed, it returns `true` and a low-level error message, if any.
    /// If the call fails, it returns `false` and the low-level error message encountered during the call.
    ///
    /// @param sealable The `Sealable` contract to call the `resume` function on.
    ///
    /// @return success A boolean indicating whether the call to `resume` was successful and the contract is resumed.
    /// @return lowLevelError The low-level error message, if any, encountered during the call to `resume`.
    function callResume(ISealable sealable) internal returns (bool success, bytes memory lowLevelError) {
        try sealable.resume() {
            (bool isPausedCallSuccess, bytes memory isPausedLowLevelError, bool isPaused) = callIsPaused(sealable);
            success = isPausedCallSuccess && !isPaused;
            lowLevelError = isPausedLowLevelError;
        } catch (bytes memory resumeLowLevelError) {
            success = false;
            lowLevelError = resumeLowLevelError;
        }
    }
}
