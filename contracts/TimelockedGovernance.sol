// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITimelock} from "./interfaces/ITimelock.sol";
import {IGovernance} from "./interfaces/IGovernance.sol";

import {ExternalCall} from "./libraries/ExternalCalls.sol";

/// @title TimelockedGovernance
/// @dev A contract that serves as the interface for submitting and scheduling the execution of governance proposals.
contract TimelockedGovernance is IGovernance {
    error CallerIsNotGovernance(address caller);

    address public immutable GOVERNANCE;
    ITimelock public immutable TIMELOCK;

    /// @dev Initializes the TimelockedGovernance contract.
    /// @param governance The address of the governance contract.
    /// @param timelock The address of the timelock contract.
    constructor(address governance, ITimelock timelock) {
        GOVERNANCE = governance;
        TIMELOCK = timelock;
    }

    /// @dev Submits a proposal to the timelock.
    /// @param calls An array of ExternalCall structs representing the calls to be executed in the proposal.
    /// @return proposalId The ID of the submitted proposal.
    function submitProposal(ExternalCall[] calldata calls) external returns (uint256 proposalId) {
        _checkCallerIsGovernance();
        return TIMELOCK.submit(TIMELOCK.getAdminExecutor(), calls);
    }

    /// @dev Schedules a submitted proposal.
    /// @param proposalId The ID of the proposal to be scheduled.
    function scheduleProposal(uint256 proposalId) external {
        TIMELOCK.schedule(proposalId);
    }

    /// @dev Executes a scheduled proposal.
    /// @param proposalId The ID of the proposal to be executed.
    function executeProposal(uint256 proposalId) external {
        TIMELOCK.execute(proposalId);
    }

    /// @dev Checks if a proposal can be scheduled.
    /// @param proposalId The ID of the proposal to check.
    /// @return A boolean indicating whether the proposal can be scheduled.
    function canScheduleProposal(uint256 proposalId) external view returns (bool) {
        return TIMELOCK.canSchedule(proposalId);
    }

    /// @dev Cancels all pending proposals that have not been executed.
    function cancelAllPendingProposals() external {
        _checkCallerIsGovernance();
        TIMELOCK.cancelAllNonExecutedProposals();
    }

    /// @dev Checks if the msg.sender is the governance address.
    function _checkCallerIsGovernance() internal view {
        if (msg.sender != GOVERNANCE) {
            revert CallerIsNotGovernance(msg.sender);
        }
    }
}
