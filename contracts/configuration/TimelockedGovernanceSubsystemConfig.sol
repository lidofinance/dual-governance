// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "../types/Duration.sol";

import {AdminExecutorConfigState} from "./AdminExecutorConfig.sol";
import {
    EmergencyProtectedTimelockConfig,
    EmergencyProtectedTimelockConfigState
} from "./EmergencyProtectedTimelockConfig.sol";

contract TimelockedGovernanceSubsystemConfig is EmergencyProtectedTimelockConfig {
    constructor(
        address adminExecutor,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee
    )
        EmergencyProtectedTimelockConfig(
            AdminExecutorConfigState({
                /// address of the admin executor
                adminExecutor: adminExecutor
            }),
            EmergencyProtectedTimelockConfigState({
                emergencyGovernance: emergencyGovernance,
                afterSubmitDelay: Durations.ZERO,
                afterScheduleDelay: Durations.from(3 days),
                emergencyActivationCommittee: emergencyActivationCommittee,
                emergencyExecutionCommittee: emergencyExecutionCommittee
            })
        )
    {}
}
