// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IExternalExecutor} from "./interfaces/IExternalExecutor.sol";

/// @title Executor
/// @notice Allows the contract owner to execute external function calls on specified target contracts with
///     possible value transfers.
contract Executor is IExternalExecutor, Ownable {
    constructor(address owner) Ownable(owner) {}

    /// @notice Allows the contract owner to execute external function calls on target contracts, optionally transferring ether.
    /// @param target The address of the target contract on which to execute the function call.
    /// @param value The amount of ether (in wei) to send with the function call.
    /// @param payload The calldata for the function call.
    /// @return result The data returned from the function call.
    function execute(
        address target,
        uint256 value,
        bytes calldata payload
    ) external payable returns (bytes memory result) {
        _checkOwner();
        result = Address.functionCallWithValue(target, payload, value);
    }

    /// @notice Allows the contract to receive ether.
    receive() external payable {}
}
