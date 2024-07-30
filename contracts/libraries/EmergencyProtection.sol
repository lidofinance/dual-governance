// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

library EmergencyProtection {
    error EmergencyProtectionDisabled();
    error InvalidEmergencyModeDuration(Duration value);
    error InvalidEmergencyProtectionDuration(Duration value);
    error EmergencyCommitteeExpired(Timestamp protectedTill);
    error InvalidEmergencyModeState(bool value);
    error InvalidEmergencyActivatationCommittee(address actual, address expected);
    error InvalidEmergencyExecutionCommittee(address actual, address expected);

    event EmergencyModeActivated();
    event EmergencyModeDeactivated();
    event EmergencyGovernanceSet(address newEmergencyGovernance);
    event EmergencyActivationCommitteeSet(address newActivationCommittee);
    event EmergencyExecutionCommitteeSet(address newActivationCommittee);
    event EmergencyModeDurationSet(Duration newEmergencyModeDuration);
    event EmergencyModeProtectionDurationSet(
        Duration newEmergencyProtectionDuration, Timestamp newEmergencyModeProtectedTill
    );

    struct Context {
        Duration emergencyModeDuration;
        Duration emergencyProtectionDuration;
        Timestamp emergencyModeProtectedTill;
        address emergencyActivationCommittee;
        address emergencyExecutionCommittee;
        Timestamp emergencyModeEndsAfter;
        address emergencyGovernance;
    }

    function setEmergencyModeDuration(Context storage self, Duration newEmergencyModeDuration) internal {
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

    function setEmergencyModeProtectedTill(Context storage self, Duration newEmergencyProtectionDuration) internal {
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

    function checkExecutionCommittee(Context storage self, address account) internal view {
        if (self.emergencyExecutionCommittee != account) {
            revert InvalidEmergencyExecutionCommittee(account, self.emergencyExecutionCommittee);
        }
    }

    function checkEmergencyProtectionEnabled(Context storage self) internal view {
        if (!isEmergencyProtectionEnabled(self)) {
            revert EmergencyProtectionDisabled();
        }
    }

    function checkEmergencyMode(Context storage self, bool isActive) internal view {
        bool isActiveActual = isEmergencyModeActive(self);
        if (isActiveActual != isActive) {
            revert InvalidEmergencyModeState(isActive);
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
