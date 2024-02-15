// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ExecutorCall} from "./ScheduledCalls.sol";

struct Proposal {
    uint256 id;
    address proposer;
    address executor;
    uint256 proposedAt;
    uint256 adoptedAt;
    ExecutorCall[] calls;
}

struct ProposalPacked {
    address proposer;
    uint40 proposedAt;
    // Time passed, starting from the proposedAt till the adoption of the proposal
    uint32 adoptionTime;
    address executor;
    ExecutorCall[] calls;
}

library Proposals {
    using SafeCast for uint256;

    // The id of the first proposal
    uint256 private constant FIRST_PROPOSAL_ID = 1;

    struct State {
        // any proposals with ids less or equal to the given one cannot be executed
        uint256 lastCanceledProposalId;
        ProposalPacked[] proposals;
    }

    error EmptyCalls();
    error ProposalCanceled(uint256 proposalId);
    error ProposalNotFound(uint256 proposalId);
    error ProposalAlreadyAdopted(uint256 proposalId, uint256 adoptedAt);
    error ProposalNotExecutable(uint256 proposalId);
    error InvalidAdoptionDelay(uint256 adoptionDelay);

    event Proposed(uint256 indexed id, address indexed proposer, address indexed executor, ExecutorCall[] calls);
    event ProposalsCanceledTill(uint256 proposalId);

    function create(
        State storage self,
        address proposer,
        address executor,
        ExecutorCall[] calldata calls
    ) internal returns (uint256 newProposalId) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        newProposalId = self.proposals.length;
        self.proposals.push();

        ProposalPacked storage newProposal = self.proposals[newProposalId];
        newProposal.proposer = proposer;
        newProposal.executor = executor;
        newProposal.adoptionTime = 0;
        newProposal.proposedAt = block.timestamp.toUint40();

        // copying of arrays of custom types from calldata to storage has not been supported by the
        // Solidity compiler yet, so insert item by item
        for (uint256 i = 0; i < calls.length; ++i) {
            newProposal.calls.push(calls[i]);
        }

        emit Proposed(newProposalId, proposer, executor, calls);
    }

    function cancelAll(State storage self) internal {
        uint256 lastProposalId = self.proposals.length;
        self.lastCanceledProposalId = lastProposalId;
        emit ProposalsCanceledTill(lastProposalId);
    }

    function adopt(State storage self, uint256 proposalId, uint256 delay) internal returns (Proposal memory proposal) {
        ProposalPacked storage packed = _packed(self, proposalId);

        if (proposalId <= self.lastCanceledProposalId) {
            revert ProposalCanceled(proposalId);
        }
        uint256 proposedAt = packed.proposedAt;
        if (packed.adoptionTime != 0) {
            revert ProposalAlreadyAdopted(proposalId, proposedAt + packed.adoptionTime);
        }
        if (block.timestamp < proposedAt + delay) {
            revert ProposalNotExecutable(proposalId);
        }
        uint256 adoptionTime = block.timestamp - proposedAt;
        // the proposal can't be proposed and adopted at the same transaction
        if (adoptionTime == 0) {
            revert InvalidAdoptionDelay(0);
        }
        packed.adoptionTime = adoptionTime.toUint32();
        proposal = _unpack(proposalId, packed);
    }

    function get(State storage self, uint256 proposalId) internal view returns (Proposal memory proposal) {
        proposal = _unpack(proposalId, _packed(self, proposalId));
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.proposals.length;
    }

    function _packed(State storage self, uint256 proposalId) private view returns (ProposalPacked storage packed) {
        if (proposalId < FIRST_PROPOSAL_ID || proposalId > self.proposals.length) {
            revert ProposalNotFound(proposalId);
        }
        packed = self.proposals[proposalId - FIRST_PROPOSAL_ID];
    }

    function _unpack(uint256 id, ProposalPacked memory packed) private pure returns (Proposal memory proposal) {
        proposal.id = id;
        proposal.calls = packed.calls;
        proposal.proposer = packed.proposer;
        proposal.executor = packed.executor;
        proposal.proposedAt = packed.proposedAt;
        proposal.adoptedAt = packed.adoptionTime == 0 ? 0 : proposal.proposedAt + packed.adoptionTime;
    }
}
