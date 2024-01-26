// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutorCall} from "../libraries/ScheduledCalls.sol";

interface ITimelock {
    function ADMIN_EXECUTOR() external pure returns (address);

    function schedule(uint256 batchId, address executor, ExecutorCall[] calldata calls) external;
}
