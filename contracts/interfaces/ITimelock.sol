// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamp} from "../types/Timestamp.sol";

import {ExternalCall} from "../libraries/ExternalCalls.sol";
import {Status as ProposalStatus} from "../libraries/ExecutableProposals.sol";

interface ITimelock {
    struct ProposalDetails {
        uint256 id;
        address executor;
        Timestamp submittedAt;
        Timestamp scheduledAt;
        ProposalStatus status;
    }

    function submit(
        address executor,
        ExternalCall[] calldata calls,
        string calldata metadata
    ) external returns (uint256 newProposalId);
    function schedule(uint256 proposalId) external;
    function execute(uint256 proposalId) external;
    function cancelAllNonExecutedProposals() external;

    function canSchedule(uint256 proposalId) external view returns (bool);
    function canExecute(uint256 proposalId) external view returns (bool);

    function getAdminExecutor() external view returns (address);
    function getGovernance() external view returns (address);
    function setGovernance(address newGovernance) external;

    function getProposal(uint256 proposalId)
        external
        view
        returns (ProposalDetails memory proposalDetails, ExternalCall[] memory calls);
    function getProposalDetails(uint256 proposalId) external view returns (ProposalDetails memory proposalDetails);
    function getProposalsCount() external view returns (uint256 count);
}
