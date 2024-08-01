// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
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

    event EmergencyModeActivated();
    event EmergencyModeDeactivated();
    event EmergencyGovernanceSet(address newEmergencyGovernance);
    event EmergencyActivationCommitteeSet(address newActivationCommittee);
    event EmergencyExecutionCommitteeSet(address newActivationCommittee);
    event EmergencyModeDurationSet(Duration newEmergencyModeDuration);
    event EmergencyModeProtectionDurationSet(
        Duration newEmergencyProtectionDuration, Timestamp newEmergencyModeProtectedTill
    );

    struct Config {
        Duration minEmergencyModeDuration;
        Duration maxEmergencyModeDuration;
        Duration maxEmergencyProtectionDuration;
        Duration minEmergencyProtectionDuration;
    }

    struct Context {
        Duration emergencyModeDuration;
        Duration emergencyProtectionDuration;
        Timestamp emergencyModeProtectedTill;
        address emergencyActivationCommittee;
        address emergencyExecutionCommittee;
        Timestamp emergencyModeEndsAfter;
        address emergencyGovernance;
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
        if (
            newEmergencyModeDuration < config.minEmergencyModeDuration
                || newEmergencyModeDuration > config.minEmergencyModeDuration
        ) {
            revert InvalidEmergencyModeDuration(newEmergencyModeDuration);
        }
        if (self.emergencyModeDuration == newEmergencyModeDuration) {
            return;
        }
        self.emergencyModeDuration = newEmergencyModeDuration;
        emit EmergencyModeDurationSet(newEmergencyModeDuration);
    }

    function setEmergencyGovernance(Context storage self, address newEmergencyGovernance) internal {
        if (self.emergencyGovernance == newEmergencyGovernance) {
            return;
        }
        self.emergencyGovernance = newEmergencyGovernance;
        emit EmergencyGovernanceSet(newEmergencyGovernance);
    }

    function setEmergencyModeProtectedTill(
        Context storage self,
        Config memory config,
        Duration newEmergencyProtectionDuration
    ) internal {
        if (
            newEmergencyProtectionDuration < config.minEmergencyModeDuration
                || newEmergencyProtectionDuration > config.minEmergencyModeDuration
        ) {
            revert InvalidEmergencyProtectionDuration(newEmergencyProtectionDuration);
        }
        Timestamp newEmergencyModeProtectedTill = newEmergencyProtectionDuration.addTo(Timestamps.now());
        if (
            self.emergencyModeProtectedTill == newEmergencyModeProtectedTill
                && self.emergencyModeProtectedTill == newEmergencyModeProtectedTill
        ) {
            return;
        }
        self.emergencyModeProtectedTill = newEmergencyModeProtectedTill;
        self.emergencyProtectionDuration = newEmergencyProtectionDuration;
        emit EmergencyModeProtectionDurationSet(newEmergencyProtectionDuration, newEmergencyModeProtectedTill);
    }

    function setEmergencyActivationCommittee(Context storage self, address newActivationCommittee) internal {
        if (self.emergencyActivationCommittee == newActivationCommittee) {
            return;
        }
        self.emergencyActivationCommittee = newActivationCommittee;
        emit EmergencyActivationCommitteeSet(newActivationCommittee);
    }

    function setEmergencyExecutionCommittee(Context storage self, address newExecutionCommittee) internal {
        if (self.emergencyActivationCommittee == newExecutionCommittee) {
            return;
        }
        self.emergencyExecutionCommittee = newExecutionCommittee;
        emit EmergencyExecutionCommitteeSet(newExecutionCommittee);
    }

    function checkActivationCommittee(Context storage self, address account) internal view {
        if (self.emergencyActivationCommittee != account) {
            revert InvalidEmergencyActivatationCommittee(account, self.emergencyActivationCommittee);
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

    function isEmergencyModeActive(Context storage self) internal view returns (bool) {
        return self.emergencyModeEndsAfter >= Timestamps.now();
    }

    function isEmergencyProtectionEnabled(Context memory self) internal view returns (bool) {
        return Timestamps.now() <= self.emergencyModeProtectedTill;
    }

    function activate(Context storage self) internal {
        if (Timestamps.now() > self.emergencyModeProtectedTill) {
            revert EmergencyCommitteeExpired(self.emergencyModeProtectedTill);
        }
        self.emergencyModeEndsAfter = self.emergencyModeDuration.addTo(Timestamps.now());
        emit EmergencyModeActivated();
    }

    function deactivate(Context storage self) internal {
        self.emergencyModeEndsAfter = Timestamps.now();
        emit EmergencyModeDeactivated();
    }
}
