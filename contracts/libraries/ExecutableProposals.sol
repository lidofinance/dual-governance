// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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

    struct ProposalState {
        Status status;
        address executor;
        Timestamp submittedAt;
        Timestamp scheduledAt;
    }

    struct Proposal {
        ProposalState state;
        ExternalCall[] calls;
    }

    error EmptyCalls();
    error ProposalNotFound(uint256 proposalId);
    error ProposalNotScheduled(uint256 proposalId);
    error ProposalNotSubmitted(uint256 proposalId);
    error AfterSubmitDelayNotPassed(uint256 proposalId);
    error AfterScheduleDelayNotPassed(uint256 proposalId);

    event ProposalSubmitted(uint256 indexed id, address indexed executor, ExternalCall[] calls);
    event ProposalScheduled(uint256 indexed id);
    event ProposalExecuted(uint256 indexed id, bytes[] callResults);
    event ProposalsCancelledTill(uint256 proposalId);

    struct State {
        uint64 proposalsCount;
        uint64 lastCancelledProposalId;
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
        /// @dev: proposal ids are one-based. The first item has id = 1
        newProposalId = ++self.proposalsCount;
        Proposal storage newProposal = self.proposals[newProposalId];

        newProposal.state.executor = executor;
        newProposal.state.status = Status.Submitted;
        newProposal.state.submittedAt = Timestamps.now();

        uint256 callsCount = calls.length;
        for (uint256 i = 0; i < callsCount; ++i) {
            newProposal.calls.push(calls[i]);
        }

        emit ProposalSubmitted(newProposalId, executor, calls);
    }

    function schedule(State storage self, uint256 proposalId, Duration afterSubmitDelay) internal {
        ProposalState memory proposalState = self.proposals[proposalId].state;

        if (proposalState.status != Status.Submitted || isProposalMarkedCancelled(self, proposalId)) {
            revert ProposalNotSubmitted(proposalId);
        }

        if (Timestamps.now() < afterSubmitDelay.addTo(proposalState.submittedAt)) {
            revert AfterSubmitDelayNotPassed(proposalId);
        }

        proposalState.status = Status.Scheduled;
        proposalState.scheduledAt = Timestamps.now();
        self.proposals[proposalId].state = proposalState;

        emit ProposalScheduled(proposalId);
    }

    function execute(State storage self, uint256 proposalId, Duration afterScheduleDelay) internal {
        Proposal memory proposal = self.proposals[proposalId];

        if (proposal.state.status != Status.Scheduled || isProposalMarkedCancelled(self, proposalId)) {
            revert ProposalNotScheduled(proposalId);
        }

        if (Timestamps.now() < afterScheduleDelay.addTo(proposal.state.scheduledAt)) {
            revert AfterScheduleDelayNotPassed(proposalId);
        }

        self.proposals[proposalId].state.status = Status.Executed;

        bytes[] memory results = proposal.calls.execute(IExternalExecutor(proposal.state.executor));
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
        ProposalState memory proposalState = self.proposals[proposalId].state;
        return proposalState.status == Status.Scheduled
            && Timestamps.now() >= afterScheduleDelay.addTo(proposalState.scheduledAt);
    }

    function canSchedule(
        State storage self,
        uint256 proposalId,
        Duration afterSubmitDelay
    ) internal view returns (bool) {
        if (isProposalMarkedCancelled(self, proposalId)) return false;
        ProposalState memory proposalState = self.proposals[proposalId].state;
        return proposalState.status == Status.Submitted
            && Timestamps.now() >= afterSubmitDelay.addTo(proposalState.submittedAt);
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
        ProposalState memory state = self.proposals[proposalId].state;
        _checkProposalExists(proposalId, state);

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
        Proposal memory proposal = self.proposals[proposalId];
        _checkProposalExists(proposalId, proposal.state);
        calls = proposal.calls;
    }

    function _checkProposalExists(uint256 proposalId, ProposalState memory proposalState) private pure {
        if (proposalState.status == Status.NotExist) {
            revert ProposalNotFound(proposalId);
        }
    }
}
