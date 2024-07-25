// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

struct Proposal {
    uint40 submittedAt;
    uint256 proposalType;
    bytes data;
}

/// @title Enumerable Proposals Library
/// @notice Library to manage a set of proposals with enumerable functionality
/// @dev Uses EnumerableSet for managing the proposal keys
library EnumerableProposals {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    error ProposalDoesNotExist(bytes32 key);
    error OffsetOutOfBounds();

    struct Bytes32ToProposalMap {
        bytes32[] _orderedKeys;
        EnumerableSet.Bytes32Set _keys;
        mapping(bytes32 key => Proposal) _proposals;
    }

    /// @notice Adds a new proposal to the map
    /// @dev Adds the proposal if it does not already exist in the map
    /// @param map The map to add the proposal to
    /// @param key The key of the proposal
    /// @param proposalType The type of the proposal
    /// @param data The data associated with the proposal
    /// @return success A boolean indicating if the proposal was added successfully
    function push(
        Bytes32ToProposalMap storage map,
        bytes32 key,
        uint256 proposalType,
        bytes memory data
    ) internal returns (bool) {
        if (!contains(map, key)) {
            Proposal memory proposal = Proposal(uint40(block.timestamp), proposalType, data);
            map._proposals[key] = proposal;
            map._orderedKeys.push(key);
            map._keys.add(key);
            return true;
        }
        return false;
    }

    /// @notice Checks if a proposal exists in the map
    /// @dev Checks if the key is present in the set of keys
    /// @param map The map to check
    /// @param key The key of the proposal
    /// @return exists A boolean indicating if the proposal exists
    function contains(Bytes32ToProposalMap storage map, bytes32 key) internal view returns (bool) {
        return map._keys.contains(key);
    }

    /// @notice Gets the number of proposals in the map
    /// @dev Returns the length of the ordered keys array
    /// @param map The map to check
    /// @return length The number of proposals in the map
    function length(Bytes32ToProposalMap storage map) internal view returns (uint256) {
        return map._orderedKeys.length;
    }

    /// @notice Gets a proposal at a specific index
    /// @dev Returns the proposal at the specified index in the ordered keys array
    /// @param map The map to check
    /// @param index The index to retrieve
    /// @return proposal The proposal at the specified index
    function at(Bytes32ToProposalMap storage map, uint256 index) internal view returns (Proposal memory) {
        bytes32 key = map._orderedKeys[index];
        return map._proposals[key];
    }

    /// @notice Gets a proposal by its key
    /// @dev Returns the proposal associated with the given key, reverts if the proposal does not exist
    /// @param map The map to check
    /// @param key The key of the proposal
    /// @return value The proposal associated with the given key
    function get(Bytes32ToProposalMap storage map, bytes32 key) internal view returns (Proposal memory value) {
        if (!contains(map, key)) {
            revert ProposalDoesNotExist(key);
        }
        value = map._proposals[key];
    }

    /// @notice Gets the ordered keys of the proposals
    /// @dev Returns the array of ordered keys
    /// @param map The map to check
    /// @return keys The ordered keys of the proposals
    function getOrderedKeys(Bytes32ToProposalMap storage map) internal view returns (bytes32[] memory) {
        return map._orderedKeys;
    }

    /// @notice Gets a subset of ordered keys with pagination
    /// @dev Returns a subset of the ordered keys based on the provided offset and limit
    /// @param map The map to check
    /// @param offset The starting index for the subset
    /// @param limit The maximum number of keys to return
    /// @return keys The subset of ordered keys
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
