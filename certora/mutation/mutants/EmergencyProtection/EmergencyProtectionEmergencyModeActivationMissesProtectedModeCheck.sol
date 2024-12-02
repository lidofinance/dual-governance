// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

/// @title EmergencyProtection
/// @dev This library manages emergency protection functionality, allowing for
/// the activation and deactivation of emergency mode by designated committees.
library EmergencyProtection {
    error CallerIsNotEmergencyActivationCommittee(address caller);
    error CallerIsNotEmergencyExecutionCommittee(address caller);
    error EmergencyProtectionExpired(Timestamp protectedTill);
    error InvalidEmergencyModeDuration(Duration value);
    error InvalidEmergencyProtectionEndDate(Timestamp value);
    error UnexpectedEmergencyModeState(bool value);

    event EmergencyModeActivated();
    event EmergencyModeDeactivated();
    event EmergencyGovernanceSet(address newEmergencyGovernance);
    event EmergencyActivationCommitteeSet(address newActivationCommittee);
    event EmergencyExecutionCommitteeSet(address newActivationCommittee);
    event EmergencyModeDurationSet(Duration newEmergencyModeDuration);
    event EmergencyProtectionEndDateSet(Timestamp newEmergencyProtectionEndDate);

    struct Context {
        /// @dev slot0 [0..39]
        Timestamp emergencyModeEndsAfter;
        /// @dev slot0 [40..199]
        address emergencyActivationCommittee;
        /// @dev slot0 [200..240]
        Timestamp emergencyProtectionEndsAfter;
        /// @dev slot1 [0..159]
        address emergencyExecutionCommittee;
        /// @dev slot1 [160..191]
        Duration emergencyModeDuration;
        /// @dev slot2 [0..160]
        address emergencyGovernance;
    }

    // ---
    // Main functionality
    // ---

    /// @dev Activates the emergency mode.
    /// @param self The storage reference to the Context struct.
    function activateEmergencyMode(Context storage self) internal {
        Timestamp now_ = Timestamps.now();

        // mutated
        //if (now_ > self.emergencyProtectionEndsAfter) {
        //    revert EmergencyProtectionExpired(self.emergencyProtectionEndsAfter);
        //}

        self.emergencyModeEndsAfter = self.emergencyModeDuration.addTo(now_);

        emit EmergencyModeActivated();
    }

    /// @dev Deactivates the emergency mode.
    /// @param self The storage reference to the Context struct.
    function deactivateEmergencyMode(Context storage self) internal {
        self.emergencyActivationCommittee = address(0);
        self.emergencyExecutionCommittee = address(0);
        self.emergencyProtectionEndsAfter = Timestamps.ZERO;
        self.emergencyModeEndsAfter = Timestamps.ZERO;
        self.emergencyModeDuration = Durations.ZERO;
        emit EmergencyModeDeactivated();
    }

    // ---
    // Setup functionality
    // ---

    function setEmergencyGovernance(Context storage self, address newEmergencyGovernance) internal {
        if (newEmergencyGovernance == self.emergencyGovernance) {
            return;
        }
        self.emergencyGovernance = newEmergencyGovernance;
        emit EmergencyGovernanceSet(newEmergencyGovernance);
    }

    function setEmergencyProtectionEndDate(
        Context storage self,
        Timestamp newEmergencyProtectionEndDate,
        Duration maxEmergencyProtectionDuration
    ) internal {
        if (newEmergencyProtectionEndDate > maxEmergencyProtectionDuration.addTo(Timestamps.now())) {
            revert InvalidEmergencyProtectionEndDate(newEmergencyProtectionEndDate);
        }

        if (newEmergencyProtectionEndDate == self.emergencyProtectionEndsAfter) {
            return;
        }
        self.emergencyProtectionEndsAfter = newEmergencyProtectionEndDate;
        emit EmergencyProtectionEndDateSet(newEmergencyProtectionEndDate);
    }

    function setEmergencyModeDuration(
        Context storage self,
        Duration newEmergencyModeDuration,
        Duration maxEmergencyModeDuration
    ) internal {
        if (newEmergencyModeDuration > maxEmergencyModeDuration) {
            revert InvalidEmergencyModeDuration(newEmergencyModeDuration);
        }
        if (newEmergencyModeDuration == self.emergencyModeDuration) {
            return;
        }

        self.emergencyModeDuration = newEmergencyModeDuration;
        emit EmergencyModeDurationSet(newEmergencyModeDuration);
    }

    function setEmergencyActivationCommittee(Context storage self, address newActivationCommittee) internal {
        if (newActivationCommittee == self.emergencyActivationCommittee) {
            return;
        }
        self.emergencyActivationCommittee = newActivationCommittee;
        emit EmergencyActivationCommitteeSet(newActivationCommittee);
    }

    function setEmergencyExecutionCommittee(Context storage self, address newExecutionCommittee) internal {
        if (newExecutionCommittee == self.emergencyExecutionCommittee) {
            return;
        }
        self.emergencyExecutionCommittee = newExecutionCommittee;
        emit EmergencyExecutionCommitteeSet(newExecutionCommittee);
    }

    // ---
    // Checks
    // ---

    /// @dev Checks if the caller is the emergency activator and reverts if not.
    /// @param self The storage reference to the Context struct.
    function checkCallerIsEmergencyActivationCommittee(Context storage self) internal view {
        if (self.emergencyActivationCommittee != msg.sender) {
            revert CallerIsNotEmergencyActivationCommittee(msg.sender);
        }
    }

    /// @dev Checks if the caller is the emergency enactor and reverts if not.
    /// @param self The storage reference to the Context struct.
    function checkCallerIsEmergencyExecutionCommittee(Context storage self) internal view {
        if (self.emergencyExecutionCommittee != msg.sender) {
            revert CallerIsNotEmergencyExecutionCommittee(msg.sender);
        }
    }

    /// @dev Checks if the emergency mode matches with expected passed value and reverts if not.
    /// @param self The storage reference to the Context struct.
    /// @param isActive The expected value of the emergency mode.
    function checkEmergencyMode(Context storage self, bool isActive) internal view {
        if (isEmergencyModeActive(self) != isActive) {
            revert UnexpectedEmergencyModeState(isActive);
        }
    }

    // ---
    // Getters
    // ---

    /// @dev Checks if the emergency mode is activated
    /// @param self The storage reference to the Context struct.
    /// @return Whether the emergency mode is activated or not.
    function isEmergencyModeActive(Context storage self) internal view returns (bool) {
        return self.emergencyModeEndsAfter.isNotZero();
    }

    /// @dev Checks if the emergency mode has passed.
    /// @param self The storage reference to the Context struct.
    /// @return Whether the emergency mode has passed or not.
    function isEmergencyModeDurationPassed(Context storage self) internal view returns (bool) {
        Timestamp endsAfter = self.emergencyModeEndsAfter;
        return endsAfter.isNotZero() && Timestamps.now() > endsAfter;
    }

    /// @dev Checks if the emergency protection is enabled.
    /// @param self The storage reference to the Context struct.
    /// @return Whether the emergency protection is enabled or not.
    function isEmergencyProtectionEnabled(Context storage self) internal view returns (bool) {
        return Timestamps.now() <= self.emergencyProtectionEndsAfter || self.emergencyModeEndsAfter.isNotZero();
    }
}
