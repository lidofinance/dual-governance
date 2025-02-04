// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Durations} from "../types/Duration.sol";
import {Timestamp} from "../types/Timestamp.sol";

import {ITiebreakerCoreCommittee} from "../interfaces/ITiebreakerCoreCommittee.sol";

import {HashConsensus} from "./HashConsensus.sol";
import {ProposalsList} from "./ProposalsList.sol";

enum ProposalType {
    ScheduleProposal,
    ResumeSealable
}

/// @title Tiebreaker SubCommittee Contract
/// @notice This contract allows a subcommittee to vote on and execute proposals for scheduling and resuming sealable addresses
/// @dev Inherits from HashConsensus for voting mechanisms and ProposalsList for proposal management
contract TiebreakerSubCommittee is HashConsensus, ProposalsList {
    address public immutable TIEBREAKER_CORE_COMMITTEE;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address tiebreakerCoreCommittee
    ) HashConsensus(owner, Durations.ZERO) {
        TIEBREAKER_CORE_COMMITTEE = tiebreakerCoreCommittee;

        _addMembers(committeeMembers, executionQuorum);
    }

    // ---
    // Schedule proposal
    // ---

    /// @notice Votes on a proposal to schedule
    /// @dev Allows committee members to vote on scheduling a proposal
    /// @param proposalId The ID of the proposal to schedule
    function scheduleProposal(uint256 proposalId) external {
        _checkCallerIsMember();
        ITiebreakerCoreCommittee(TIEBREAKER_CORE_COMMITTEE).checkProposalExists(proposalId);
        (bytes memory proposalData, bytes32 key) = _encodeApproveProposal(proposalId);
        _vote(key, true);
        _pushProposal(key, uint256(ProposalType.ScheduleProposal), proposalData);
    }

    /// @notice Gets the current state of a schedule proposal
    /// @dev Retrieves the state of the schedule proposal for a given proposal ID
    /// @param proposalId The ID of the proposal
    /// @return support The number of votes in support of the proposal
    /// @return executionQuorum The required number of votes for execution
    /// @return quorumAt The number of votes required to reach quorum
    /// @return isExecuted Whether the proposal has been executed
    function getScheduleProposalState(uint256 proposalId)
        external
        view
        returns (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted)
    {
        (, bytes32 key) = _encodeApproveProposal(proposalId);
        return _getHashState(key);
    }

    /// @notice Executes an approved schedule proposal
    /// @dev Executes the schedule proposal by calling the scheduleProposal function on the Tiebreaker Core contract
    /// @param proposalId The ID of the proposal to schedule
    function executeScheduleProposal(uint256 proposalId) external {
        (, bytes32 key) = _encodeApproveProposal(proposalId);
        _markUsed(key);
        Address.functionCall(
            TIEBREAKER_CORE_COMMITTEE,
            abi.encodeWithSelector(ITiebreakerCoreCommittee.scheduleProposal.selector, proposalId)
        );
    }

    /// @notice Encodes a schedule proposal
    /// @dev Internal function to encode the proposal data and generate the proposal key
    /// @param proposalId The ID of the proposal to schedule
    /// @return data The encoded proposal data
    /// @return key The generated proposal key
    function _encodeApproveProposal(uint256 proposalId) internal pure returns (bytes memory data, bytes32 key) {
        data = abi.encode(ProposalType.ScheduleProposal, proposalId);
        key = keccak256(data);
    }

    // ---
    // Sealable resume
    // ---

    /// @notice Votes on a proposal to resume a sealable address
    /// @dev Allows committee members to vote on resuming a sealable address
    ///      reverts if the sealable address is the zero address or if the sealable address is not paused
    /// @param sealable The address to resume
    function sealableResume(address sealable) external {
        _checkCallerIsMember();
        ITiebreakerCoreCommittee(TIEBREAKER_CORE_COMMITTEE).checkSealableIsPaused(sealable);

        (bytes memory proposalData, bytes32 key,) = _encodeSealableResume(sealable);
        _vote(key, true);
        _pushProposal(key, uint256(ProposalType.ResumeSealable), proposalData);
    }

    /// @notice Gets the current state of a resume sealable proposal
    /// @dev Retrieves the state of the resume sealable proposal for a given address
    /// @param sealable The address to resume
    /// @return support The number of votes in support of the proposal
    /// @return executionQuorum The required number of votes for execution
    /// @return quorumAt The timestamp when the quorum was reached
    /// @return isExecuted Whether the proposal has been executed
    function getSealableResumeState(address sealable)
        external
        view
        returns (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted)
    {
        (, bytes32 key,) = _encodeSealableResume(sealable);
        return _getHashState(key);
    }

    /// @notice Executes an approved resume sealable proposal
    /// @dev Executes the resume sealable proposal by calling the sealableResume function on the Tiebreaker Core contract
    /// @param sealable The address to resume
    function executeSealableResume(address sealable) external {
        (, bytes32 key, uint256 nonce) = _encodeSealableResume(sealable);
        _markUsed(key);
        Address.functionCall(
            TIEBREAKER_CORE_COMMITTEE,
            abi.encodeWithSelector(ITiebreakerCoreCommittee.sealableResume.selector, sealable, nonce)
        );
    }

    /// @notice Encodes a resume sealable proposal
    /// @dev Internal function to encode the proposal data and generate the proposal key
    /// @param sealable The address to resume
    /// @return data The encoded proposal data
    /// @return key The generated proposal key
    /// @return nonce The current resume nonce for the sealable address
    function _encodeSealableResume(address sealable)
        internal
        view
        returns (bytes memory data, bytes32 key, uint256 nonce)
    {
        nonce = ITiebreakerCoreCommittee(TIEBREAKER_CORE_COMMITTEE).getSealableResumeNonce(sealable);
        data = abi.encode(ProposalType.ResumeSealable, sealable, nonce);
        key = keccak256(data);
    }
}
