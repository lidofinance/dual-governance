// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HashConsensus} from "./HashConsensus.sol";
import {ProposalsList} from "./ProposalsList.sol";
import {ITimelock} from "../interfaces/ITimelock.sol";
import {Timestamp} from "../types/Timestamp.sol";
import {Durations} from "../types/Duration.sol";

enum ProposalType {
    EmergencyExecute,
    EmergencyReset
}

/// @title Emergency Execution Committee Contract
/// @notice This contract allows a committee to vote on and execute emergency proposals
/// @dev Inherits from HashConsensus for voting mechanisms and ProposalsList for proposal management
contract EmergencyExecutionCommittee is HashConsensus, ProposalsList {
    address public immutable EMERGENCY_PROTECTED_TIMELOCK;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) HashConsensus(owner, Durations.from(0)) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;

        _addMembers(committeeMembers, executionQuorum);
    }

    // ---
    // Emergency Execution
    // ---

    /// @notice Votes on an emergency execution proposal
    /// @dev Only callable by committee members
    /// @param proposalId The ID of the proposal to vote on
    /// @param _supports Indicates whether the member supports the proposal execution
    function voteEmergencyExecute(uint256 proposalId, bool _supports) public {
        _checkCallerIsMember();
        (bytes memory proposalData, bytes32 key) = _encodeEmergencyExecute(proposalId);
        _vote(key, _supports);
        _pushProposal(key, uint256(ProposalType.EmergencyExecute), proposalData);
    }

    /// @notice Gets the current state of an emergency execution proposal
    /// @param proposalId The ID of the proposal
    /// @return support The number of votes in support of the proposal
    /// @return executionQuorum The required number of votes for execution
    /// @return quorumAt The timestamp when the quorum was reached
    /// @return isExecuted Whether the proposal has been executed
    function getEmergencyExecuteState(uint256 proposalId)
        public
        view
        returns (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted)
    {
        (, bytes32 key) = _encodeEmergencyExecute(proposalId);
        return _getHashState(key);
    }

    /// @notice Executes an approved emergency execution proposal
    /// @param proposalId The ID of the proposal to execute
    function executeEmergencyExecute(uint256 proposalId) public {
        (, bytes32 key) = _encodeEmergencyExecute(proposalId);
        _markUsed(key);
        Address.functionCall(
            EMERGENCY_PROTECTED_TIMELOCK, abi.encodeWithSelector(ITimelock.emergencyExecute.selector, proposalId)
        );
    }

    /// @dev Encodes the proposal data and generates the proposal key for an emergency execution
    /// @param proposalId The ID of the proposal to encode
    /// @return proposalData The encoded proposal data
    /// @return key The generated proposal key
    function _encodeEmergencyExecute(uint256 proposalId)
        private
        pure
        returns (bytes memory proposalData, bytes32 key)
    {
        proposalData = abi.encode(ProposalType.EmergencyExecute, proposalId);
        key = keccak256(proposalData);
    }

    // ---
    // Governance reset
    // ---

    /// @notice Approves an emergency reset proposal
    /// @dev Only callable by committee members
    function approveEmergencyReset() public {
        _checkCallerIsMember();
        bytes32 proposalKey = _encodeEmergencyResetProposalKey();
        _vote(proposalKey, true);
        _pushProposal(proposalKey, uint256(ProposalType.EmergencyReset), bytes(""));
    }

    /// @notice Gets the current state of an emergency reset proposal
    /// @return support The number of votes in support of the proposal
    /// @return executionQuorum The required number of votes for execution
    /// @return quorumAt The timestamp when the quorum was reached
    /// @return isExecuted Whether the proposal has been executed
    function getEmergencyResetState()
        public
        view
        returns (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted)
    {
        bytes32 proposalKey = _encodeEmergencyResetProposalKey();
        return _getHashState(proposalKey);
    }

    /// @notice Executes an approved emergency reset proposal
    function executeEmergencyReset() external {
        bytes32 proposalKey = _encodeEmergencyResetProposalKey();
        _markUsed(proposalKey);
        Address.functionCall(EMERGENCY_PROTECTED_TIMELOCK, abi.encodeWithSelector(ITimelock.emergencyReset.selector));
    }

    /// @notice Encodes the proposal key for an emergency reset
    /// @return The generated proposal key
    function _encodeEmergencyResetProposalKey() internal pure returns (bytes32) {
        return keccak256(abi.encode(ProposalType.EmergencyReset, bytes32(0)));
    }
}
