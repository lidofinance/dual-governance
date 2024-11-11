// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IExternalExecutor} from "../interfaces/IExternalExecutor.sol";

/// @notice Represents an external call to a specific address with an optional ETH transfer.
/// @param target The address to call.
/// @param value The amount of ETH (in wei) to transfer with the call, capped at approximately 7.9 billion ETH.
/// @param payload The calldata payload sent to the target address.
struct ExternalCall {
    address target;
    uint96 value;
    bytes payload;
}

/// @title External Calls Library
/// @notice Provides functionality for executing multiple external calls through an `IExternalExecutor` contract.
library ExternalCalls {
    /// @notice Executes a series of external calls using the provided executor, which implements the
    ///     `IExternalExecutor` interface.
    /// @param calls An array of `ExternalCall` structs, each specifying a call to be executed.
    /// @param executor The contract responsible for executing each call, conforming to the `IExternalExecutor` interface.
    /// @return results An array containing the return data from each call.
    function execute(
        ExternalCall[] memory calls,
        IExternalExecutor executor
    ) internal returns (bytes[] memory results) {
        uint256 callsCount = calls.length;
        results = new bytes[](callsCount);
        for (uint256 i = 0; i < callsCount; ++i) {
            results[i] = executor.execute(calls[i].target, calls[i].value, calls[i].payload);
        }
    }
}
