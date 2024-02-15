// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

struct EmergencyState {
    address committee;
    uint256 protectedTill;
    bool isEmergencyModeActivated;
    uint256 emergencyModeDuration;
    uint256 emergencyModeEndsAfter;
}

library EmergencyProtection {
    error NotEmergencyCommittee(address sender);
    error EmergencyModeNotActivated();
    error EmergencyPeriodFinished();
    error EmergencyCommitteeExpired();
    error EmergencyModeAlreadyActive();

    event EmergencyModeActivated();
    event EmergencyModeDeactivated();
    event EmergencyGovernanceReset();
    event EmergencyCommitteeSet(address indexed guardian);
    event EmergencyModeDurationSet(uint256 emergencyModeDuration);
    event EmergencyCommitteeProtectedTillSet(uint256 protectedTill);

    struct State {
        // has rights to activate emergency mode
        address committee;
        // till this time, the committee may activate the emergency mode
        uint40 protectedTill;
        uint40 emergencyModeEndsAfter;
        uint32 emergencyModeDuration;
    }

    function setup(
        State storage self,
        address committee,
        uint256 protectionDuration,
        uint256 emergencyModeDuration
    ) internal {
        address prevCommittee = self.committee;
        if (prevCommittee != committee) {
            self.committee = committee;
            emit EmergencyCommitteeSet(committee);
        }

        uint256 prevProtectedTill = self.protectedTill;
        uint256 protectedTill = block.timestamp + protectionDuration;

        if (prevProtectedTill != protectedTill) {
            self.protectedTill = SafeCast.toUint40(protectedTill);
            emit EmergencyCommitteeProtectedTillSet(protectedTill);
        }

        uint256 prevDuration = self.emergencyModeDuration;
        if (prevDuration != emergencyModeDuration) {
            self.emergencyModeDuration = SafeCast.toUint32(emergencyModeDuration);
            emit EmergencyModeDurationSet(emergencyModeDuration);
        }
    }

    function activate(State storage self) internal {
        if (msg.sender != self.committee) {
            revert NotEmergencyCommittee(msg.sender);
        }
        if (block.timestamp > self.protectedTill) {
            revert EmergencyCommitteeExpired();
        }
        if (self.emergencyModeEndsAfter != 0) {
            revert EmergencyModeAlreadyActive();
        }
        self.emergencyModeEndsAfter = SafeCast.toUint40(block.timestamp + self.emergencyModeDuration);
        emit EmergencyModeActivated();
    }

    function deactivate(State storage self) internal {
        uint256 endsAfter = self.emergencyModeEndsAfter;
        if (endsAfter == 0) {
            revert EmergencyModeNotActivated();
        }
        _reset(self);
        emit EmergencyModeDeactivated();
    }

    function reset(State storage self) internal {
        uint256 endsAfter = self.emergencyModeEndsAfter;
        if (endsAfter == 0) {
            revert EmergencyModeNotActivated();
        }
        if (block.timestamp > endsAfter) {
            revert EmergencyPeriodFinished();
        }
        _reset(self);
        emit EmergencyGovernanceReset();
    }

    function validateIsCommittee(State storage self, address account) internal view {
        if (self.committee != account) {
            revert NotEmergencyCommittee(account);
        }
    }

    function getEmergencyState(State storage self) internal view returns (EmergencyState memory res) {
        res.committee = self.committee;
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

    function _reset(State storage self) private {
        self.committee = address(0);
        self.emergencyModeDuration = 0;
        self.emergencyModeEndsAfter = 0;
    }
}
