// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ExecutorCall} from "./ScheduledCalls.sol";

import {Proposer} from "./Proposers.sol";

struct Proposal {
    uint24 id;
    Proposer proposer;
    uint40 proposedAt;
    bool isDecided;
    ExecutorCall[] calls;
}

library Proposals {
    using SafeCast for uint256;
    struct State {
        uint24 proposalsCount;
        // all proposals with ids less or equal than given one cannot be queued
        uint24 lastCanceledProposalId;
        mapping(uint256 id => Proposal proposal) proposals;
    }

    error EmptyCalls();
    error ProposalNotFound(uint256 proposalId);
    error ProposalNotExecutable(uint256 proposalId);

    event Proposed(
        uint256 indexed id,
        address indexed proposer,
        address indexed executor,
        ExecutorCall[] calls
    );
    event ProposalsCanceledTill(uint256 proposalId);

    // the memory is used, because copying from the calldata directly to the store
    // has not implemented by the solidity compiler yet. TODO: check, if copying from
    // the calldata by hand is more gas efficient then calls passed via memory
    function create(
        State storage self,
        Proposer memory proposer,
        ExecutorCall[] memory calls
    ) internal returns (uint256) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        uint24 newProposalId = ++self.proposalsCount;
        Proposal storage newProposal = self.proposals[newProposalId];
        newProposal.id = newProposalId;
        newProposal.proposer = proposer;
        newProposal.proposedAt = block.timestamp.toUint40();
        newProposal.isDecided = false;

        // copying of arrays of custom types from memory to storage has not supported
        // by the Solidity compiler yet, so copy item by item
        for (uint256 i = 0; i < calls.length; ) {
            newProposal.calls.push(calls[i]);
            unchecked {
                ++i;
            }
        }

        emit Proposed(newProposalId, proposer.account, proposer.executor, calls);
        return newProposalId;
    }

    function decide(
        State storage self,
        uint256 proposalId,
        uint256 delay
    ) internal returns (Proposal storage proposal) {
        proposal = load(self, proposalId);
        if (block.timestamp < proposal.proposedAt + delay) {
            revert ProposalNotExecutable(proposalId);
        }
        proposal.isDecided = true;
    }

    function load(
        State storage self,
        uint256 proposalId
    ) internal view returns (Proposal storage proposal) {
        proposal = self.proposals[proposalId];
        if (proposal.id == 0) {
            revert ProposalNotFound(proposalId);
        }
    }

    function cancelAll(State storage self) internal {
        self.lastCanceledProposalId = self.proposalsCount;
        emit ProposalsCanceledTill(self.proposalsCount);
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.proposalsCount;
    }
}
