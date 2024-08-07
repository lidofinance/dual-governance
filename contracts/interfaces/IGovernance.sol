// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall} from "../libraries/ExternalCalls.sol";

interface IGovernance {
    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId);
    function scheduleProposal(uint256 proposalId) external;
    function cancelAllPendingProposals() external;

    function canScheduleProposal(uint256 proposalId) external view returns (bool);
}
