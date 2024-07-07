// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Timestamp} from "../types/Timestamp.sol";
import {ExecutorCall} from "./IExecutor.sol";

interface IGovernance {
    function submitProposal(ExecutorCall[] calldata calls) external returns (uint256 proposalId);
    function scheduleProposal(uint256 proposalId) external;
    function cancelAllPendingProposals() external;

    function canSchedule(uint256 proposalId) external view returns (bool);
}

interface ITimelock {
    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId);
    function schedule(uint256 proposalId) external;
    function execute(uint256 proposalId) external;
    function cancelAllNonExecutedProposals() external;

    function canSchedule(uint256 proposalId) external view returns (bool);
    function canExecute(uint256 proposalId) external view returns (bool);

    function getProposalSubmissionTime(uint256 proposalId) external view returns (Timestamp submittedAt);
}
