// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IExternalExecutor} from "./interfaces/IExternalExecutor.sol";

/// @title Executor
/// @notice Allows the designated operator to execute external function calls on specified target contracts with
///     possible value transfers. The owner can set the operator.
contract Executor is IExternalExecutor, Ownable {
    // ---
    // Events
    // ---

    event OperatorSet(address indexed newOperator);
    event Execute(address indexed sender, address indexed target, uint256 ethValue, bytes data);

    // ---
    // Errors
    // ---

    error CallerIsNotOperator(address caller);
    error InvalidOperator(address account);

    // ---
    // Storage variables
    // ---

    address private _operator;

    // ---
    // Constructor
    // ---

    constructor(address owner, address operator) Ownable(owner) {
        _setOperator(operator);
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Allows the operator to execute external function calls on target contracts, optionally transferring ether.
    /// @param target The address of the target contract on which to execute the function call.
    /// @param value The amount of ether (in wei) to send with the function call.
    /// @param payload The calldata for the function call.
    function execute(address target, uint256 value, bytes calldata payload) external payable {
        if (msg.sender != _operator) {
            revert CallerIsNotOperator(msg.sender);
        }
        Address.functionCallWithValue(target, payload, value);
        emit Execute(msg.sender, target, value, payload);
    }

    // ---
    // Management Operations
    // ---

    /// @notice Allows the owner to set a new operator.
    /// @param newOperator The address of the new operator.
    function setOperator(address newOperator) external onlyOwner {
        _setOperator(newOperator);
    }

    /// @notice Returns the current operator.
    /// @return operator The address of the current operator.
    function getOperator() external view returns (address operator) {
        return _operator;
    }

    /// @notice Allows the contract to receive ether.
    receive() external payable {}

    // ---
    // Internal Methods
    // ---

    function _setOperator(address newOperator) internal {
        if (newOperator == address(0) || newOperator == _operator) {
            revert InvalidOperator(newOperator);
        }
        _operator = newOperator;
        emit OperatorSet(newOperator);
    }
}
