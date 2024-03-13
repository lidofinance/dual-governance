// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutorCall} from "./IExecutor.sol";

interface ITimelockController {
    function onSubmitProposal(address sender, address executor) external;
    function onExecuteProposal(address sender, uint256 proposalId) external;
    function onCancelAllProposals(address sender) external;

    function isProposalsSubmissionAllowed() external view returns (bool);
    function isProposalExecutionAllowed(uint256 proposalId) external view returns (bool);
}

interface ITimelock {
    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId);
    function execute(uint256 proposalId) external;
    function cancelAll() external;

    function isDelayPassed(uint256 proposalId) external view returns (bool);
    function isEmergencyProtectionEnabled() external view returns (bool);
    function isProposalSubmitted(uint256 proposalId) external view returns (bool);
    function isProposalCanceled(uint256 proposalId) external view returns (bool);
}
