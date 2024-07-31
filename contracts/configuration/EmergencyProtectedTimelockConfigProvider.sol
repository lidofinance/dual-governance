// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timelock} from "../libraries/Timelock.sol";
import {EmergencyProtection} from "../libraries/EmergencyProtection.sol";

interface ITimelockConfigProvider {
    function getTimelockConfig() external view returns (Timelock.Config memory config);
}

interface IEmergencyProtectionConfigProvider {
    function getEmergencyProtectionConfig() external view returns (EmergencyProtection.Config memory config);
}

interface IEmergencyProtectedTimelockConfigProvider is ITimelockConfigProvider, IEmergencyProtectionConfigProvider {}

contract ImmutableEmergencyProtectedTimelockConfigProvider is
    ITimelockConfigProvider,
    IEmergencyProtectionConfigProvider
{
    // ---
    // Timelock Config Immutables
    // ---

    Duration public immutable MIN_SUBMIT_DELAY;
    Duration public immutable MAX_SUBMIT_DELAY;

    Duration public immutable MIN_SCHEDULE_DELAY;
    Duration public immutable MAX_SCHEDULE_DELAY;

    // ---
    // Emergency Protection Config Immutables
    // ---
    Duration public immutable MIN_EMERGENCY_MODE_DURATION;
    Duration public immutable MAX_EMERGENCY_MODE_DURATION;

    Duration public immutable MIN_EMERGENCY_PROTECTION_DURATION;
    Duration public immutable MAX_EMERGENCY_PROTECTION_DURATION;

    constructor(Timelock.Config memory timelockConfig, EmergencyProtection.Config memory emergencyProtectionConfig) {
        MIN_SUBMIT_DELAY = timelockConfig.minSubmitDelay;
        MAX_SUBMIT_DELAY = timelockConfig.maxSubmitDelay;

        MIN_SCHEDULE_DELAY = timelockConfig.minScheduleDelay;
        MAX_SCHEDULE_DELAY = timelockConfig.maxScheduleDelay;

        MIN_EMERGENCY_MODE_DURATION = emergencyProtectionConfig.minEmergencyModeDuration;
        MAX_EMERGENCY_MODE_DURATION = emergencyProtectionConfig.maxEmergencyModeDuration;

        MIN_EMERGENCY_PROTECTION_DURATION = emergencyProtectionConfig.minEmergencyProtectionDuration;
        MAX_EMERGENCY_PROTECTION_DURATION = emergencyProtectionConfig.maxEmergencyProtectionDuration;
    }

    function getTimelockConfig() external view returns (Timelock.Config memory config) {
        config.minSubmitDelay = MIN_SUBMIT_DELAY;
        config.maxSubmitDelay = MAX_SUBMIT_DELAY;

        config.minScheduleDelay = MIN_SCHEDULE_DELAY;
        config.maxScheduleDelay = MAX_SCHEDULE_DELAY;
    }

    function getEmergencyProtectionConfig() external view returns (EmergencyProtection.Config memory config) {}
}
