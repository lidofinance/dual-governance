// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

struct EmergencyState {
    address executionCommittee;
    address activationCommittee;
    uint256 protectedTill;
    bool isEmergencyModeActivated;
    uint256 emergencyModeDuration;
    uint256 emergencyModeEndsAfter;
}

library EmergencyProtection {
    error NotEmergencyActivator(address account);
    error NotEmergencyEnactor(address account);
    error EmergencyPeriodFinished();
    error EmergencyCommitteeExpired();
    error InvalidEmergencyModeActiveValue(bool actual, bool expected);

    event EmergencyModeActivated();
    event EmergencyModeDeactivated();
    event EmergencyGovernanceReset();
    event EmergencyActivationCommitteeSet(address indexed activationCommittee);
    event EmergencyExecutionCommitteeSet(address indexed executionCommittee);
    event EmergencyModeDurationSet(uint256 emergencyModeDuration);
    event EmergencyCommitteeProtectedTillSet(uint256 protectedTill);

    struct State {
        // has rights to activate emergency mode
        address activationCommittee;
        uint40 protectedTill;
        // till this time, the committee may activate the emergency mode
        uint40 emergencyModeEndsAfter;
        uint32 emergencyModeDuration;
        // has rights to execute proposals in emergency mode
        address executionCommittee;
    }

    function setup(
        State storage self,
        address activationCommittee,
        address executionCommittee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration
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

        uint256 prevProtectedTill = self.protectedTill;
        uint256 protectedTill = block.timestamp + protectionDuration;

        if (protectedTill != prevProtectedTill) {
            self.protectedTill = SafeCast.toUint40(protectedTill);
            emit EmergencyCommitteeProtectedTillSet(protectedTill);
        }

        uint256 prevEmergencyModeDuration = self.emergencyModeDuration;
        if (emergencyModeDuration != prevEmergencyModeDuration) {
            self.emergencyModeDuration = SafeCast.toUint32(emergencyModeDuration);
            emit EmergencyModeDurationSet(emergencyModeDuration);
        }
    }

    function activate(State storage self) internal {
        if (block.timestamp > self.protectedTill) {
            revert EmergencyCommitteeExpired();
        }
        self.emergencyModeEndsAfter = SafeCast.toUint40(block.timestamp + self.emergencyModeDuration);
        emit EmergencyModeActivated();
    }

    function deactivate(State storage self) internal {
        self.activationCommittee = address(0);
        self.executionCommittee = address(0);
        self.protectedTill = 0;
        self.emergencyModeDuration = 0;
        self.emergencyModeEndsAfter = 0;
        emit EmergencyModeDeactivated();
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
        return self.emergencyModeEndsAfter != 0;
    }

    function isEmergencyModePassed(State storage self) internal view returns (bool) {
        uint256 endsAfter = self.emergencyModeEndsAfter;
        return endsAfter != 0 && block.timestamp > endsAfter;
    }

    function isEmergencyProtectionEnabled(State storage self) internal view returns (bool) {
        return block.timestamp <= self.protectedTill || self.emergencyModeEndsAfter != 0;
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
