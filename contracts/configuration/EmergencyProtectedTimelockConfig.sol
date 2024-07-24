// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {IAdminExecutorConfig, AdminExecutorConfigState, AdminExecutorConfig} from "./AdminExecutorConfig.sol";

struct EmergencyProtectionConfig {
    address emergencyGovernance;
    address emergencyActivationCommittee;
    address emergencyExecutionCommittee;
}

struct EmergencyProtectedTimelockConfigState {
    Duration afterSubmitDelay;
    Duration afterScheduleDelay;
    address emergencyGovernance;
    address emergencyActivationCommittee;
    address emergencyExecutionCommittee;
}

interface IEmergencyProtectedTimelockConfig is IAdminExecutorConfig {
    function AFTER_SUBMIT_DELAY() external view returns (Duration);
    function AFTER_SCHEDULE_DELAY() external view returns (Duration);
    function EMERGENCY_GOVERNANCE() external view returns (address);
    function EMERGENCY_ACTIVATION_COMMITTEE() external view returns (address);
    function EMERGENCY_EXECUTION_COMMITTEE() external view returns (address);
}

abstract contract EmergencyProtectedTimelockConfig is IEmergencyProtectedTimelockConfig, AdminExecutorConfig {
    Duration public immutable AFTER_SUBMIT_DELAY;
    Duration public immutable AFTER_SCHEDULE_DELAY;

    address public immutable EMERGENCY_GOVERNANCE;
    address public immutable EMERGENCY_ACTIVATION_COMMITTEE;
    address public immutable EMERGENCY_EXECUTION_COMMITTEE;

    constructor(
        AdminExecutorConfigState memory adminExecutorConfig,
        EmergencyProtectedTimelockConfigState memory input
    ) AdminExecutorConfig(adminExecutorConfig) {
        AFTER_SUBMIT_DELAY = input.afterSubmitDelay;
        AFTER_SCHEDULE_DELAY = input.afterScheduleDelay;
        EMERGENCY_GOVERNANCE = input.emergencyGovernance;
        EMERGENCY_ACTIVATION_COMMITTEE = input.emergencyActivationCommittee;
        EMERGENCY_EXECUTION_COMMITTEE = input.emergencyExecutionCommittee;
    }
}
