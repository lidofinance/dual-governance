// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";

/// @title Timelock State Library
/// @dev Library for managing the configuration related  the state of timelock contract.
library TimelockState {
    // ---
    // Errors
    // ---

    error CallerIsNotGovernance(address caller);
    error InvalidGovernance(address value);
    error InvalidAfterSubmitDelay(Duration value);
    error InvalidAfterScheduleDelay(Duration value);

    // ---
    // Events
    // ---

    event GovernanceSet(address newGovernance);
    event AfterSubmitDelaySet(Duration newAfterSubmitDelay);
    event AfterScheduleDelaySet(Duration newAfterScheduleDelay);

    // ---
    // Data Types
    // ---

    struct Context {
        /// @dev slot0 [0..159]
        address governance;
        /// @dev slot0 [160..191]
        Duration afterSubmitDelay;
        /// @dev slot0 [192..224]
        Duration afterScheduleDelay;
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Sets the governance address.
    /// @param self The context of the Timelock State library.
    /// @param newGovernance The new governance address.
    function setGovernance(Context storage self, address newGovernance) internal {
        if (newGovernance == address(0) || newGovernance == self.governance) {
            revert InvalidGovernance(newGovernance);
        }
        self.governance = newGovernance;
        emit GovernanceSet(newGovernance);
    }

    /// @notice Sets the delay period after a proposal is submitted before it can be scheduled for execution,
    ///     ensuring new delay does not exceed the maximum allowed duration.
    /// @param self The context of the Timelock State library.
    /// @param newAfterSubmitDelay The new after submit delay.
    /// @param maxAfterSubmitDelay The maximum allowed after submit delay.
    function setAfterSubmitDelay(
        Context storage self,
        Duration newAfterSubmitDelay,
        Duration maxAfterSubmitDelay
    ) internal {
        if (newAfterSubmitDelay > maxAfterSubmitDelay || newAfterSubmitDelay == self.afterSubmitDelay) {
            revert InvalidAfterSubmitDelay(newAfterSubmitDelay);
        }
        self.afterSubmitDelay = newAfterSubmitDelay;
        emit AfterSubmitDelaySet(newAfterSubmitDelay);
    }

    /// @notice Sets the delay period after a proposal is scheduled before it can be executed, ensuring
    ///     the new delay does not exceed the maximum allowed duration.
    /// @param self The context of the Timelock State library.
    /// @param newAfterScheduleDelay The new after schedule delay.
    /// @param maxAfterScheduleDelay The maximum allowed after schedule delay.
    function setAfterScheduleDelay(
        Context storage self,
        Duration newAfterScheduleDelay,
        Duration maxAfterScheduleDelay
    ) internal {
        if (newAfterScheduleDelay > maxAfterScheduleDelay || newAfterScheduleDelay == self.afterScheduleDelay) {
            revert InvalidAfterScheduleDelay(newAfterScheduleDelay);
        }
        self.afterScheduleDelay = newAfterScheduleDelay;
        emit AfterScheduleDelaySet(newAfterScheduleDelay);
    }

    /// @notice Retrieves the delay period required after a proposal is submitted before it can be scheduled.
    /// @param self The context of the Timelock State library.
    /// @return Duration The current after submit delay.
    function getAfterSubmitDelay(Context storage self) internal view returns (Duration) {
        return self.afterSubmitDelay;
    }

    /// @notice Retrieves the delay period required after a proposal is scheduled before it can be executed.
    /// @param self The context of the Timelock State library library.
    /// @return Duration The current after schedule delay.
    function getAfterScheduleDelay(Context storage self) internal view returns (Duration) {
        return self.afterScheduleDelay;
    }

    /// @notice Checks if the caller is the governance address, reverting if not.
    /// @param self The context of the Timelock State library.
    function checkCallerIsGovernance(Context storage self) internal view {
        if (self.governance != msg.sender) {
            revert CallerIsNotGovernance(msg.sender);
        }
    }
}
