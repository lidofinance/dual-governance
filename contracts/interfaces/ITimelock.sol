// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutorCall} from "../libraries/ScheduledCalls.sol";

interface ITimelock {
    function ADMIN_EXECUTOR() external view returns (address);

    function relay(address executor, ExecutorCall[] calldata calls) external;

    function schedule(uint256 batchId, address executor, ExecutorCall[] calldata calls) external;

    function execute(uint256 batchId) external;
}
