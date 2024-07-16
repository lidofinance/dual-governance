// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Timestamp} from "../types/Timestamp.sol";

import {Status as TimelockProposalStatus} from "../libraries/ExecutableProposals.sol";
import {ExternalCall} from "../libraries/ExternalCalls.sol";

interface IGovernance {
    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId);
    function scheduleProposal(uint256 proposalId) external;
    function cancelAllPendingProposals() external;

    function canSchedule(uint256 proposalId) external view returns (bool);
}

interface ITimelock {
    struct Proposal {
        uint256 id;
        bool isCancelled;
        address executor;
        TimelockProposalStatus status;
        Timestamp submittedAt;
        Timestamp scheduledAt;
        ExternalCall[] calls;
    }

    struct ProposalState {
        uint256 id;
        bool isCancelled;
        address executor;
        TimelockProposalStatus status;
        Timestamp submittedAt;
        Timestamp scheduledAt;
        Timestamp executedAt;
    }

    function submit(address executor, ExternalCall[] calldata calls) external returns (uint256 newProposalId);
    function schedule(uint256 proposalId) external;
    function execute(uint256 proposalId) external;
    function cancelAllNonExecutedProposals() external;

    function canSchedule(uint256 proposalId) external view returns (bool);
    function canExecute(uint256 proposalId) external view returns (bool);

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal);
    function getProposalState(uint256 proposalId) external view returns (ProposalState memory);
}
