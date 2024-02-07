// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ExecutorCall, ExecutorCallPacked} from "./ScheduledCalls.sol";

import {Proposer} from "./Proposers.sol";

struct Proposal {
    uint256 id;
    address proposer;
    address executor;
    uint256 proposedAt;
    uint256 adoptedAt;
    ExecutorCall[] calls;
}

struct ProposalPacked {
    uint24 id;
    address proposer;
    uint40 proposedAt;
    // time passed, starting from proposedAt to adopting the proposal
    uint32 adoptionTime;
    address executor;
    ExecutorCallPacked[] calls;
}

library Proposals {
    using SafeCast for uint256;
    struct State {
        uint24 proposalsCount;
        // all proposals with ids less or equal than given one cannot be queued
        uint24 lastCanceledProposalId;
        mapping(uint256 id => ProposalPacked proposal) proposals;
    }

    error EmptyCalls();
    error ProposalNotFound(uint256 proposalId);
    error ProposalNotExecutable(uint256 proposalId);
    error InvalidAdoptionDelay(uint256 adoptionDelay);

    event Proposed(
        uint256 indexed id,
        address indexed proposer,
        address indexed executor,
        ExecutorCall[] calls
    );
    event ProposalsCanceledTill(uint256 proposalId);

    function create(
        State storage self,
        address proposer,
        address executor,
        ExecutorCall[] calldata calls
    ) internal returns (uint256) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        uint24 newProposalId = ++self.proposalsCount;
        ProposalPacked storage newProposal = self.proposals[newProposalId];
        newProposal.id = newProposalId;
        newProposal.proposer = proposer;
        newProposal.executor = executor;
        newProposal.proposedAt = block.timestamp.toUint40();
        newProposal.adoptionTime = 0;

        // copying of arrays of custom types from memory to storage has not supported
        // by the Solidity compiler yet, so copy item by item
        for (uint256 i = 0; i < calls.length; ) {
            newProposal.calls.push(
                ExecutorCallPacked({
                    target: calls[i].target,
                    value: calls[i].value.toUint96(),
                    payload: calls[i].payload
                })
            );
            unchecked {
                ++i;
            }
        }

        emit Proposed(newProposalId, proposer, executor, calls);
        return newProposalId;
    }

    function cancelAll(State storage self) internal {
        self.lastCanceledProposalId = self.proposalsCount;
        emit ProposalsCanceledTill(self.proposalsCount);
    }

    function adopt(
        State storage self,
        uint256 proposalId,
        uint256 delay
    ) internal returns (Proposal memory proposal) {
        ProposalPacked storage packed = _packed(self, proposalId);
        if (block.timestamp < packed.proposedAt + delay) {
            revert ProposalNotExecutable(proposalId);
        }
        uint256 adoptionDelay = block.timestamp - packed.proposedAt;
        if (adoptionDelay == 0) {
            revert InvalidAdoptionDelay(0);
        }
        packed.adoptionTime = adoptionDelay.toUint32();
        proposal = _unpack(packed);
    }

    function get(
        State storage self,
        uint256 proposalId
    ) internal view returns (Proposal memory proposal) {
        proposal = _unpack(_packed(self, proposalId));
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.proposalsCount;
    }

    function _packed(
        State storage self,
        uint256 proposalId
    ) private view returns (ProposalPacked storage packed) {
        packed = self.proposals[proposalId];
        if (packed.id == 0) {
            revert ProposalNotFound(proposalId);
        }
    }

    function _unpack(
        ProposalPacked storage packed
    ) private view returns (Proposal memory proposal) {
        proposal.id = packed.id;
        proposal.proposer = packed.proposer;
        proposal.executor = packed.executor;
        proposal.proposedAt = packed.proposedAt;
        proposal.adoptedAt = packed.adoptionTime == 0
            ? 0
            : proposal.proposedAt + packed.adoptionTime;

        uint256 callsCount = packed.calls.length;
        proposal.calls = new ExecutorCall[](callsCount);
        for (uint256 i = 0; i < callsCount; ) {
            proposal.calls[i].target = packed.calls[i].target;
            proposal.calls[i].value = packed.calls[i].value;
            proposal.calls[i].payload = packed.calls[i].payload;
            unchecked {
                ++i;
            }
        }
    }
}
