// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

struct Proposal {
    uint40 submittedAt;
    uint256 proposalType;
    bytes data;
}

library EnumerableProposals {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    error ProposalDoesNotExist(bytes32 key);
    error OffsetOutOfBounds();

    struct Bytes32ToProposalMap {
        bytes32[] _orderedKeys;
        EnumerableSet.Bytes32Set _keys;
        mapping(bytes32 key => Proposal) _proposals;
    }

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

    function contains(Bytes32ToProposalMap storage map, bytes32 key) internal view returns (bool) {
        return map._keys.contains(key);
    }

    function length(Bytes32ToProposalMap storage map) internal view returns (uint256) {
        return map._orderedKeys.length;
    }

    function at(Bytes32ToProposalMap storage map, uint256 index) internal view returns (Proposal memory) {
        bytes32 key = map._orderedKeys[index];
        return map._proposals[key];
    }

    function get(Bytes32ToProposalMap storage map, bytes32 key) internal view returns (Proposal memory value) {
        if (!contains(map, key)) {
            revert ProposalDoesNotExist(key);
        }
        value = map._proposals[key];
    }

    function orederedKeys(Bytes32ToProposalMap storage map) internal view returns (bytes32[] memory) {
        return map._orderedKeys;
    }

    function orederedKeys(
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
