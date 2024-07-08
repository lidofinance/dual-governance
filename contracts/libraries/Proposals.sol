// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

import {IExecutor, ExecutorCall} from "../interfaces/IExecutor.sol";

enum Status {
    NotExist,
    Submitted,
    Scheduled,
    Executed,
    Cancelled
}

struct Proposal {
    uint256 id;
    Status status;
    address executor;
    Timestamp submittedAt;
    Timestamp scheduledAt;
    Timestamp executedAt;
    ExecutorCall[] calls;
}

library Proposals {
    struct ProposalPacked {
        address executor;
        Timestamp submittedAt;
        Timestamp scheduledAt;
        Timestamp executedAt;
        ExecutorCall[] calls;
    }

    struct State {
        // any proposals with ids less or equal to the given one cannot be executed
        uint256 lastCancelledProposalId;
        ProposalPacked[] proposals;
    }

    error EmptyCalls();
    error ProposalCancelled(uint256 proposalId);
    error ProposalNotFound(uint256 proposalId);
    error ProposalNotScheduled(uint256 proposalId);
    error ProposalNotSubmitted(uint256 proposalId);
    error AfterSubmitDelayNotPassed(uint256 proposalId);
    error AfterScheduleDelayNotPassed(uint256 proposalId);

    event ProposalScheduled(uint256 indexed id);
    event ProposalSubmitted(uint256 indexed id, address indexed executor, ExecutorCall[] calls);
    event ProposalExecuted(uint256 indexed id, bytes[] callResults);
    event ProposalsCancelledTill(uint256 proposalId);

    // The id of the first proposal
    uint256 private constant PROPOSAL_ID_OFFSET = 1;

    function submit(
        State storage self,
        address executor,
        ExecutorCall[] memory calls
    ) internal returns (uint256 newProposalId) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        uint256 newProposalIndex = self.proposals.length;

        self.proposals.push();
        ProposalPacked storage newProposal = self.proposals[newProposalIndex];

        newProposal.executor = executor;
        newProposal.submittedAt = Timestamps.now();

        // copying of arrays of custom types from calldata to storage has not been supported by the
        // Solidity compiler yet, so insert item by item
        for (uint256 i = 0; i < calls.length; ++i) {
            newProposal.calls.push(calls[i]);
        }

        newProposalId = newProposalIndex + PROPOSAL_ID_OFFSET;
        emit ProposalSubmitted(newProposalId, executor, calls);
    }

    function schedule(State storage self, uint256 proposalId, Duration afterSubmitDelay) internal {
        _checkProposalSubmitted(self, proposalId);
        _checkAfterSubmitDelayPassed(self, proposalId, afterSubmitDelay);

        ProposalPacked storage proposal = _packed(self, proposalId);
        proposal.scheduledAt = Timestamps.now();

        emit ProposalScheduled(proposalId);
    }

    function execute(State storage self, uint256 proposalId, Duration afterScheduleDelay) internal {
        _checkProposalScheduled(self, proposalId);
        _checkAfterScheduleDelayPassed(self, proposalId, afterScheduleDelay);
        _executeProposal(self, proposalId);
    }

    function cancelAll(State storage self) internal {
        uint256 lastProposalId = self.proposals.length;
        self.lastCancelledProposalId = lastProposalId;
        emit ProposalsCancelledTill(lastProposalId);
    }

    function get(State storage self, uint256 proposalId) internal view returns (Proposal memory proposal) {
        _checkProposalExists(self, proposalId);
        ProposalPacked storage packed = _packed(self, proposalId);

        proposal.id = proposalId;
        proposal.status = _getProposalStatus(self, proposalId);
        proposal.executor = packed.executor;
        proposal.submittedAt = packed.submittedAt;
        proposal.scheduledAt = packed.scheduledAt;
        proposal.executedAt = packed.executedAt;
        proposal.calls = packed.calls;
    }

    function getProposalSubmissionTime(
        State storage self,
        uint256 proposalId
    ) internal view returns (Timestamp submittedAt) {
        _checkProposalExists(self, proposalId);
        submittedAt = _packed(self, proposalId).submittedAt;
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.proposals.length;
    }

    function canExecute(
        State storage self,
        uint256 proposalId,
        Duration afterScheduleDelay
    ) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == Status.Scheduled
            && Timestamps.now() >= afterScheduleDelay.addTo(_packed(self, proposalId).scheduledAt);
    }

    function canSchedule(
        State storage self,
        uint256 proposalId,
        Duration afterSubmitDelay
    ) internal view returns (bool) {
        return _getProposalStatus(self, proposalId) == Status.Submitted
            && Timestamps.now() >= afterSubmitDelay.addTo(_packed(self, proposalId).submittedAt);
    }

    function _executeProposal(State storage self, uint256 proposalId) private {
        ProposalPacked storage packed = _packed(self, proposalId);
        packed.executedAt = Timestamps.now();

        ExecutorCall[] memory calls = packed.calls;
        uint256 callsCount = calls.length;

        assert(callsCount > 0);

        address executor = packed.executor;
        bytes[] memory results = new bytes[](callsCount);
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

    function _checkProposalSubmitted(State storage self, uint256 proposalId) private view {
        Status status = _getProposalStatus(self, proposalId);
        if (status != Status.Submitted) {
            revert ProposalNotSubmitted(proposalId);
        }
    }

    function _checkProposalScheduled(State storage self, uint256 proposalId) private view {
        Status status = _getProposalStatus(self, proposalId);
        if (status != Status.Scheduled) {
            revert ProposalNotScheduled(proposalId);
        }
    }

    function _checkAfterSubmitDelayPassed(
        State storage self,
        uint256 proposalId,
        Duration afterSubmitDelay
    ) private view {
        if (Timestamps.now() < afterSubmitDelay.addTo(_packed(self, proposalId).submittedAt)) {
            revert AfterSubmitDelayNotPassed(proposalId);
        }
    }

    function _checkAfterScheduleDelayPassed(
        State storage self,
        uint256 proposalId,
        Duration afterScheduleDelay
    ) private view {
        if (Timestamps.now() < afterScheduleDelay.addTo(_packed(self, proposalId).scheduledAt)) {
            revert AfterScheduleDelayNotPassed(proposalId);
        }
    }

    function _getProposalStatus(State storage self, uint256 proposalId) private view returns (Status status) {
        if (proposalId < PROPOSAL_ID_OFFSET || proposalId > self.proposals.length) return Status.NotExist;

        ProposalPacked storage packed = _packed(self, proposalId);

        if (packed.executedAt.isNotZero()) return Status.Executed;
        if (proposalId <= self.lastCancelledProposalId) return Status.Cancelled;
        if (packed.scheduledAt.isNotZero()) return Status.Scheduled;
        if (packed.submittedAt.isNotZero()) return Status.Submitted;
        assert(false);
    }
}
