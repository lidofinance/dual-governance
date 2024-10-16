// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISealable} from "../interfaces/ISealable.sol";

/// @dev All calls to sealable addresses less than MIN_VALID_SEALABLE_ADDRESS are treated as unsuccessful
///     to prevent potential false positives for current or future precompiled addresses.
address constant MIN_VALID_SEALABLE_ADDRESS = address(1024);

library SealableCalls {
    /// @notice Attempts to call `ISealable.getResumeSinceTimestamp()` method, returning whether the call succeeded
    ///     and the result of the `ISealable.getResumeSinceTimestamp()` call if it succeeded.
    /// @dev Performs a static call to the `getResumeSinceTimestamp()` method on the `ISealable` interface.
    ///     Ensures that the function does not revert even if the `sealable` contract does not implement
    ///     the interface, has no code at the address, or returns unexpected data.
    ///     Calls to addresses less than `MIN_VALID_SEALABLE_ADDRESS` are treated as unsuccessful to prevent
    ///     potential false positives from current or future precompiled addresses.
    /// @param sealable The address of the sealable contract to check.
    /// @return success Indicates whether the call to `getResumeSinceTimestamp()` was successful.
    /// @return resumeSinceTimestamp The timestamp when the contract is expected to become unpaused.
    ///     If the value is less than `block.timestamp`, it indicates the contract resumed in the past;
    ///     if `type(uint256).max`, the contract is paused indefinitely.
    function callGetResumeSinceTimestamp(address sealable)
        external
        view
        returns (bool success, uint256 resumeSinceTimestamp)
    {
        if (sealable < MIN_VALID_SEALABLE_ADDRESS) {
            return (false, 0);
        }

        // Low-level call to the `getResumeSinceTimestamp` function on the `sealable` contract
        (bool isCallSucceed, bytes memory returndata) =
            sealable.staticcall(abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector));

        // Check if the call succeeded and returned the expected data length (32 bytes, single uint256)
        if (isCallSucceed && returndata.length == 32) {
            success = true;
            resumeSinceTimestamp = abi.decode(returndata, (uint256));
        }
    }
}
