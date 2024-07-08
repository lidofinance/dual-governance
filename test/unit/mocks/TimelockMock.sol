// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Timestamp} from "contracts/types/Timestamp.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {ExecutorCall} from "contracts/libraries/Proposals.sol";

contract TimelockMock is ITimelock {
    uint8 public constant OFFSET = 1;

    mapping(uint256 => bool) public canScheduleProposal;

    uint256[] public submittedProposals;
    uint256[] public scheduledProposals;
    uint256[] public executedProposals;

    uint256 public lastCancelledProposalId;

    function submit(address, ExecutorCall[] calldata) external returns (uint256 newProposalId) {
        newProposalId = submittedProposals.length + OFFSET;
        submittedProposals.push(newProposalId);
        canScheduleProposal[newProposalId] = false;
        return newProposalId;
    }

    function schedule(uint256 proposalId) external {
        if (canScheduleProposal[proposalId] == false) {
            revert();
        }

        scheduledProposals.push(proposalId);
    }

    function execute(uint256 proposalId) external {
        executedProposals.push(proposalId);
    }

    function canExecute(uint256 proposalId) external view returns (bool) {
        revert("Not Implemented");
    }

    function canSchedule(uint256 proposalId) external view returns (bool) {
        return canScheduleProposal[proposalId];
    }

    function cancelAllNonExecutedProposals() external {
        lastCancelledProposalId = submittedProposals[submittedProposals.length - 1];
    }

    function setSchedule(uint256 proposalId) external {
        canScheduleProposal[proposalId] = true;
    }

    function getSubmittedProposals() external view returns (uint256[] memory) {
        return submittedProposals;
    }

    function getScheduledProposals() external view returns (uint256[] memory) {
        return scheduledProposals;
    }

    function getExecutedProposals() external view returns (uint256[] memory) {
        return executedProposals;
    }

    function getLastCancelledProposalId() external view returns (uint256) {
        return lastCancelledProposalId;
    }

    function getProposalSubmissionTime(uint256 proposalId) external view returns (Timestamp submittedAt) {
        revert("Not Implemented");
    }
}
