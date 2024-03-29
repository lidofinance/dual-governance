// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutorCall} from "./IExecutor.sol";

interface IGovernance {
    function submit(ExecutorCall[] calldata calls) external returns (uint256 proposalId);
    function schedule(uint256 proposalId) external;
    function cancelAll() external;

    function canSchedule(uint256 proposalId) external view returns (bool);
}

interface ITimelock {
    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId);
    function schedule(uint256 proposalId) external;
    function execute(uint256 proposalId) external;
    function cancelAll() external;

    function canSchedule(uint256 proposalId) external view returns (bool);
    function canExecute(uint256 proposalId) external view returns (bool);
}
