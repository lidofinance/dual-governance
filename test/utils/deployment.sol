// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

uint256 constant PERCENT = 10 ** 16;

// ---
// Types
// ---
import {Durations} from "contracts/types/Duration.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Executor} from "contracts/Executor.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

// ---
// Committees
// ---

import {TiebreakerCore} from "contracts/committees/TiebreakerCore.sol";
import {EmergencyActivationCommittee} from "contracts/committees/EmergencyActivationCommittee.sol";

// ---
// Configuration
// ---

import {
    Tiebreaker,
    EscrowState,
    DualGovernanceStateMachine,
    IDualGovernanceConfigProvider,
    ImmutableDualGovernanceConfigProvider
} from "contracts/configuration/DualGovernanceConfigProvider.sol";
import {
    Timelock,
    EmergencyProtection,
    IEmergencyProtectedTimelockConfigProvider,
    ImmutableEmergencyProtectedTimelockConfigProvider
} from "contracts/configuration/EmergencyProtectedTimelockConfigProvider.sol";

library Deployment {
    // ---
    // Configuration
    // ---

    function deployEmergencyProtectedTimelockConfigProvider()
        internal
        returns (ImmutableEmergencyProtectedTimelockConfigProvider configProvider)
    {
        configProvider = new ImmutableEmergencyProtectedTimelockConfigProvider(
            Timelock.Config({
                minSubmitDelay: Durations.ZERO,
                maxSubmitDelay: Durations.from(30 days),
                minScheduleDelay: Durations.ZERO,
                maxScheduleDelay: Durations.from(30 days)
            }),
            EmergencyProtection.Config({
                minEmergencyModeDuration: Durations.from(180 days),
                maxEmergencyModeDuration: Durations.from(365 days),
                minEmergencyProtectionDuration: Durations.from(30 days),
                maxEmergencyProtectionDuration: Durations.from(90 days)
            })
        );
    }

    function deployDualGovernanceConfigProvider()
        internal
        returns (ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider)
    {
        dualGovernanceConfigProvider = new ImmutableDualGovernanceConfigProvider(
            EscrowState.Config({
                minWithdrawalsBatchSize: 8,
                maxWithdrawalsBatchSize: 128,
                signallingEscrowMinLockTime: Durations.from(5 hours)
            }),
            Tiebreaker.Config({
                maxSealableWithdrawalBlockers: 5,
                minTiebreakerActivationTimeout: Durations.from(365 days),
                maxTiebreakerActivationTimeout: Durations.from(730 days)
            }),
            DualGovernanceStateMachine.Config({
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
        );
    }

    // ---
    // Admin Executor
    // ---
    function deployAdminExecutor(address owner) internal returns (Executor executor) {
        executor = new Executor(owner);
    }

    // ---
    // Emergency Protected Timelock
    // ---

    function deployEmergencyProtectedTimelock(
        IEmergencyProtectedTimelockConfigProvider configProvider,
        Executor adminExecutor
    ) internal returns (EmergencyProtectedTimelock timelock) {
        timelock = new EmergencyProtectedTimelock(address(configProvider), address(adminExecutor));
    }

    // ---
    // Escrow Master Copy
    // ---

    function deployEscrowMasterCopy(
        address stETH,
        address wstETH,
        address withdrawalQueue
    ) internal returns (Escrow escrow) {
        escrow = new Escrow({stETH: stETH, wstETH: wstETH, withdrawalQueue: withdrawalQueue});
    }

    // ---
    // Dual Governance
    // ---

    function deployDualGovernance(
        IDualGovernanceConfigProvider configProvider,
        EmergencyProtectedTimelock timelock,
        Escrow escrowMasterCopy
    ) internal returns (DualGovernance dualGovernance) {
        dualGovernance =
            new DualGovernance({timelock: timelock, configProvider: configProvider, escrowMasterCopy: escrowMasterCopy});
    }

    // ---
    // Committees
    // ---

    function deployEmergencyActivationCommittee(
        address adminExecutor,
        address emergencyProtectedTimelock,
        address[] memory committeeMembers,
        uint256 executionQuorum
    ) internal returns (EmergencyActivationCommittee committee) {
        committee = new EmergencyActivationCommittee({
            owner: adminExecutor,
            committeeMembers: committeeMembers,
            executionQuorum: executionQuorum,
            emergencyProtectedTimelock: emergencyProtectedTimelock
        });
    }

    function deployTiebreakerCoreCommittee(
        address adminExecutor,
        address dualGovernance
    ) internal returns (TiebreakerCore tiebreakerCore) {
        tiebreakerCore = new TiebreakerCore({
            owner: adminExecutor,
            dualGovernance: dualGovernance,
            committeeMembers: new address[](0),
            executionQuorum: 1,
            timelock: 0
        });
    }

    // ---
    // Dual Governance Setup Deployment
    // ---

    struct DualGovernanceSetup {
        Executor adminExecutor;
        Escrow escrowMasterCopy;
        ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider;
        ImmutableEmergencyProtectedTimelockConfigProvider timelockConfigProvider;
        EmergencyProtectedTimelock timelock;
        DualGovernance dualGovernance;
    }

    function deployDualGovernanceSetup(
        address stETH,
        address wstETH,
        address withdrawalQueue
    ) internal returns (DualGovernanceSetup memory setup) {
        address tmpExecutorOwner = address(this);
        setup.adminExecutor = deployAdminExecutor({owner: tmpExecutorOwner});
        setup.escrowMasterCopy =
            deployEscrowMasterCopy({stETH: stETH, wstETH: wstETH, withdrawalQueue: withdrawalQueue});

        setup.dualGovernanceConfigProvider = deployDualGovernanceConfigProvider();
        setup.timelockConfigProvider = deployEmergencyProtectedTimelockConfigProvider();

        setup.timelock = deployEmergencyProtectedTimelock({
            adminExecutor: setup.adminExecutor,
            configProvider: setup.timelockConfigProvider
        });

        setup.dualGovernance = deployDualGovernance({
            timelock: setup.timelock,
            configProvider: setup.dualGovernanceConfigProvider,
            escrowMasterCopy: setup.escrowMasterCopy
        });
    }
}
