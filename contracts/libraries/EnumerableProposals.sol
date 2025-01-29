// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

/// @notice Data structure representing a proposal.
/// @param submittedAt The timestamp when the proposal was submitted.
/// @param proposalType The type identifier for the proposal.
/// @param data The additional data associated with the proposal.
struct Proposal {
    Timestamp submittedAt;
    uint256 proposalType;
    bytes data;
}

/// @title Enumerable Proposals Library
/// @notice Library to manage a set of proposals with enumerable functionality.
/// @dev Uses EnumerableSet for managing the proposal keys.
library EnumerableProposals {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // ---
    // Errors
    // ---

    error ProposalDoesNotExist(bytes32 key);
    error OffsetOutOfBounds();

    // ---
    // Data Types
    // ---

    /// @notice Data structure to manage the state of the library.
    /// @dev Uses `EnumerableSet.Bytes32Set` to manage unique keys efficiently.
    /// @param _orderedKeys Array of proposal keys in the order of insertion.
    /// @param _keys Set of unique proposal keys for existence checks.
    /// @param _proposals Mapping of proposal keys to Proposal data.
    struct Bytes32ToProposalMap {
        bytes32[] _orderedKeys;
        EnumerableSet.Bytes32Set _keys;
        mapping(bytes32 key => Proposal) _proposals;
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Adds a new proposal to the map.
    /// @dev Adds the proposal if it does not already exist in the map.
    /// @param map The map to add the proposal to.
    /// @param key The key of the proposal.
    /// @param proposalType The type of the proposal.
    /// @param data The data associated with the proposal.
    /// @return success A boolean indicating if the proposal was added successfully.
    function push(
        Bytes32ToProposalMap storage map,
        bytes32 key,
        uint256 proposalType,
        bytes memory data
    ) internal returns (bool) {
        if (map._keys.add(key)) {
            Proposal memory proposal = Proposal(Timestamps.now(), proposalType, data);
            map._proposals[key] = proposal;
            map._orderedKeys.push(key);
            return true;
        }
        return false;
    }

    /// @notice Checks if a proposal with the specified key exists in the map.
    /// @param map The map to check.
    /// @param key The key of the proposal.
    /// @return exists A boolean indicating if the proposal exists.
    function contains(Bytes32ToProposalMap storage map, bytes32 key) internal view returns (bool) {
        return map._keys.contains(key);
    }

    /// @notice Retrieves the number of proposals in the map.
    /// @param map The map to check.
    /// @return length The number of proposals in the map.
    function length(Bytes32ToProposalMap storage map) internal view returns (uint256) {
        return map._orderedKeys.length;
    }

    /// @notice Retrieves a proposal at a specified index.
    /// @param map The map to check.
    /// @param index The index to retrieve.
    /// @return proposal The proposal at the specified index.
    function at(Bytes32ToProposalMap storage map, uint256 index) internal view returns (Proposal memory) {
        bytes32 key = map._orderedKeys[index];
        return map._proposals[key];
    }

    /// @notice Retrieves a proposal by its unique key.
    /// @param map The map to check.
    /// @param key The key of the proposal.
    /// @return value The proposal associated with the given key.
    function get(Bytes32ToProposalMap storage map, bytes32 key) internal view returns (Proposal memory value) {
        if (!contains(map, key)) {
            revert ProposalDoesNotExist(key);
        }
        value = map._proposals[key];
    }

    /// @notice Retrieves all proposal keys in the order they were added.
    /// @param map The map to check.
    /// @return keys An array of ordered proposal keys.
    function getOrderedKeys(Bytes32ToProposalMap storage map) internal view returns (bytes32[] memory) {
        return map._orderedKeys;
    }

    /// @notice Retrieves a subset of proposal keys using pagination.
    /// @dev Returns a subset of keys based on the provided offset and limit for pagination.
    /// @param map The map to check.
    /// @param offset The starting index for the subset.
    /// @param limit The maximum number of keys to return.
    /// @return keys An array of ordered keys within the specified range.
    function getOrderedKeys(
        Bytes32ToProposalMap storage map,
        uint256 offset,
        uint256 limit
    ) internal view returns (bytes32[] memory keys) {
        if (offset >= map._orderedKeys.length) {
            revert OffsetOutOfBounds();
        }

        uint256 keysLength = limit;
        if (keysLength > map._orderedKeys.length - offset) {
            keysLength = map._orderedKeys.length - offset;
        }

        keys = new bytes32[](keysLength);
        for (uint256 i = 0; i < keysLength; ++i) {
            keys[i] = map._orderedKeys[offset + i];
        }
    }
}
