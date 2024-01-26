// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IExecutor {
    function execute(
        address target,
        uint256 value,
        bytes calldata payload
    ) external payable returns (bytes memory result);

    receive() external payable;
}
