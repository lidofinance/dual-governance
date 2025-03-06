// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

import {IEmergencyProtectedTimelock} from "../interfaces/IEmergencyProtectedTimelock.sol";

/// @title Emergency Protection Library
/// @notice Manages emergency protection functionality, allowing for the activation and deactivation
///     of emergency mode by designated committees.
library EmergencyProtection {
    // ---
    // Errors
    // ---

    error CallerIsNotEmergencyActivationCommittee(address caller);
    error CallerIsNotEmergencyExecutionCommittee(address caller);
    error EmergencyProtectionExpired(Timestamp protectedTill);
    error InvalidEmergencyGovernance(address governance);
    error InvalidEmergencyActivationCommittee(address committee);
    error InvalidEmergencyExecutionCommittee(address committee);
    error InvalidEmergencyModeDuration(Duration value);
    error InvalidEmergencyProtectionEndDate(Timestamp value);
    error UnexpectedEmergencyModeState(bool state);

    // ---
    // Events
    // ---

    event EmergencyModeActivated();
    event EmergencyModeDeactivated();
    event EmergencyGovernanceSet(address newEmergencyGovernance);
    event EmergencyActivationCommitteeSet(address newActivationCommittee);
    event EmergencyExecutionCommitteeSet(address newExecutionCommittee);
    event EmergencyModeDurationSet(Duration newEmergencyModeDuration);
    event EmergencyProtectionEndDateSet(Timestamp newEmergencyProtectionEndDate);

    // ---
    // Data Types
    // ---

    /// @notice The context of the Emergency Protection library.
    /// @param emergencyModeEndsAfter The timestamp indicating when the emergency mode will end.
    /// @param emergencyActivationCommittee The address of the committee authorized to activate emergency mode.
    /// @param emergencyProtectionEndsAfter The timestamp indicating when emergency protection will expire.
    /// @param emergencyExecutionCommittee The address of the committee authorized to execute scheduled proposals
    ///     or reset governance to the emergency governance while in emergency mode.
    /// @param emergencyModeDuration The duration for which the emergency mode remains active after activation.
    /// @param emergencyGovernance The governance address to which control will be transferred if the
    ///     emergency execution committee initiates a governance reset during emergency mode.
    struct Context {
        /// @dev slot0 [0..39]
        Timestamp emergencyModeEndsAfter;
        /// @dev slot0 [40..199]
        address emergencyActivationCommittee;
        /// @dev slot0 [200..239]
        Timestamp emergencyProtectionEndsAfter;
        /// @dev slot1 [0..159]
        address emergencyExecutionCommittee;
        /// @dev slot1 [160..191]
        Duration emergencyModeDuration;
        /// @dev slot2 [0..159]
        address emergencyGovernance;
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Activates the emergency mode, if it wasn't activated earlier
    /// @param self The context of the Emergency Protection library
    function activateEmergencyMode(Context storage self) internal {
        Timestamp now_ = Timestamps.now();

        if (now_ > self.emergencyProtectionEndsAfter) {
            revert EmergencyProtectionExpired(self.emergencyProtectionEndsAfter);
        }

        self.emergencyModeEndsAfter = self.emergencyModeDuration.addTo(now_);
        emit EmergencyModeActivated();
    }

    /// @notice Deactivates the emergency mode, resetting context fields to default (except
    ///     the emergencyGovernance value).
    /// @param self The context of the Emergency Protection library
    function deactivateEmergencyMode(Context storage self) internal {
        self.emergencyActivationCommittee = address(0);
        self.emergencyExecutionCommittee = address(0);
        self.emergencyProtectionEndsAfter = Timestamps.ZERO;
        self.emergencyModeEndsAfter = Timestamps.ZERO;
        self.emergencyModeDuration = Durations.ZERO;
        emit EmergencyModeDeactivated();
    }

    // ---
    // Setup Functionality
    // ---

    /// @notice Sets the emergency governance address.
    /// @param self The context of the Emergency Protection library
    /// @param newEmergencyGovernance The new emergency governance address.
    function setEmergencyGovernance(Context storage self, address newEmergencyGovernance) internal {
        if (newEmergencyGovernance == self.emergencyGovernance) {
            revert InvalidEmergencyGovernance(newEmergencyGovernance);
        }
        self.emergencyGovernance = newEmergencyGovernance;
        emit EmergencyGovernanceSet(newEmergencyGovernance);
    }

    /// @notice Sets the emergency protection end date, ensuring it does not exceed the maximum
    ///     allowed duration.
    /// @param self The context of the Emergency Protection library
    /// @param newEmergencyProtectionEndDate The new emergency protection end date.
    /// @param maxEmergencyProtectionDuration The maximum duration for the emergency protection.
    function setEmergencyProtectionEndDate(
        Context storage self,
        Timestamp newEmergencyProtectionEndDate,
        Duration maxEmergencyProtectionDuration
    ) internal {
        if (
            newEmergencyProtectionEndDate > maxEmergencyProtectionDuration.addTo(Timestamps.now())
                || newEmergencyProtectionEndDate == self.emergencyProtectionEndsAfter
        ) {
            revert InvalidEmergencyProtectionEndDate(newEmergencyProtectionEndDate);
        }
        self.emergencyProtectionEndsAfter = newEmergencyProtectionEndDate;
        emit EmergencyProtectionEndDateSet(newEmergencyProtectionEndDate);
    }

    /// @notice Sets the emergency mode duration, ensuring it does not exceed the maximum
    ///     allowed duration.
    /// @param self The context of the Emergency Protection library
    /// @param newEmergencyModeDuration The new emergency mode duration.
    /// @param maxEmergencyModeDuration The maximum duration for the emergency mode.
    function setEmergencyModeDuration(
        Context storage self,
        Duration newEmergencyModeDuration,
        Duration maxEmergencyModeDuration
    ) internal {
        if (
            newEmergencyModeDuration > maxEmergencyModeDuration
                || newEmergencyModeDuration == self.emergencyModeDuration
        ) {
            revert InvalidEmergencyModeDuration(newEmergencyModeDuration);
        }

        self.emergencyModeDuration = newEmergencyModeDuration;
        emit EmergencyModeDurationSet(newEmergencyModeDuration);
    }

    /// @notice Sets the emergency activation committee address.
    /// @param self The context of the Emergency Protection library
    /// @param newActivationCommittee The new emergency activation committee address.
    function setEmergencyActivationCommittee(Context storage self, address newActivationCommittee) internal {
        if (newActivationCommittee == self.emergencyActivationCommittee) {
            revert InvalidEmergencyActivationCommittee(newActivationCommittee);
        }
        self.emergencyActivationCommittee = newActivationCommittee;
        emit EmergencyActivationCommitteeSet(newActivationCommittee);
    }

    /// @notice Sets the emergency execution committee address.
    /// @param self The context of the Emergency Protection library
    /// @param newExecutionCommittee The new emergency execution committee address.
    function setEmergencyExecutionCommittee(Context storage self, address newExecutionCommittee) internal {
        if (newExecutionCommittee == self.emergencyExecutionCommittee) {
            revert InvalidEmergencyExecutionCommittee(newExecutionCommittee);
        }
        self.emergencyExecutionCommittee = newExecutionCommittee;
        emit EmergencyExecutionCommitteeSet(newExecutionCommittee);
    }

    // ---
    // Checks
    // ---

    /// @notice Checks if the caller is the emergency activation committee and reverts if not.
    /// @param self The context of the Emergency Protection library
    function checkCallerIsEmergencyActivationCommittee(Context storage self) internal view {
        if (self.emergencyActivationCommittee != msg.sender) {
            revert CallerIsNotEmergencyActivationCommittee(msg.sender);
        }
    }

    /// @notice Checks if the caller is the emergency execution committee and reverts if not.
    /// @param self The context of the Emergency Protection library
    function checkCallerIsEmergencyExecutionCommittee(Context storage self) internal view {
        if (self.emergencyExecutionCommittee != msg.sender) {
            revert CallerIsNotEmergencyExecutionCommittee(msg.sender);
        }
    }

    /// @notice Checks whether the current state of emergency mode matches the expected state (`isActive`),
    ///     and reverts if there is a mismatch.
    /// @param self The context of the Emergency Protection library
    /// @param isActive The expected value of the emergency mode.
    function checkEmergencyMode(Context storage self, bool isActive) internal view {
        if (isEmergencyModeActive(self) != isActive) {
            revert UnexpectedEmergencyModeState(!isActive);
        }
    }

    // ---
    // Getters
    // ---

    /// @notice Retrieves the details of the emergency protection.
    /// @param self  The storage reference to the Context struct.
    /// @return details The struct containing the emergency protection details.
    function getEmergencyProtectionDetails(Context storage self)
        internal
        view
        returns (IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details)
    {
        details.emergencyModeDuration = self.emergencyModeDuration;
        details.emergencyModeEndsAfter = self.emergencyModeEndsAfter;
        details.emergencyProtectionEndsAfter = self.emergencyProtectionEndsAfter;
    }

    /// @notice Checks if the emergency mode is activated
    /// @param self The context of the Emergency Protection library
    /// @return bool Whether the emergency mode is activated or not.
    function isEmergencyModeActive(Context storage self) internal view returns (bool) {
        return self.emergencyModeEndsAfter.isNotZero();
    }

    /// @notice Checks if the emergency mode duration has passed.
    /// @param self The context of the Emergency Protection library
    /// @return bool Whether the emergency mode duration has passed or not.
    function isEmergencyModeDurationPassed(Context storage self) internal view returns (bool) {
        Timestamp endsAfter = self.emergencyModeEndsAfter;
        return endsAfter.isNotZero() && Timestamps.now() > endsAfter;
    }

    /// @notice Checks if the emergency protection is enabled.
    /// @param self The context of the Emergency Protection library
    /// @return bool Whether the emergency protection is enabled or not.
    function isEmergencyProtectionEnabled(Context storage self) internal view returns (bool) {
        return Timestamps.now() <= self.emergencyProtectionEndsAfter || self.emergencyModeEndsAfter.isNotZero();
    }
}
