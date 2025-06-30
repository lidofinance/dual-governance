// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
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

    function submit(address executor, ExternalCall[] calldata calls) external returns (uint256 newProposalId);
    function schedule(uint256 proposalId) external;
    function execute(uint256 proposalId) external;
    function cancelAllNonExecutedProposals() external;

    function canSchedule(uint256 proposalId) external view returns (bool);
    function canExecute(uint256 proposalId) external view returns (bool);

    function getAdminExecutor() external view returns (address);
    function setAdminExecutor(address newAdminExecutor) external;
    function getGovernance() external view returns (address);
    function setGovernance(address newGovernance) external;

    function getProposal(uint256 proposalId)
        external
        view
        returns (ProposalDetails memory proposalDetails, ExternalCall[] memory calls);
    function getProposalDetails(uint256 proposalId) external view returns (ProposalDetails memory proposalDetails);
    function getProposalCalls(uint256 proposalId) external view returns (ExternalCall[] memory calls);
    function getProposalsCount() external view returns (uint256 count);

    function getAfterSubmitDelay() external view returns (Duration);
    function getAfterScheduleDelay() external view returns (Duration);
    function setAfterSubmitDelay(Duration newAfterSubmitDelay) external;
    function setAfterScheduleDelay(Duration newAfterScheduleDelay) external;
    function transferExecutorOwnership(address executor, address owner) external;
}
