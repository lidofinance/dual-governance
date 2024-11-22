// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

import {ITimelock} from "../interfaces/ITimelock.sol";

import {ExternalCall, ExternalCalls, IExternalExecutor} from "./ExternalCalls.sol";

/// @notice Describes the lifecycle state of a proposal, defining its current status.
/// @param NotExist Proposal has not been submitted yet.
/// @param Submitted Proposal has been successfully submitted but not scheduled yet. This state is
///     only reachable from NotExist.
/// @param Scheduled Proposal has been successfully scheduled after submission. This state is only
///     reachable from Submitted.
/// @param Executed Proposal has been successfully executed after being scheduled. This state is
///     only reachable from Scheduled and is the final state of the proposal.
/// @param Cancelled Proposal was cancelled before execution. Cancelled proposals cannot be resubmitted
///     or rescheduled. This state is only reachable from Submitted or Scheduled and is the final state
///     of the proposal.
///     @dev A proposal is considered cancelled if it was not executed and its id is less than
///         the id of the last submitted proposal at the time the `cancelAll()` method was called.
///         To check if a proposal is in the `Cancelled` state, use the `_isProposalMarkedCancelled()`
///         view function.
enum Status {
    NotExist,
    Submitted,
    Scheduled,
    Executed,
    Cancelled
}

