// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IExecutor} from "./interfaces/IExecutor.sol";

contract Executor is IExecutor, Ownable {
    constructor(address owner) Ownable(owner) {}

    function execute(
        address target,
        uint256 value,
        bytes calldata payload
    ) external payable onlyOwner returns (bytes memory result) {
        result = Address.functionCallWithValue(target, payload, value);
    }

    receive() external payable {}
}
