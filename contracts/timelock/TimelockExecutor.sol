// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract TimelockExecutor {
    error NotTimelock(address caller);

    address public immutable TIMELOCK;

    constructor(address owner) {
        TIMELOCK = owner;
    }

    function call(address target, uint256 value, bytes calldata payload) external payable {
        if (msg.sender != TIMELOCK) {
            revert NotTimelock(msg.sender);
        }
        Address.functionCallWithValue(target, payload, value);
    }

    // TODO: uncomment and fix error in _makeCalls when the contract has fallback function
    // receive() external payable {}
}
