// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";

/// @title TimelockState
/// @dev Library for managing the configuration related to emergency protection.
library TimelockState {
    error CallerIsNotGovernance(address caller);
    error InvalidGovernance(address value);
    error InvalidAfterSubmitDelay(Duration value);
    error InvalidAfterScheduleDelay(Duration value);

    event GovernanceSet(address newGovernance);
    event AfterSubmitDelaySet(Duration newAfterSubmitDelay);
    event AfterScheduleDelaySet(Duration newAfterScheduleDelay);

    struct Context {
        /// @dev slot0 [0..159]
        address governance;
        /// @dev slot0 [160..191]
        Duration afterSubmitDelay;
        /// @dev slot0 [192..224]
        Duration afterScheduleDelay;
    }

    /// @notice Sets the governance address.
    /// @dev Reverts if the new governance address is zero or the same as the current one.
    /// @param self The context of the timelock state.
    /// @param newGovernance The new governance address.
    function setGovernance(Context storage self, address newGovernance) internal {
        if (newGovernance == address(0) || newGovernance == self.governance) {
            revert InvalidGovernance(newGovernance);
        }
        self.governance = newGovernance;
        emit GovernanceSet(newGovernance);
    }

    /// @notice Sets the after submit delay.
    /// @dev Reverts if the new delay is greater than the maximum allowed or the same as the current one.
    /// @param self The context of the timelock state.
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

    /// @notice Sets the after schedule delay.
    /// @dev Reverts if the new delay is greater than the maximum allowed or the same as the current one.
    /// @param self The context of the timelock state.
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

    /// @notice Gets the after submit delay.
    /// @param self The context of the timelock state.
    /// @return The current after submit delay.
    function getAfterSubmitDelay(Context storage self) internal view returns (Duration) {
        return self.afterSubmitDelay;
    }

    /// @notice Gets the after schedule delay.
    /// @param self The context of the timelock state.
    /// @return The current after schedule delay.
    function getAfterScheduleDelay(Context storage self) internal view returns (Duration) {
        return self.afterScheduleDelay;
    }

    /// @notice Checks if the caller is the governance address.
    /// @dev Reverts if the caller is not the governance address.
    /// @param self The context of the timelock state.
    function checkCallerIsGovernance(Context storage self) internal view {
        if (self.governance != msg.sender) {
            revert CallerIsNotGovernance(msg.sender);
        }
    }
}
