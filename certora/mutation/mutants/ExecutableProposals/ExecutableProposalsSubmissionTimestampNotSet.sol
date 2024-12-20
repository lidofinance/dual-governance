// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

import {ExternalCall, ExternalCalls, IExternalExecutor} from "./ExternalCalls.sol";

/// @dev Describes the lifecycle state of a proposal
enum Status {
    /// Proposal has not been submitted yet
    NotExist,
    /// Proposal has been successfully submitted but not scheduled yet. This state is only reachable from NotExist
    Submitted,
    /// Proposal has been successfully scheduled after submission. This state is only reachable from Submitted
    Scheduled,
    /// Proposal has been successfully executed after being scheduled. This state is only reachable from Scheduled
    /// and is the final state of the proposal
    Executed,
    /// Proposal was cancelled before execution. Cancelled proposals cannot be resubmitted or rescheduled.
    /// This state is only reachable from Submitted or Scheduled and is the final state of the proposal.
    /// @dev A proposal is considered cancelled if it was not executed and its ID is less than the ID of the last
    /// submitted proposal at the time the cancelAll() method was called. To check if a proposal is in the Cancelled
    /// state, use the _isProposalMarkedCancelled() view function.
    Cancelled
}

/// @dev Manages a collection of proposals with associated external calls stored as Proposal struct.
/// Proposals are uniquely identified by sequential IDs, starting from one.
library ExecutableProposals {
    using ExternalCalls for ExternalCall[];

    /// @dev Efficiently stores proposal data within a single EVM word.
    /// This struct allows gas-efficient loading from storage using a single EVM sload operation.
    struct ProposalData {
        ///
        /// @dev slot 0: [0..7]
        /// The current status of the proposal. See Status for details.
        Status status;
        ///
        /// @dev slot 0: [8..167]
        /// The address of the associated executor used for executing the proposal's calls.
        address executor;
        ///
        /// @dev slot 0: [168..207]
        /// The timestamp when the proposal was submitted.
        Timestamp submittedAt;
        ///
        /// @dev slot 0: [208..247]
        /// The timestamp when the proposal was scheduled for execution. Equals zero if the proposal hasn't been scheduled yet.
        Timestamp scheduledAt;
    }

    struct Proposal {
        /// @dev Proposal data packed into a struct for efficient loading into memory.
        ProposalData data;
        /// @dev The list of external calls associated with the proposal.
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

    struct Context {
        uint64 proposalsCount;
        uint64 lastCancelledProposalId;
        mapping(uint256 proposalId => Proposal) proposals;
    }

    // ---
    // Proposal lifecycle
    // ---

    function submit(
        Context storage self,
        address executor,
        ExternalCall[] memory calls
    ) internal returns (uint256 newProposalId) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        /// @dev: proposal ids are one-based. The first item has id = 1
        newProposalId = ++self.proposalsCount;
        Proposal storage newProposal = self.proposals[newProposalId];

        newProposal.data.executor = executor;
        newProposal.data.status = Status.Submitted;
        // mutated
        //newProposal.data.submittedAt = Timestamps.now();

        uint256 callsCount = calls.length;
        for (uint256 i = 0; i < callsCount; ++i) {
            newProposal.calls.push(calls[i]);
        }

        emit ProposalSubmitted(newProposalId, executor, calls);
    }

    function schedule(Context storage self, uint256 proposalId, Duration afterSubmitDelay) internal {
        ProposalData memory proposalState = self.proposals[proposalId].data;

        if (proposalState.status != Status.Submitted || _isProposalMarkedCancelled(self, proposalId, proposalState)) {
            revert ProposalNotSubmitted(proposalId);
        }

        if (afterSubmitDelay.addTo(proposalState.submittedAt) > Timestamps.now()) {
            revert AfterSubmitDelayNotPassed(proposalId);
        }

        proposalState.status = Status.Scheduled;
        proposalState.scheduledAt = Timestamps.now();
        self.proposals[proposalId].data = proposalState;

        emit ProposalScheduled(proposalId);
    }

    function execute(Context storage self, uint256 proposalId, Duration afterScheduleDelay) internal {
        Proposal memory proposal = self.proposals[proposalId];

        if (proposal.data.status != Status.Scheduled || _isProposalMarkedCancelled(self, proposalId, proposal.data)) {
            revert ProposalNotScheduled(proposalId);
        }

        if (afterScheduleDelay.addTo(proposal.data.scheduledAt) > Timestamps.now()) {
            revert AfterScheduleDelayNotPassed(proposalId);
        }

        self.proposals[proposalId].data.status = Status.Executed;

        address executor = proposal.data.executor;
        ExternalCall[] memory calls = proposal.calls;

        bytes[] memory results = calls.execute(IExternalExecutor(executor));

        emit ProposalExecuted(proposalId, results);
    }

    function cancelAll(Context storage self) internal {
        uint64 lastCancelledProposalId = self.proposalsCount;
        self.lastCancelledProposalId = lastCancelledProposalId;
        emit ProposalsCancelledTill(lastCancelledProposalId);
    }

    // ---
    // Getters
    // ---

    function canExecute(
        Context storage self,
        uint256 proposalId,
        Duration afterScheduleDelay
    ) internal view returns (bool) {
        ProposalData memory proposalState = self.proposals[proposalId].data;
        if (_isProposalMarkedCancelled(self, proposalId, proposalState)) return false;
        return proposalState.status == Status.Scheduled
            && Timestamps.now() >= afterScheduleDelay.addTo(proposalState.scheduledAt);
    }

    function canSchedule(
        Context storage self,
        uint256 proposalId,
        Duration afterSubmitDelay
    ) internal view returns (bool) {
        ProposalData memory proposalState = self.proposals[proposalId].data;
        if (_isProposalMarkedCancelled(self, proposalId, proposalState)) return false;
        return proposalState.status == Status.Submitted
            && Timestamps.now() >= afterSubmitDelay.addTo(proposalState.submittedAt);
    }

    function getProposalsCount(Context storage self) internal view returns (uint256) {
        return self.proposalsCount;
    }

    function getProposalInfo(
        Context storage self,
        uint256 proposalId
    ) internal view returns (Status status, address executor, Timestamp submittedAt, Timestamp scheduledAt) {
        ProposalData memory proposalData = self.proposals[proposalId].data;
        _checkProposalExists(proposalId, proposalData);

        status = _isProposalMarkedCancelled(self, proposalId, proposalData) ? Status.Cancelled : proposalData.status;
        executor = address(proposalData.executor);
        submittedAt = proposalData.submittedAt;
        scheduledAt = proposalData.scheduledAt;
    }

    function getProposalCalls(
        Context storage self,
        uint256 proposalId
    ) internal view returns (ExternalCall[] memory calls) {
        Proposal memory proposal = self.proposals[proposalId];
        _checkProposalExists(proposalId, proposal.data);
        calls = proposal.calls;
    }

    // ---
    // Private methods
    // ---

    function _checkProposalExists(uint256 proposalId, ProposalData memory proposalData) private pure {
        if (proposalData.status == Status.NotExist) {
            revert ProposalNotFound(proposalId);
        }
    }

    function _isProposalMarkedCancelled(
        Context storage self,
        uint256 proposalId,
        ProposalData memory proposalData
    ) private view returns (bool) {
        return proposalId <= self.lastCancelledProposalId || proposalData.status == Status.Cancelled;
    }
}
