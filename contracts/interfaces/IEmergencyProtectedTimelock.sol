// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITimelock} from "./ITimelock.sol";
import {Duration} from "../types/Duration.sol";
import {Timestamp} from "../types/Timestamp.sol";

interface IEmergencyProtectedTimelock is ITimelock {
    struct EmergencyProtectionDetails {
        Duration emergencyModeDuration;
        Timestamp emergencyModeEndsAfter;
        Timestamp emergencyProtectionEndsAfter;
    }

    function MAX_AFTER_SUBMIT_DELAY() external view returns (Duration);
    function MAX_AFTER_SCHEDULE_DELAY() external view returns (Duration);
    function MAX_EMERGENCY_MODE_DURATION() external view returns (Duration);
    function MAX_EMERGENCY_PROTECTION_DURATION() external view returns (Duration);

    function setupDelays(Duration afterSubmitDelay, Duration afterScheduleDelay) external;
    function transferExecutorOwnership(address executor, address owner) external;
    function setEmergencyProtectionActivationCommittee(address emergencyActivationCommittee) external;
    function setEmergencyProtectionExecutionCommittee(address emergencyExecutionCommittee) external;
    function setEmergencyProtectionEndDate(Timestamp emergencyProtectionEndDate) external;
    function setEmergencyModeDuration(Duration emergencyModeDuration) external;
    function setEmergencyGovernance(address emergencyGovernance) external;

    function activateEmergencyMode() external;
    function emergencyExecute(uint256 proposalId) external;
    function deactivateEmergencyMode() external;
    function emergencyReset() external;
    function isEmergencyProtectionEnabled() external view returns (bool);
    function isEmergencyModeActive() external view returns (bool);
    function getEmergencyProtectionDetails() external view returns (EmergencyProtectionDetails memory details);
    function getEmergencyGovernance() external view returns (address emergencyGovernance);
    function getEmergencyActivationCommittee() external view returns (address committee);
    function getEmergencyExecutionCommittee() external view returns (address committee);
    function getAfterSubmitDelay() external view returns (Duration);
    function getAfterScheduleDelay() external view returns (Duration);

    function setAdminExecutor(address newAdminExecutor) external;
}
