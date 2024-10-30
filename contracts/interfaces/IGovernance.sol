// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITimelock} from "./ITimelock.sol";

import {ExternalCall} from "../libraries/ExternalCalls.sol";

interface IGovernance {
    function TIMELOCK() external view returns (ITimelock);
    function submitProposal(
        ExternalCall[] calldata calls,
        string calldata metadata
    ) external returns (uint256 proposalId);
    function scheduleProposal(uint256 proposalId) external;
    function cancelAllPendingProposals() external;

    function canScheduleProposal(uint256 proposalId) external view returns (bool);
}
