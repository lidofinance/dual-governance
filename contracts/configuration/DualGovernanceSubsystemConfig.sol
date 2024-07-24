// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "../types/Duration.sol";

uint256 constant PERCENT = 10 ** 16;

import {
    EscrowConfigState,
    DualGovernanceConfig,
    TiebreakerConfigState,
    DualGovernanceStateMachineConfigState
} from "./DualGovernanceConfig.sol";
import {
    AdminExecutorConfigState,
    EmergencyProtectedTimelockConfig,
    EmergencyProtectedTimelockConfigState
} from "./EmergencyProtectedTimelockConfig.sol";

contract DualGovernanceSubsystemConfig is EmergencyProtectedTimelockConfig, DualGovernanceConfig {
    constructor(
        address adminExecutor,
        address emergencyGovernance,
        address emergencyActivationCommittee,
        address emergencyExecutionCommittee,
        address resealManager,
        address tiebreakerCommittee,
        address[] memory potentialDeadlockSealables
    )
        EmergencyProtectedTimelockConfig(
            AdminExecutorConfigState({
                // address of the admin executor
                adminExecutor: adminExecutor
            }),
            EmergencyProtectedTimelockConfigState({
                afterSubmitDelay: Durations.from(3 days),
                afterScheduleDelay: Durations.from(2 days),
                emergencyGovernance: emergencyGovernance,
                emergencyActivationCommittee: emergencyActivationCommittee,
                emergencyExecutionCommittee: emergencyExecutionCommittee
            })
        )
        DualGovernanceConfig(
            EscrowConfigState({
                minWithdrawalsBatchSize: 8,
                maxWithdrawalsBatchSize: 128,
                signallingEscrowMinLockTime: Durations.from(5 hours)
            }),
            TiebreakerConfigState({
                resealManager: resealManager,
                tiebreakerCommittee: tiebreakerCommittee,
                tiebreakerActivationTimeout: Durations.from(365 days),
                potentialDeadlockSealables: potentialDeadlockSealables
            }),
            DualGovernanceStateMachineConfigState({
                firstSealRageQuitSupport: 3 * PERCENT,
                secondSealRageQuitSupport: 15 * PERCENT,
                dynamicTimelockMinDuration: Durations.from(3 days),
                dynamicTimelockMaxDuration: Durations.from(30 days),
                vetoSignallingMinActiveDuration: Durations.from(5 hours),
                vetoSignallingDeactivationMaxDuration: Durations.from(5 days),
                vetoCooldownDuration: Durations.from(4 days),
                rageQuitExtensionDelay: Durations.from(7 days),
                rageQuitEthWithdrawalsMinTimelock: Durations.from(60 days),
                rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber: 2,
                rageQuitEthWithdrawalsTimelockGrowthCoeffs: [uint256(0), 0, 0]
            })
        )
    {}
}
