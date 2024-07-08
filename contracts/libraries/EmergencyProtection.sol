// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

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

library EmergencyProtection {
    error NotEmergencyActivator(address account);
    error NotEmergencyEnactor(address account);
    error EmergencyCommitteeExpired(Timestamp timestamp, Timestamp protectedTill);
    error InvalidEmergencyModeActiveValue(bool actual, bool expected);

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

    function activate(State storage self) internal {
        Timestamp timestamp = Timestamps.now();
        if (timestamp > self.protectedTill) {
            revert EmergencyCommitteeExpired(timestamp, self.protectedTill);
        }
        self.emergencyModeEndsAfter = self.emergencyModeDuration.addTo(timestamp);
        emit EmergencyModeActivated(timestamp);
    }

    function deactivate(State storage self) internal {
        self.activationCommittee = address(0);
        self.executionCommittee = address(0);
        self.protectedTill = Timestamps.ZERO;
        self.emergencyModeEndsAfter = Timestamps.ZERO;
        self.emergencyModeDuration = Durations.ZERO;
        emit EmergencyModeDeactivated(Timestamps.now());
    }

    function getEmergencyState(State storage self) internal view returns (EmergencyState memory res) {
        res.executionCommittee = self.executionCommittee;
        res.activationCommittee = self.activationCommittee;
        res.protectedTill = self.protectedTill;
        res.emergencyModeDuration = self.emergencyModeDuration;
        res.emergencyModeEndsAfter = self.emergencyModeEndsAfter;
        res.isEmergencyModeActivated = isEmergencyModeActivated(self);
    }

    function isEmergencyModeActivated(State storage self) internal view returns (bool) {
        return self.emergencyModeEndsAfter.isNotZero();
    }

    function isEmergencyModePassed(State storage self) internal view returns (bool) {
        Timestamp endsAfter = self.emergencyModeEndsAfter;
        return endsAfter.isNotZero() && Timestamps.now() > endsAfter;
    }

    function isEmergencyProtectionEnabled(State storage self) internal view returns (bool) {
        return Timestamps.now() <= self.protectedTill || self.emergencyModeEndsAfter.isNotZero();
    }

    function checkActivationCommittee(State storage self, address account) internal view {
        if (self.activationCommittee != account) {
            revert NotEmergencyActivator(account);
        }
    }

    function checkExecutionCommittee(State storage self, address account) internal view {
        if (self.executionCommittee != account) {
            revert NotEmergencyEnactor(account);
        }
    }

    function checkEmergencyModeActive(State storage self, bool expected) internal view {
        bool actual = isEmergencyModeActivated(self);
        if (actual != expected) {
            revert InvalidEmergencyModeActiveValue(actual, expected);
        }
    }
}
