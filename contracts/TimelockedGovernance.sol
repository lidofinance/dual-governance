// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITimelock} from "./interfaces/ITimelock.sol";
import {IGovernance} from "./interfaces/IGovernance.sol";

import {ExternalCall} from "./libraries/ExternalCalls.sol";

/// @title Timelocked Governance
/// @notice A contract that serves as the interface for submitting and scheduling the execution of governance proposals.
contract TimelockedGovernance is IGovernance {
    // ---
    // Errors
    // ---

    error CallerIsNotGovernance(address caller);
    error InvalidGovernance(address governance);
    error InvalidTimelock(ITimelock timelock);

    // ---
    // Immutable Variables
    // ---

    address public immutable GOVERNANCE;
    ITimelock public immutable TIMELOCK;

    // ---
    // Main Functionality
    // ---

    /// @notice Initializes the TimelockedGovernance contract.
    /// @param governance The address of the governance contract.
    /// @param timelock The address of the timelock contract.
    constructor(address governance, ITimelock timelock) {
        if (governance == address(0)) {
            revert InvalidGovernance(governance);
        }
        if (address(timelock) == address(0)) {
            revert InvalidTimelock(timelock);
        }
        GOVERNANCE = governance;
        TIMELOCK = timelock;
    }

    /// @notice Submits a proposal to the timelock.
    /// @param calls An array of ExternalCall structs representing the calls to be executed in the proposal.
    /// @param metadata A string containing additional information about the proposal.
    /// @return proposalId The id of the submitted proposal.
    function submitProposal(
        ExternalCall[] calldata calls,
        string calldata metadata
    ) external returns (uint256 proposalId) {
        _checkCallerIsGovernance();
        proposalId = TIMELOCK.submit(TIMELOCK.getAdminExecutor(), calls);
        emit ProposalSubmitted(msg.sender, proposalId, metadata);
    }

    /// @notice Schedules a submitted proposal.
    /// @param proposalId The id of the proposal to be scheduled.
    function scheduleProposal(uint256 proposalId) external {
        TIMELOCK.schedule(proposalId);
    }

    /// @notice Checks if a proposal can be scheduled.
    /// @param proposalId The id of the proposal to check.
    /// @return A boolean indicating whether the proposal can be scheduled.
    function canScheduleProposal(uint256 proposalId) external view returns (bool) {
        return TIMELOCK.canSchedule(proposalId);
    }

    /// @notice Cancels all pending proposals that have not been executed.
    /// @return A boolean indicating whether the operation was successful.
    function cancelAllPendingProposals() external returns (bool) {
        _checkCallerIsGovernance();
        TIMELOCK.cancelAllNonExecutedProposals();
        return true;
    }

    // ---
    // Internal Methods
    // ---

    /// @notice Checks if the msg.sender is the governance address.
    function _checkCallerIsGovernance() internal view {
        if (msg.sender != GOVERNANCE) {
            revert CallerIsNotGovernance(msg.sender);
        }
    }
}
