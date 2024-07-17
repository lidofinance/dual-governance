// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

struct ExecutorCall {
    address target;
    uint96 value; // ~ 7.9 billion ETH
    bytes payload;
}

interface IExecutor {
    function execute(
        address target,
        uint256 value,
        bytes calldata payload
    ) external payable returns (bytes memory result);

    receive() external payable;
}
