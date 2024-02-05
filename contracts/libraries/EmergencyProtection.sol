// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library EmergencyProtection {
    error NotEmergencyCommittee(address sender);
    error EmergencyCommitteeExpired();
    error EmergencyModeNotEntered();
    error EmergencyPeriodFinished();
    error EmergencyPeriodNotFinished();
    error EmergencyModeIsActive();
    error EmergencyModeWasActivatedPreviously();

    event EmergencyModeActivated();
    event EmergencyModeDeactivated();
    event EmergencyGovernanceReset();
    event EmergencyCommitteeSet(address indexed guardian);
    event EmergencyDurationSet(uint256 emergencyModeDuration);
    event EmergencyCommitteeActiveTillSet(uint256 guardedTill);

    struct State {
        // has rights to activate emergency mode
        address committee;
        // till this time, the committee may activate the emergency mode
        uint40 protectedTill;
        uint40 emergencyModeEndsAfter;
        uint32 emergencyModeDuration;
        // flag which allow to the committee activate the emergency mode only once
        bool emergencyModeWasActivatedPreviously;
    }

    function setup(
        State storage self,
        address committee,
        uint256 lifetime,
        uint256 duration
    ) internal {
        address prevCommittee = self.committee;
        if (prevCommittee != committee) {
            self.committee = committee;
            emit EmergencyCommitteeSet(committee);
        }

        uint256 prevProtectedTill = self.protectedTill;
        uint256 protectedTill = block.timestamp + lifetime;

        if (prevProtectedTill != protectedTill) {
            self.protectedTill = SafeCast.toUint40(protectedTill);
            emit EmergencyCommitteeActiveTillSet(protectedTill);
        }

        uint256 prevDuration = self.emergencyModeDuration;
        if (prevDuration != duration) {
            self.emergencyModeDuration = SafeCast.toUint32(duration);
            emit EmergencyDurationSet(duration);
        }
        // new committee has rights to trigger emergency mode again
        self.emergencyModeWasActivatedPreviously = false;
    }

    function activate(State storage self) internal {
        if (msg.sender != self.committee) {
            revert NotEmergencyCommittee(msg.sender);
        }
        if (block.timestamp > self.protectedTill) {
            revert EmergencyCommitteeExpired();
        }
        if (self.emergencyModeEndsAfter != 0) {
            revert EmergencyModeIsActive();
        }
        if (self.emergencyModeWasActivatedPreviously) {
            revert EmergencyModeWasActivatedPreviously();
        }
        self.emergencyModeEndsAfter = SafeCast.toUint40(
            block.timestamp + self.emergencyModeDuration
        );
        emit EmergencyModeActivated();
    }

    function deactivate(State storage self) internal {
        uint256 endsAfter = self.emergencyModeEndsAfter;
        if (endsAfter == 0) {
            revert EmergencyModeNotEntered();
        }
        if (msg.sender != self.committee && block.timestamp <= endsAfter) {
            revert EmergencyPeriodNotFinished();
        }
        // TODO: Check security guarantees.
        // When deactivation happens, the committee is not reset
        self.emergencyModeEndsAfter = 0;
        emit EmergencyModeDeactivated();
    }

    function reset(State storage self) internal {
        uint256 endsAfter = self.emergencyModeEndsAfter;
        if (endsAfter == 0) {
            revert EmergencyModeNotEntered();
        }
        if (msg.sender != self.committee) {
            revert NotEmergencyCommittee(msg.sender);
        }
        if (block.timestamp > endsAfter) {
            revert EmergencyPeriodFinished();
        }
        self.committee = address(0);
        self.protectedTill = 0;
        self.emergencyModeDuration = 0;
        self.emergencyModeEndsAfter = 0;
        self.emergencyModeWasActivatedPreviously = false;
        emit EmergencyGovernanceReset();
    }

    function isActive(State storage self) internal view returns (bool) {
        uint256 endsAfter = self.emergencyModeEndsAfter;
        if (endsAfter == 0) return false;
        return endsAfter >= block.timestamp;
    }

    function isCommittee(State storage self) internal view returns (bool) {
        return msg.sender == self.committee;
    }

    function validateIsCommittee(State storage self, address account) internal view {
        if (self.committee != account) {
            revert NotEmergencyCommittee(account);
        }
    }
}
