// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamp} from "contracts/types/Timestamp.sol";
import {ITimelock, ProposalStatus} from "contracts/interfaces/ITimelock.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

contract TimelockMock is ITimelock {
    uint8 public constant OFFSET = 1;

    address internal immutable _ADMIN_EXECUTOR;

    constructor(address adminExecutor) {
        _ADMIN_EXECUTOR = adminExecutor;
    }

    mapping(uint256 => bool) public canScheduleProposal;

    uint256[] public submittedProposals;
    uint256[] public scheduledProposals;
    uint256[] public executedProposals;

    uint256 public lastCancelledProposalId;

    address internal governance;

    function submit(address, ExternalCall[] calldata, string calldata) external returns (uint256 newProposalId) {
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

    function getProposal(uint256 proposalId) external view returns (ProposalDetails memory, ExternalCall[] memory) {
        revert("Not Implemented");
    }

    function setGovernance(address newGovernance) external {
        governance = newGovernance;
    }

    function getGovernance() external view returns (address) {
        return governance;
    }

    function emergencyReset() external {
        revert("Not Implemented");
    }

    function emergencyExecute(uint256 proposalId) external {
        revert("Not Implemented");
    }

    function activateEmergencyMode() external {
        revert("Not Implemented");
    }

    function getProposalDetails(uint256 proposalId) external view returns (ProposalDetails memory) {
        revert("Not Implemented");
    }

    function getProposalsCount() external view returns (uint256 count) {
        return submittedProposals.length;
    }

    function getAdminExecutor() external view returns (address) {
        return _ADMIN_EXECUTOR;
    }
}
