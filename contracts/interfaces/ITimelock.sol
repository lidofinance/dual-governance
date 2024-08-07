// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamp} from "../types/Timestamp.sol";

import {ExternalCall} from "../libraries/ExternalCalls.sol";
import {Status as ProposalStatus} from "../libraries/ExecutableProposals.sol";

interface ITimelock {
    struct Proposal {
        uint256 id;
        ProposalStatus status;
        address executor;
        Timestamp submittedAt;
        Timestamp scheduledAt;
        ExternalCall[] calls;
    }

    function submit(address executor, ExternalCall[] calldata calls) external returns (uint256 newProposalId);
    function schedule(uint256 proposalId) external;
    function execute(uint256 proposalId) external;
    function cancelAllNonExecutedProposals() external;

    function canSchedule(uint256 proposalId) external view returns (bool);
    function canExecute(uint256 proposalId) external view returns (bool);

    function getAdminExecutor() external view returns (address);

    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal);
    function getProposalInfo(uint256 proposalId)
        external
        view
        returns (uint256 id, ProposalStatus status, address executor, Timestamp submittedAt, Timestamp scheduledAt);

    function getGovernance() external view returns (address);
    function setGovernance(address governance) external;

    function activateEmergencyMode() external;
    function emergencyExecute(uint256 proposalId) external;
    function emergencyReset() external;
}
