// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableProposals, Proposal} from "../libraries/EnumerableProposals.sol";

/// @title Proposals List Contract
/// @notice This contract manages a list of proposals using an enumerable map
/// @dev Uses the EnumerableProposals library for managing proposals
contract ProposalsList {
    using EnumerableProposals for EnumerableProposals.Bytes32ToProposalMap;

    EnumerableProposals.Bytes32ToProposalMap internal _proposals;

    /// @notice Retrieves a list of proposals with pagination
    /// @dev Fetches an ordered list of proposals based on the offset and limit
    /// @param offset The starting index for the list of proposals
    /// @param limit The maximum number of proposals to return
    /// @return proposals An array of Proposal structs
    function getProposals(uint256 offset, uint256 limit) external view returns (Proposal[] memory proposals) {
        bytes32[] memory keys = _proposals.getOrderedKeys(offset, limit);

        uint256 length = keys.length;
        proposals = new Proposal[](length);

        for (uint256 i = 0; i < length; ++i) {
            proposals[i] = _proposals.get(keys[i]);
        }
    }

    /// @notice Retrieves a proposal at a specific index
    /// @dev Fetches the proposal located at the specified index in the map
    /// @param index The index of the proposal to retrieve
    /// @return The Proposal struct at the given index
    function getProposalAt(uint256 index) external view returns (Proposal memory) {
        return _proposals.at(index);
    }

    /// @notice Retrieves a proposal by its key
    /// @dev Fetches the proposal associated with the given key
    /// @param key The key of the proposal to retrieve
    /// @return The Proposal struct associated with the given key
    function getProposal(bytes32 key) external view returns (Proposal memory) {
        return _proposals.get(key);
    }

    /// @notice Retrieves the total number of proposals
    /// @dev Fetches the length of the proposals map
    /// @return The total number of proposals
    function getProposalsLength() external view returns (uint256) {
        return _proposals.length();
    }

    /// @notice Retrieves an ordered list of proposal keys with pagination
    /// @dev Fetches the keys of the proposals based on the offset and limit
    /// @param offset The starting index for the list of keys
    /// @param limit The maximum number of keys to return
    /// @return An array of proposal keys
    function getOrderedKeys(uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        return _proposals.getOrderedKeys(offset, limit);
    }

    /// @notice Adds a new proposal to the list
    /// @dev Internal function to push a new proposal into the map
    /// @param key The key of the proposal
    /// @param proposalType The type of the proposal
    /// @param data The data associated with the proposal
    function _pushProposal(bytes32 key, uint256 proposalType, bytes memory data) internal {
        _proposals.push(key, proposalType, data);
    }
}
