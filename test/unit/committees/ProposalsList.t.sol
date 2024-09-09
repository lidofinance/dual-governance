// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ProposalsList} from "contracts/committees/ProposalsList.sol";
import {Proposal} from "contracts/libraries/EnumerableProposals.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract ProposalsListUnitTest is UnitTest, ProposalsList {
    ProposalsListWrapper internal proposalsList;

    bytes32 internal proposalKey1 = keccak256(abi.encodePacked("proposal1"));
    bytes32 internal proposalKey2 = keccak256(abi.encodePacked("proposal2"));
    bytes32 internal proposalKey3 = keccak256(abi.encodePacked("proposal3"));
    uint256 internal proposalType1 = 1;
    uint256 internal proposalType2 = 2;
    bytes internal proposalData1 = abi.encodePacked("data1");
    bytes internal proposalData2 = abi.encodePacked("data2");
    bytes internal proposalData3 = abi.encodePacked("data3");

    function setUp() public {
        proposalsList = new ProposalsListWrapper();

        proposalsList.pushProposal(proposalKey1, proposalType1, proposalData1);
        proposalsList.pushProposal(proposalKey2, proposalType2, proposalData2);
        proposalsList.pushProposal(proposalKey3, proposalType1, proposalData3);
    }

    function test_getProposalsLength_HappyPath() external {
        uint256 length = proposalsList.getProposalsLength();
        assertEq(length, 3);
    }

    function test_getProposal_HappyPath() external {
        Proposal memory proposal = proposalsList.getProposal(proposalKey1);
        assertEq(proposal.proposalType, proposalType1);
        assertEq(proposal.data, proposalData1);
    }

    function test_getProposals_HappyPath() external {
        Proposal[] memory proposals = proposalsList.getProposals(0, 2);
        assertEq(proposals.length, 2);
        assertEq(proposals[0].proposalType, proposalType1);
        assertEq(proposals[0].data, proposalData1);
        assertEq(proposals[1].proposalType, proposalType2);
        assertEq(proposals[1].data, proposalData2);
    }

    function test_getProposalAt_HappyPath() external {
        Proposal memory proposal = proposalsList.getProposalAt(1);
        assertEq(proposal.proposalType, proposalType2);
        assertEq(proposal.data, proposalData2);
    }

    function test_getOrderedKeys_HappyPath() external {
        bytes32[] memory keys = proposalsList.getOrderedKeys(0, 3);
        assertEq(keys.length, 3);
        assertEq(keys[0], proposalKey1);
        assertEq(keys[1], proposalKey2);
        assertEq(keys[2], proposalKey3);
    }

    function test_getProposals_Pagination() external {
        Proposal[] memory proposals = proposalsList.getProposals(1, 2);
        assertEq(proposals.length, 2);
        assertEq(proposals[0].proposalType, proposalType2);
        assertEq(proposals[0].data, proposalData2);
        assertEq(proposals[1].proposalType, proposalType1);
        assertEq(proposals[1].data, proposalData3);
    }

    function test_pushProposal_HappyPath() external {
        bytes32 proposalKey4 = keccak256(abi.encodePacked("proposal4"));
        uint256 proposalType4 = 4;
        bytes memory proposalData4 = abi.encodePacked("data4");

        proposalsList.pushProposal(proposalKey4, proposalType4, proposalData4);

        Proposal memory proposal = proposalsList.getProposal(proposalKey4);
        assertEq(proposal.proposalType, proposalType4);
        assertEq(proposal.data, proposalData4);
    }
}

contract ProposalsListWrapper is ProposalsList {
    function pushProposal(bytes32 key, uint256 proposalType, bytes memory data) public {
        _pushProposal(key, proposalType, data);
    }
}
