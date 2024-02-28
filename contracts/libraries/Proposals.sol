// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IExecutor, ExecutorCall} from "../interfaces/IExecutor.sol";
import {timestamp} from "../utils/time.sol";

enum ProposalStatus {
    NotExist,
    Submitted,
    Scheduled,
    Executed,
    Canceled
}

struct Proposal {
    uint256 id;
    ProposalStatus status;
    address proposer;
    address executor;
    uint256 proposedAt;
    uint256 scheduledAt;
    uint256 executedAt;
    ExecutorCall[] calls;
    // TODO: remove unused fields
    uint256 adoptedAt;
}

library Proposals {
    struct ProposalPacked {
        uint40 proposedAt;
        uint40 scheduledAt;
        uint40 executedAt;
        address executor;
        ExecutorCall[] calls;
    }

    struct State {
        uint40 afterProposeDelay;
        uint40 afterScheduleDelay;
        // any proposals with ids less or equal to the given one cannot be executed
        uint256 lastCanceledProposalId;
        ProposalPacked[] proposals;
    }

    error EmptyCalls();
    error ProposalCanceled(uint256 proposalId);
    error ProposalNotFound(uint256 proposalId);
    error ProposalNotExecutable(uint256 proposalId);
    error ProposalNotScheduled(uint256 proposalId);
    error ProposalAlreadyExecuted(uint256 proposalId);
    error ProposalAlreadyScheduled(uint256 proposalId);
    error InvalidAdoptionDelay(uint256 adoptionDelay);
    error InvalidProposalStatus(ProposalStatus actual, ProposalStatus expected);

    event ProposalSubmitted(uint256 indexed id, address indexed executor, ExecutorCall[] calls);
    event ProposalExecuted(uint256 indexed id, bytes[] callResults);
    event ProposalsCanceledTill(uint256 proposalId);
    event ProposalScheduled(uint256 indexed id);
    event AfterProposeDelaySet(uint256 afterProposeDelay);
    event AfterScheduleDelaySet(uint256 afterScheduleDelay);

    // The id of the first proposal

    uint256 private constant PROPOSAL_ID_OFFSET = 1;

    function create(
        State storage self,
        address proposer,
        address executor,
        ExecutorCall[] calldata calls
    ) internal returns (uint256 newProposalId) {}

    function adopt(State storage self, uint256 id, uint256 delay) internal returns (Proposal memory) {}

    function submit(
        State storage self,
        address executor,
        ExecutorCall[] calldata calls
    ) internal returns (uint256 newProposalId) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        uint256 newProposalIndex = self.proposals.length;

        self.proposals.push();
        ProposalPacked storage newProposal = self.proposals[newProposalIndex];
        newProposal.executor = executor;

        newProposal.executedAt = 0;
        newProposal.scheduledAt = 0;
        newProposal.proposedAt = timestamp();

        // copying of arrays of custom types from calldata to storage has not been supported by the
        // Solidity compiler yet, so insert item by item
        for (uint256 i = 0; i < calls.length; ++i) {
            newProposal.calls.push(calls[i]);
        }

        newProposalId = newProposalIndex + PROPOSAL_ID_OFFSET;
        emit ProposalSubmitted(newProposalId, executor, calls);
    }

    function schedule(State storage self, uint256 proposalId) internal {
        _checkProposalExists(self, proposalId);
        _checkProposalStatus(self, proposalId, ProposalStatus.Submitted);
        _checkAfterProposeDelayPassed(self, proposalId);
        _packed(self, proposalId).scheduledAt = timestamp();
        emit ProposalScheduled(proposalId);
    }

    function executeScheduled(State storage self, uint256 proposalId) internal {
        _checkProposalExists(self, proposalId);
        _checkProposalStatus(self, proposalId, ProposalStatus.Scheduled);
        _checkAfterScheduleDelayPassed(self, proposalId);
        _executeProposal(self, proposalId);
    }

    function executeSubmitted(State storage self, uint256 proposalId) internal {
        _checkProposalExists(self, proposalId);
        _checkProposalStatus(self, proposalId, ProposalStatus.Submitted);
        _checkAfterProposeDelayPassed(self, proposalId);
        _executeProposal(self, proposalId);
    }

    function cancelAll(State storage self) internal {
        uint256 lastProposalId = self.proposals.length;
        self.lastCanceledProposalId = lastProposalId;
        emit ProposalsCanceledTill(lastProposalId);
    }

    function setDelays(State storage self, uint256 afterProposeDelay, uint256 afterScheduleDelay) internal {
        uint256 currentAfterProposeDelay = self.afterProposeDelay;
        if (currentAfterProposeDelay != afterProposeDelay) {
            self.afterProposeDelay = timestamp(afterProposeDelay);
            emit AfterProposeDelaySet(afterProposeDelay);
        }

        uint256 currentAfterScheduleDelay = self.afterScheduleDelay;
        if (currentAfterScheduleDelay != afterScheduleDelay) {
            self.afterScheduleDelay = timestamp(afterScheduleDelay);
            emit AfterScheduleDelaySet(afterScheduleDelay);
        }
    }

    function get(State storage self, uint256 proposalId) internal view returns (Proposal memory proposal) {
        _checkProposalExists(self, proposalId);
        ProposalPacked storage packed = _packed(self, proposalId);

        proposal.id = proposalId;
        proposal.status = _getProposalStatus(self, proposalId);
        proposal.executor = packed.executor;
        proposal.proposedAt = packed.proposedAt;
        proposal.scheduledAt = packed.scheduledAt;
        proposal.executedAt = packed.executedAt;
        proposal.calls = packed.calls;
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.proposals.length;
    }

    function canScheduleOrExecuteSubmitted(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Submitted
            && block.timestamp > _packed(self, proposalId).proposedAt + self.afterProposeDelay;
    }

    function canExecuteScheduled(State storage self, uint256 proposalId) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == ProposalStatus.Scheduled
            && block.timestamp > _packed(self, proposalId).scheduledAt + self.afterScheduleDelay;
    }

    function _executeProposal(State storage self, uint256 proposalId) private returns (bytes[] memory results) {
        ProposalPacked storage packed = _packed(self, proposalId);
        packed.executedAt = timestamp();

        ExecutorCall[] memory calls = packed.calls;
        uint256 callsCount = calls.length;

        assert(callsCount > 0);

        address executor = packed.executor;
        results = new bytes[](callsCount);
        for (uint256 i = 0; i < callsCount; ++i) {
            results[i] = IExecutor(payable(executor)).execute(calls[i].target, calls[i].value, calls[i].payload);
        }
        emit ProposalExecuted(proposalId, results);
    }

    function _packed(State storage self, uint256 proposalId) private view returns (ProposalPacked storage packed) {
        packed = self.proposals[proposalId - PROPOSAL_ID_OFFSET];
    }

    function _checkProposalExists(State storage self, uint256 proposalId) private view {
        if (proposalId < PROPOSAL_ID_OFFSET || proposalId > self.proposals.length) {
            revert ProposalNotFound(proposalId);
        }
    }

    function _checkAfterProposeDelayPassed(State storage self, uint256 proposalId) private view {
        uint256 proposedAt = _packed(self, proposalId).proposedAt;
        if (block.timestamp < proposedAt + self.afterProposeDelay) {
            revert ProposalNotExecutable(proposalId);
        }
    }

    function _checkAfterScheduleDelayPassed(State storage self, uint256 proposalId) private view {
        uint256 scheduledAt = _packed(self, proposalId).scheduledAt;
        if (block.timestamp < scheduledAt + self.afterScheduleDelay) {
            revert ProposalNotExecutable(proposalId);
        }
    }

    function _checkProposalStatus(State storage self, uint256 proposalId, ProposalStatus expected) private view {
        ProposalStatus actual = _getProposalStatus(self, proposalId);
        if (actual != expected) {
            revert InvalidProposalStatus(actual, expected);
        }
    }

    function _getProposalStatus(State storage self, uint256 proposalId) private view returns (ProposalStatus) {
        if (proposalId < PROPOSAL_ID_OFFSET || proposalId > self.proposals.length) {
            return ProposalStatus.NotExist;
        } else if (proposalId <= self.lastCanceledProposalId) {
            return ProposalStatus.Canceled;
        }
        ProposalPacked storage packed = self.proposals[proposalId - PROPOSAL_ID_OFFSET];

        if (packed.executedAt != 0) {
            return ProposalStatus.Executed;
        } else if (packed.scheduledAt != 0) {
            return ProposalStatus.Scheduled;
        } else if (packed.proposedAt != 0) {
            return ProposalStatus.Submitted;
        }
        assert(false);
    }
}