/// @title Executable Proposals Library
/// @notice Manages a collection of proposals with associated external calls stored as Proposal struct.
///     Proposals are uniquely identified by sequential ids, starting from one.
library ExecutableProposals {
    using ExternalCalls for ExternalCall[];

    // ---
    // Data Types
    // ---

    /// @notice Efficiently stores proposal data within a single EVM slot.
    /// @param status The current status of the proposal. See `Status` for details.
    /// @param executor The address of the associated executor used for executing the proposal's calls.
    /// @param submittedAt The timestamp when the proposal was submitted.
    /// @param scheduledAt The timestamp when the proposal was scheduled for execution.
    ///     Equals zero if the proposal hasn't been scheduled yet.
    struct ProposalData {
        /// @dev slot 0: [0..7]
        Status status;
        /// @dev slot 0: [8..167]
        address executor;
        /// @dev slot 0: [168..207]
        Timestamp submittedAt;
        /// @dev slot 0: [208..247]
        Timestamp scheduledAt;
    }

    /// @notice A struct representing a proposal data with associated external calls.
    /// @param data Proposal data packed into a struct for efficient loading into memory.
    /// @param calls List of external calls associated with the proposal
    struct Proposal {
        ProposalData data;
        ExternalCall[] calls;
    }

    /// @notice The context for the library, storing relevant proposals data.
    /// @param proposalsCount The total number of proposals submitted so far.
    /// @param lastCancelledProposalId The id of the most recently canceled proposal.
    /// @param proposals A mapping of proposal ids to their corresponding `Proposal` data.
    struct Context {
        uint64 proposalsCount;
        uint64 lastCancelledProposalId;
        mapping(uint256 proposalId => Proposal) proposals;
    }

    // ---
    // Errors
    // ---

    error EmptyCalls();
    error ProposalNotFound(uint256 proposalId);
    error ProposalNotScheduled(uint256 proposalId);
    error ProposalNotSubmitted(uint256 proposalId);
    error AfterSubmitDelayNotPassed(uint256 proposalId);
    error AfterScheduleDelayNotPassed(uint256 proposalId);

    // ---
    // Events
    // ---

    event ProposalSubmitted(uint256 indexed id, address indexed executor, ExternalCall[] calls, string metadata);
    event ProposalScheduled(uint256 indexed id);
    event ProposalExecuted(uint256 indexed id, bytes[] callResults);
    event ProposalsCancelledTill(uint256 proposalId);

    // ---
    // Proposal lifecycle
    // ---

    /// @notice Submits a new proposal with the specified executor and external calls.
    /// @param self The context of the Executable Proposal library.
    /// @param executor The address authorized to execute the proposal.
    /// @param calls The list of external calls to include in the proposal.
    /// @param metadata Metadata describing the proposal.
    /// @return newProposalId The id of the newly submitted proposal.
    function submit(
        Context storage self,
        address executor,
        ExternalCall[] memory calls,
        string memory metadata
    ) internal returns (uint256 newProposalId) {
        if (calls.length == 0) {
            revert EmptyCalls();
        }

        /// @dev: proposal ids are one-based. The first item has id = 1
        newProposalId = ++self.proposalsCount;
        Proposal storage newProposal = self.proposals[newProposalId];

        newProposal.data.executor = executor;
        newProposal.data.status = Status.Submitted;
        newProposal.data.submittedAt = Timestamps.now();

        uint256 callsCount = calls.length;
        for (uint256 i = 0; i < callsCount; ++i) {
            newProposal.calls.push(calls[i]);
        }

        emit ProposalSubmitted(newProposalId, executor, calls, metadata);
    }

    /// @notice Marks a previously submitted proposal as scheduled for execution if the required delay period
    ///     has passed since submission and the proposal was not canceled.
    /// @param self The context of the Executable Proposal library.
    /// @param proposalId The id of the proposal to schedule.
    /// @param afterSubmitDelay The required delay duration after submission before the proposal can be scheduled.
    ///
    function schedule(Context storage self, uint256 proposalId, Duration afterSubmitDelay) internal {
        ProposalData memory proposalState = self.proposals[proposalId].data;

        if (!_isProposalSubmitted(self, proposalId, proposalState)) {
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

    /// @notice Marks a previously scheduled proposal as executed and runs the associated external calls if the
    ///     required delay period has passed since scheduling and the proposal has not been canceled.
    /// @param self The context of the Executable Proposal library.
    /// @param proposalId The id of the proposal to execute.
    /// @param afterScheduleDelay The minimum delay required after scheduling before execution is allowed.
    function execute(Context storage self, uint256 proposalId, Duration afterScheduleDelay) internal {
        Proposal memory proposal = self.proposals[proposalId];

        if (!_isProposalScheduled(self, proposalId, proposal.data)) {
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

    /// @notice Marks all non-executed proposals up to the most recently submitted as canceled, preventing their execution.
    /// @param self The context of the Executable Proposal library.
    function cancelAll(Context storage self) internal {
        uint64 lastCancelledProposalId = self.proposalsCount;
        self.lastCancelledProposalId = lastCancelledProposalId;
        emit ProposalsCancelledTill(lastCancelledProposalId);
    }

    // ---
    // Getters
    // ---

    /// @notice Determines whether a proposal is eligible for execution based on its status and delay requirements.
    /// @param self The context of the Executable Proposal library.
    /// @param proposalId The id of the proposal to check for execution eligibility.
    /// @param afterScheduleDelay The required delay duration after scheduling before the proposal can be executed.
    /// @return bool `true` if the proposal is eligible for execution, otherwise `false`.
    function canExecute(
        Context storage self,
        uint256 proposalId,
        Duration afterScheduleDelay
    ) internal view returns (bool) {
        ProposalData memory proposalState = self.proposals[proposalId].data;
        return _isProposalScheduled(self, proposalId, proposalState)
            && Timestamps.now() >= afterScheduleDelay.addTo(proposalState.scheduledAt);
    }

    /// @notice Determines whether a proposal is eligible to be scheduled based on its status and required delay.
    /// @param self The context of the Executable Proposal library.
    /// @param proposalId The id of the proposal to check for scheduling eligibility.
    /// @param afterSubmitDelay The minimum delay required after submission before the proposal can be scheduled.
    /// @return bool `true` if the proposal is eligible for scheduling, otherwise `false`.
    function canSchedule(
        Context storage self,
        uint256 proposalId,
        Duration afterSubmitDelay
    ) internal view returns (bool) {
        ProposalData memory proposalState = self.proposals[proposalId].data;
        return _isProposalSubmitted(self, proposalId, proposalState)
            && Timestamps.now() >= afterSubmitDelay.addTo(proposalState.submittedAt);
    }

    /// @notice Returns the total count of submitted proposals.
    /// @param self The context of the Executable Proposal library.
    /// @return uint256 The number of submitted proposal
    function getProposalsCount(Context storage self) internal view returns (uint256) {
        return self.proposalsCount;
    }

    /// @notice Retrieves detailed information about a specific previously submitted proposal.
    /// @param self The context of the Executable Proposal library.
    /// @param proposalId The id of the proposal to retrieve details for.
    /// @return proposalDetails A struct containing the proposal’s id, status, executor, submission timestamp,
    ///     and scheduling timestamp, if applicable
    function getProposalDetails(
        Context storage self,
        uint256 proposalId
    ) internal view returns (ITimelock.ProposalDetails memory proposalDetails) {
        ProposalData memory proposalData = self.proposals[proposalId].data;
        _checkProposalExists(proposalId, proposalData);

        proposalDetails.id = proposalId;
        proposalDetails.status =
            _isProposalMarkedCancelled(self, proposalId, proposalData) ? Status.Cancelled : proposalData.status;
        proposalDetails.executor = address(proposalData.executor);
        proposalDetails.submittedAt = proposalData.submittedAt;
        proposalDetails.scheduledAt = proposalData.scheduledAt;
    }

    /// @notice Retrieves the list of external calls associated with a specific previously submitted proposal.
    /// @param self The storage context for managing proposals within the Executable Proposal library.
    /// @param proposalId The id of the proposal to retrieve calls for.
    /// @return calls An array containing all external calls associated with the specified proposal
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
        return proposalId <= self.lastCancelledProposalId && proposalData.status != Status.Executed;
    }

    function _isProposalScheduled(
        Context storage self,
        uint256 proposalId,
        ProposalData memory proposalData
    ) private view returns (bool) {
        return proposalId > self.lastCancelledProposalId && proposalData.status == Status.Scheduled;
    }

    function _isProposalSubmitted(
        Context storage self,
        uint256 proposalId,
        ProposalData memory proposalData
    ) private view returns (bool) {
        return proposalId > self.lastCancelledProposalId && proposalData.status == Status.Submitted;
    }
}
