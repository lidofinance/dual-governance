// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Duration} from "../types/Duration.sol";
import {Timestamp} from "../types/Timestamp.sol";

import {IDualGovernance} from "../interfaces/IDualGovernance.sol";

import {HashConsensus} from "./HashConsensus.sol";
import {ProposalsList} from "./ProposalsList.sol";

/// @title Reseal Committee Contract
/// @notice This contract allows a committee to vote on and execute resealing proposals
/// @dev Inherits from HashConsensus for voting mechanisms and ProposalsList for proposal management
contract ResealCommittee is HashConsensus, ProposalsList {
    error InvalidSealable(address sealable);

    address public immutable DUAL_GOVERNANCE;

    mapping(bytes32 hash => uint256 nonce) private _resealNonces;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address dualGovernance,
        Duration timelock
    ) HashConsensus(owner, timelock) {
        DUAL_GOVERNANCE = dualGovernance;

        _addMembers(committeeMembers, executionQuorum);
    }

    /// @notice Votes on a reseal proposal
    /// @dev Allows committee members to vote on resealing a sealed address
    /// @param sealable The address to reseal
    /// @param support Indicates whether the member supports the proposal
    function voteReseal(address sealable, bool support) external {
        _checkCallerIsMember();

        if (sealable == address(0)) {
            revert InvalidSealable(sealable);
        }

        (bytes memory proposalData, bytes32 key) = _encodeResealProposal(sealable);
        _vote(key, support);
        _pushProposal(key, 0, proposalData);
    }

    /// @notice Gets the current state of a reseal proposal
    /// @dev Retrieves the state of the reseal proposal for a sealed address
    /// @param sealable The addresses for the reseal proposal
    /// @return support The number of votes in support of the proposal
    /// @return executionQuorum The required number of votes for execution
    /// @return quorumAt The timestamp when the quorum was reached
    function getResealState(address sealable)
        external
        view
        returns (uint256 support, uint256 executionQuorum, Timestamp quorumAt)
    {
        (, bytes32 key) = _encodeResealProposal(sealable);
        (support, executionQuorum, quorumAt,) = _getHashState(key);
    }

    /// @notice Executes an approved reseal proposal
    /// @dev Executes the reseal proposal by calling the reseal function on the Dual Governance contract
    /// @param sealable The address to reseal
    function executeReseal(address sealable) external {
        (, bytes32 key) = _encodeResealProposal(sealable);
        _markUsed(key);

        Address.functionCall(DUAL_GOVERNANCE, abi.encodeWithSelector(IDualGovernance.resealSealable.selector, sealable));

        bytes32 resealNonceHash = keccak256(abi.encode(sealable));
        _resealNonces[resealNonceHash]++;
    }

    /// @notice Encodes a reseal proposal
    /// @dev Internal function to encode the proposal data and generate the proposal key
    /// @param sealable The address to reseal
    /// @return data The encoded proposal data
    /// @return key The generated proposal key
    function _encodeResealProposal(address sealable) internal view returns (bytes memory data, bytes32 key) {
        bytes32 resealNonceHash = keccak256(abi.encode(sealable));
        data = abi.encode(sealable, _resealNonces[resealNonceHash]);
        key = keccak256(data);
    }
}
