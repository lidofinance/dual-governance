// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISealable} from "../interfaces/ISealable.sol";

library SealableCalls {
    /// @notice Attempts to call `ISealable.isPaused()` method, returning whether the call succeeded and the result
    ///     of the `ISealable.isPaused()` call if it succeeded.
    /// @dev This function performs a static call to the `isPaused` method of the `ISealable` interface.
    ///     It ensures that the function does not revert even if the sealable contract does not implement
    ///     the interface, has no code at the address, or returns unexpected data.
    /// @param sealable The address of the sealable contract to check.
    /// @return success Indicates whether the call to `isPaused` was successful.
    /// @return isPaused Indicates whether the sealable contract is paused. Returns `false` if the call failed
    ///     or returned an invalid value.
    function callIsPaused(address sealable) internal view returns (bool success, bool isPaused) {
        // Low-level call to the `isPaused` function on the `sealable` contract
        (bool isCallSucceed, bytes memory returndata) =
            sealable.staticcall(abi.encodeWithSelector(ISealable.isPaused.selector));

        // Check if the call succeeded and returned the expected data length (32 bytes, single EVM word)
        if (isCallSucceed && returndata.length == 32) {
            uint256 resultAsUint256 = abi.decode(returndata, (uint256));

            // If the resulting value is greater than 1, the call is considered invalid as it returns an out-of-bound boolean value
            success = resultAsUint256 <= 1;

            // Cast uint256 into boolean (0 = false, 1 = true)
            isPaused = resultAsUint256 == 1;
        }
    }
}
