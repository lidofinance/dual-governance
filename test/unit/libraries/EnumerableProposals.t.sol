// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableProposals} from "contracts/libraries/EnumerableProposals.sol";
import {Proposal} from "contracts/libraries/EnumerableProposals.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract EnumerableProposalsTest is UnitTest {
    using EnumerableProposals for EnumerableProposals.Bytes32ToProposalMap;

    EnumerableProposals.Bytes32ToProposalMap private proposalsMap;

    bytes32 private constant TEST_KEY_1 = keccak256("TEST_KEY_1");
    bytes32 private constant TEST_KEY_2 = keccak256("TEST_KEY_2");
    uint256 private constant TEST_PROPOSAL_TYPE = 1;
    bytes private constant TEST_DATA = "test data";

    function test_pushAddsProposal() public {
        bool success = proposalsMap.push(TEST_KEY_1, TEST_PROPOSAL_TYPE, TEST_DATA);
        assertTrue(success);
        assertEq(proposalsMap.length(), 1);
    }

    function test_pushDoesNotAddDuplicateProposal() public {
        proposalsMap.push(TEST_KEY_1, TEST_PROPOSAL_TYPE, TEST_DATA);
        bool success = proposalsMap.push(TEST_KEY_1, TEST_PROPOSAL_TYPE, TEST_DATA);
        assertFalse(success);
        assertEq(proposalsMap.length(), 1);
    }

    function test_containsReturnsTrueForExistingProposal() public {
        proposalsMap.push(TEST_KEY_1, TEST_PROPOSAL_TYPE, TEST_DATA);
        bool exists = proposalsMap.contains(TEST_KEY_1);
        assertTrue(exists);
    }

    function test_containsReturnsFalseForNonExistingProposal() public view {
        bool exists = proposalsMap.contains(TEST_KEY_1);
        assertFalse(exists);
    }

    function test_getReturnsCorrectProposal() public {
        proposalsMap.push(TEST_KEY_1, TEST_PROPOSAL_TYPE, TEST_DATA);
        Proposal memory proposal = proposalsMap.get(TEST_KEY_1);
        assertEq(proposal.proposalType, TEST_PROPOSAL_TYPE);
        assertEq(proposal.data, TEST_DATA);
    }

    function test_getRevertsForNonExistingProposal() public {
        vm.expectRevert(abi.encodeWithSelector(EnumerableProposals.ProposalDoesNotExist.selector, TEST_KEY_1));
        this.external__get(TEST_KEY_1);
    }

    function test_atReturnsCorrectProposal() public {
        proposalsMap.push(TEST_KEY_1, TEST_PROPOSAL_TYPE, TEST_DATA);
        Proposal memory proposal = proposalsMap.at(0);
        assertEq(proposal.proposalType, TEST_PROPOSAL_TYPE);
        assertEq(proposal.data, TEST_DATA);
    }

    function test_atRevertsForOutOfBoundsIndex() public {
        vm.expectRevert();
        this.external__at(0);
    }

    function test_getOrderedKeysReturnsAllKeys() public {
        proposalsMap.push(TEST_KEY_1, TEST_PROPOSAL_TYPE, TEST_DATA);
        proposalsMap.push(TEST_KEY_2, TEST_PROPOSAL_TYPE, TEST_DATA);
        bytes32[] memory keys = proposalsMap.getOrderedKeys();
        assertEq(keys.length, 2);
        assertEq(keys[0], TEST_KEY_1);
        assertEq(keys[1], TEST_KEY_2);
    }

    function test_getOrderedKeysWithPagination() public {
        proposalsMap.push(TEST_KEY_1, TEST_PROPOSAL_TYPE, TEST_DATA);
        proposalsMap.push(TEST_KEY_2, TEST_PROPOSAL_TYPE, TEST_DATA);
        bytes32[] memory keys = proposalsMap.getOrderedKeys(0, 1);
        assertEq(keys.length, 1);
        assertEq(keys[0], TEST_KEY_1);
    }

    function test_getOrderedKeysWithPaginationRevertsForInvalidOffset() public {
        vm.expectRevert(EnumerableProposals.OffsetOutOfBounds.selector);
        this.external__getOrderedKeys(2, 1);
    }

    function test_getOrderedKeysWithLimitExceedingRemainingKeys() public {
        proposalsMap.push(TEST_KEY_1, TEST_PROPOSAL_TYPE, TEST_DATA);
        proposalsMap.push(TEST_KEY_2, TEST_PROPOSAL_TYPE, TEST_DATA);

        bytes32[] memory keys = proposalsMap.getOrderedKeys(1, 5);

        assertEq(keys.length, 1);
        assertEq(keys[0], TEST_KEY_2);
    }

    function external__get(bytes32 key) external view {
        proposalsMap.get(key);
    }

    function external__at(uint256 index) external view {
        proposalsMap.at(index);
    }

    function external__getOrderedKeys(uint256 offset, uint256 limit) external view {
        proposalsMap.getOrderedKeys(offset, limit);
    }
}
