// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

import {ExternalCall, ExternalCalls, IExternalExecutor} from "./ExternalCalls.sol";

enum Status {
    NotExist,
    Submitted,
    Scheduled,
    Executed
}

library ExecutableProposals {
    using ExternalCalls for ExternalCall[];

    struct Proposal {
        Status status; // 8
        address executor; // 168
        Timestamp submittedAt; // 208
        Timestamp scheduledAt; // 248
    }

    error EmptyCalls();
    error ProposalNotFound(uint256 proposalId);
    error ProposalNotScheduled(uint256 proposalId);
    error ProposalNotSubmitted(uint256 proposalId);
    error AfterSubmitDelayNotPassed(uint256 proposalId);
    error AfterScheduleDelayNotPassed(uint256 proposalId);

    event ProposalSubmitted(uint256 indexed id, ExternalCall[] calls);
    event ProposalScheduled(uint256 indexed id);
    event ProposalExecuted(uint256 indexed id, bytes[] callResults);
    event ProposalsCancelledTill(uint256 proposalId);

    struct State {
        uint64 proposalsCount;
        uint64 lastCancelledProposalId;
        mapping(uint256 proposalId => ExternalCall[]) calls;
        mapping(uint256 proposalId => Proposal) proposals;
    }

    function submit(
        State storage self,
        address executor,
        ExternalCall[] memory calls
    ) internal returns (uint256 newProposalId) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        self.proposalsCount += 1;
        newProposalId = self.proposalsCount;

        self.proposals[newProposalId] = Proposal({
            status: Status.Submitted,
            executor: executor,
            submittedAt: Timestamps.now(),
            scheduledAt: Timestamps.ZERO
        });

        uint256 callsCount = calls.length;
        for (uint256 i = 0; i < callsCount; ++i) {
            self.calls[newProposalId].push(calls[i]);
        }

        emit ProposalSubmitted(newProposalId, calls);
    }

    function schedule(State storage self, uint256 proposalId, Duration afterSubmitDelay) internal {
        Proposal memory proposal = self.proposals[proposalId];

        if (proposal.status != Status.Submitted || isProposalMarkedCancelled(self, proposalId)) {
            revert ProposalNotSubmitted(proposalId);
        }

        if (Timestamps.now() < afterSubmitDelay.addTo(proposal.submittedAt)) {
            revert AfterSubmitDelayNotPassed(proposalId);
        }

        proposal.status = Status.Scheduled;
        proposal.scheduledAt = Timestamps.now();
        self.proposals[proposalId] = proposal;

        emit ProposalScheduled(proposalId);
    }

    function execute(State storage self, uint256 proposalId, Duration afterScheduleDelay) internal {
        Proposal memory proposal = self.proposals[proposalId];

        if (proposal.status != Status.Scheduled || isProposalMarkedCancelled(self, proposalId)) {
            revert ProposalNotScheduled(proposalId);
        }

        if (Timestamps.now() < afterScheduleDelay.addTo(proposal.scheduledAt)) {
            revert AfterScheduleDelayNotPassed(proposalId);
        }

        self.proposals[proposalId].status = Status.Executed;

        bytes[] memory results = self.calls[proposalId].execute(IExternalExecutor(proposal.executor));
        emit ProposalExecuted(proposalId, results);
    }

    function cancelAll(State storage self) internal {
        uint64 lastCancelledProposalId = self.proposalsCount;
        self.lastCancelledProposalId = lastCancelledProposalId;
        emit ProposalsCancelledTill(lastCancelledProposalId);
    }

    // ---
    // Getters
    // ---

    function canExecute(
        State storage self,
        uint256 proposalId,
        Duration afterScheduleDelay
    ) internal view returns (bool) {
        if (isProposalMarkedCancelled(self, proposalId)) return false;
        Proposal memory proposal = self.proposals[proposalId];
        return proposal.status == Status.Scheduled && Timestamps.now() >= afterScheduleDelay.addTo(proposal.scheduledAt);
    }

    function canSchedule(
        State storage self,
        uint256 proposalId,
        Duration afterSubmitDelay
    ) internal view returns (bool) {
        if (isProposalMarkedCancelled(self, proposalId)) return false;
        Proposal memory proposal = self.proposals[proposalId];
        return proposal.status == Status.Submitted && Timestamps.now() >= afterSubmitDelay.addTo(proposal.submittedAt);
    }

    function getProposalsCount(State storage self) internal view returns (uint256) {
        return self.proposalsCount;
    }

    function getProposalInfo(
        State storage self,
        uint256 proposalId
    )
        internal
        view
        returns (Status status, address executor, bool isCancelled, Timestamp submittedAt, Timestamp scheduledAt)
    {
        Proposal memory state = self.proposals[proposalId];
        status = state.status;
        executor = address(state.executor);
        submittedAt = state.submittedAt;
        scheduledAt = state.scheduledAt;
        isCancelled = isProposalMarkedCancelled(self, proposalId) && status != Status.Executed;
    }

    function isProposalMarkedCancelled(State storage self, uint256 proposalId) internal view returns (bool) {
        return proposalId <= self.lastCancelledProposalId;
    }

    function getExternalCalls(
        State storage self,
        uint256 proposalId
    ) internal view returns (ExternalCall[] memory calls) {
        calls = self.calls[proposalId];
    }

    function checkProposalExists(State storage self, uint256 proposalId) internal view {
        if (proposalId == 0 || proposalId > self.proposalsCount) {
            revert ProposalNotFound(proposalId);
        }
    }
}
