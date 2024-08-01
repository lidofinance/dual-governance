// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

struct EmergencyState {
    address executionCommittee;
    address activationCommittee;
    Timestamp protectedTill;
    bool isEmergencyModeActivated;
    Duration emergencyModeDuration;
    Timestamp emergencyModeEndsAfter;
}

/// @title EmergencyProtection
/// @dev This library manages emergency protection functionality, allowing for
/// the activation and deactivation of emergency mode by designated committees.
library EmergencyProtection {
    error NotEmergencyActivator(address account);
    error NotEmergencyEnactor(address account);
    error EmergencyCommitteeExpired(Timestamp now, Timestamp protectedTill);
    error InvalidEmergencyModeStatus(bool actual, bool expected);

    event EmergencyModeActivated(Timestamp timestamp);
    event EmergencyModeDeactivated(Timestamp timestamp);
    event EmergencyActivationCommitteeSet(address indexed activationCommittee);
    event EmergencyExecutionCommitteeSet(address indexed executionCommittee);
    event EmergencyModeDurationSet(Duration emergencyModeDuration);
    event EmergencyCommitteeProtectedTillSet(Timestamp newProtectedTill);

    struct State {
        // has rights to activate emergency mode
        address activationCommittee;
        Timestamp protectedTill;
        // till this time, the committee may activate the emergency mode
        Timestamp emergencyModeEndsAfter;
        Duration emergencyModeDuration;
        // has rights to execute proposals in emergency mode
        address executionCommittee;
    }

    /// @dev Sets up the initial state of the emergency protection.
    /// @param self The storage reference to the State struct.
    /// @param activationCommittee The address of the emergency activation committee.
    /// @param executionCommittee The address of the emergency execution committee.
    /// @param protectionDuration The duration of the committee protection.
    /// @param emergencyModeDuration The duration of the emergency mode.
    function setup(
        State storage self,
        address activationCommittee,
        address executionCommittee,
        Duration protectionDuration,
        Duration emergencyModeDuration
    ) internal {
        address prevActivationCommittee = self.activationCommittee;
        if (activationCommittee != prevActivationCommittee) {
            self.activationCommittee = activationCommittee;
            emit EmergencyActivationCommitteeSet(activationCommittee);
        }

        address prevExecutionCommittee = self.executionCommittee;
        if (executionCommittee != prevExecutionCommittee) {
            self.executionCommittee = executionCommittee;
            emit EmergencyExecutionCommitteeSet(executionCommittee);
        }

        Timestamp prevProtectedTill = self.protectedTill;
        Timestamp newProtectedTill = protectionDuration.addTo(Timestamps.now());

        if (newProtectedTill != prevProtectedTill) {
            self.protectedTill = newProtectedTill;
            emit EmergencyCommitteeProtectedTillSet(newProtectedTill);
        }

        Duration prevEmergencyModeDuration = self.emergencyModeDuration;
        if (emergencyModeDuration != prevEmergencyModeDuration) {
            self.emergencyModeDuration = emergencyModeDuration;
            emit EmergencyModeDurationSet(emergencyModeDuration);
        }
    }

    /// @dev Activates the emergency mode.
    /// @param self The storage reference to the State struct.
    function activate(State storage self) internal {
        Timestamp now = Timestamps.now();
        if (now > self.protectedTill) {
            revert EmergencyCommitteeExpired(now, self.protectedTill);
        }
        self.emergencyModeEndsAfter = self.emergencyModeDuration.addTo(now);
        emit EmergencyModeActivated(now);
    }

    /// @dev Deactivates the emergency mode.
    /// @param self The storage reference to the State struct.
    function deactivate(State storage self) internal {
        self.activationCommittee = address(0);
        self.executionCommittee = address(0);
        self.protectedTill = Timestamps.ZERO;
        self.emergencyModeEndsAfter = Timestamps.ZERO;
        self.emergencyModeDuration = Durations.ZERO;
        emit EmergencyModeDeactivated(Timestamps.now());
    }

    /// @dev Retrieves the emergency state.
    /// @param self The storage reference to the State struct.
    /// @return res The EmergencyState struct representing the current emergency state.
    function getEmergencyState(State storage self) internal view returns (EmergencyState memory res) {
        res.executionCommittee = self.executionCommittee;
        res.activationCommittee = self.activationCommittee;
        res.protectedTill = self.protectedTill;
        res.emergencyModeDuration = self.emergencyModeDuration;
        res.emergencyModeEndsAfter = self.emergencyModeEndsAfter;
        res.isEmergencyModeActivated = isEmergencyModeActivated(self);
    }

    /// @dev Checks if the emergency mode is activated.
    /// @param self The storage reference to the State struct.
    /// @return Whether the emergency mode is activated or not.
    function isEmergencyModeActivated(State storage self) internal view returns (bool) {
        return self.emergencyModeEndsAfter.isNotZero();
    }

    /// @dev Checks if the emergency mode has passed.
    /// @param self The storage reference to the State struct.
    /// @return Whether the emergency mode has passed or not.
    function isEmergencyModePassed(State storage self) internal view returns (bool) {
        Timestamp endsAfter = self.emergencyModeEndsAfter;
        return endsAfter.isNotZero() && Timestamps.now() > endsAfter;
    }

    /// @dev Checks if the emergency protection is enabled.
    /// @param self The storage reference to the State struct.
    /// @return Whether the emergency protection is enabled or not.
    function isEmergencyProtectionEnabled(State storage self) internal view returns (bool) {
        return Timestamps.now() <= self.protectedTill || self.emergencyModeEndsAfter.isNotZero();
    }

    /// @dev Checks if the caller is the emergency activator and reverts if not.
    /// @param self The storage reference to the State struct.
    /// @param account The account to check.
    function checkActivationCommittee(State storage self, address account) internal view {
        if (self.activationCommittee != account) {
            revert NotEmergencyActivator(account);
        }
    }

    /// @dev Checks if the caller is the emergency enactor and reverts if not.
    /// @param self The storage reference to the State struct.
    /// @param account The account to check.
    function checkExecutionCommittee(State storage self, address account) internal view {
        if (self.executionCommittee != account) {
            revert NotEmergencyEnactor(account);
        }
    }

    /// @dev Checks if the emergency mode matches with expected passed value and reverts if not.
    /// @param self The storage reference to the State struct.
    /// @param expected The expected value of the emergency mode.
    function checkEmergencyModeStatus(State storage self, bool expected) internal view {
        bool actual = isEmergencyModeActivated(self);
        if (actual != expected) {
            revert InvalidEmergencyModeStatus(actual, expected);
        }
    }
}
