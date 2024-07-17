// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HashConsensus} from "./HashConsensus.sol";
import {ProposalsList} from "./ProposalsList.sol";

interface IDualGovernance {
    function reseal(address[] memory sealables) external;
}

/// @title Reseal Committee Contract
/// @notice This contract allows a committee to vote on and execute resealing proposals
/// @dev Inherits from HashConsensus for voting mechanisms and ProposalsList for proposal management
contract ResealCommittee is HashConsensus, ProposalsList {
    address public immutable DUAL_GOVERNANCE;

    mapping(bytes32 => uint256) private _resealNonces;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address dualGovernance,
        uint256 timelock
    ) HashConsensus(owner, committeeMembers, executionQuorum, timelock) {
        DUAL_GOVERNANCE = dualGovernance;
    }

    /// @notice Votes on a reseal proposal
    /// @dev Allows committee members to vote on resealing a set of addresses
    /// @param sealables The addresses to reseal
    /// @param support Indicates whether the member supports the proposal
    function voteReseal(address[] memory sealables, bool support) public onlyMember {
        (bytes memory proposalData, bytes32 key) = _encodeResealProposal(sealables);
        _vote(key, support);
        _pushProposal(key, 0, proposalData);
    }

    /// @notice Gets the current state of a reseal proposal
    /// @dev Retrieves the state of the reseal proposal for a set of addresses
    /// @param sealables The addresses for the reseal proposal
    /// @return support The number of votes in support of the proposal
    /// @return execuitionQuorum The required number of votes for execution
    /// @return isExecuted Whether the proposal has been executed
    function getResealState(address[] memory sealables)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        (, bytes32 key) = _encodeResealProposal(sealables);
        return _getHashState(key);
    }

    /// @notice Executes an approved reseal proposal
    /// @dev Executes the reseal proposal by calling the reseal function on the Dual Governance contract
    /// @param sealables The addresses to reseal
    function executeReseal(address[] memory sealables) external {
        (, bytes32 key) = _encodeResealProposal(sealables);
        _markUsed(key);

        Address.functionCall(DUAL_GOVERNANCE, abi.encodeWithSelector(IDualGovernance.reseal.selector, sealables));

        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        _resealNonces[resealNonceHash]++;
    }

    /// @notice Encodes a reseal proposal
    /// @dev Internal function to encode the proposal data and generate the proposal key
    /// @param sealables The addresses to reseal
    /// @return data The encoded proposal data
    /// @return key The generated proposal key
    function _encodeResealProposal(address[] memory sealables) internal view returns (bytes memory data, bytes32 key) {
        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        data = abi.encode(sealables, _resealNonces[resealNonceHash]);
        key = keccak256(data);
    }
}
