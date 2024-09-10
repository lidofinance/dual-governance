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

    function getEmergencyGovernance() external view returns (address emergencyGovernance);
    function getEmergencyActivationCommittee() external view returns (address committee);
    function getEmergencyExecutionCommittee() external view returns (address committee);
    function getEmergencyProtectionDetails() external view returns (EmergencyProtectionDetails memory details);
}
