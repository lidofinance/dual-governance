// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IExternalExecutor} from "./interfaces/IExternalExecutor.sol";

contract Executor is IExternalExecutor, Ownable {
    constructor(address owner) Ownable(owner) {}

    function execute(
        address target,
        uint256 value,
        bytes calldata payload
    ) external payable returns (bytes memory result) {
        _checkOwner();
        result = Address.functionCallWithValue(target, payload, value);
    }

    receive() external payable {}
}
