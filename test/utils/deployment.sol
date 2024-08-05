// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

uint256 constant PERCENT = 10 ** 16;

// ---
// Types
// ---
import {Durations} from "contracts/types/Duration.sol";

// ---
// Interfaces
// ---
import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IResealManager} from "contracts/interfaces/IResealManager.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

import {ITimelock} from "contracts/interfaces/ITimelock.sol";

// ---
// Core Contracts
// ---

import {Escrow} from "contracts/Escrow.sol";
import {Executor} from "contracts/Executor.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

// ---
// Committees
// ---

import {TiebreakerCore} from "contracts/committees/TiebreakerCore.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
import {EmergencyExecutionCommittee} from "contracts/committees/EmergencyExecutionCommittee.sol";
import {EmergencyActivationCommittee} from "contracts/committees/EmergencyActivationCommittee.sol";

// ---
// Configuration
// ---

import {
    DualGovernanceConfig,
    IDualGovernanceConfigProvider,
    ImmutableDualGovernanceConfigProvider
} from "contracts/DualGovernanceConfigProvider.sol";

library Deployment {
    // ---
    // Executor
    // ---
    function deployExecutor(address owner) internal returns (Executor executor) {
        executor = new Executor(owner);
    }

    // ---
    // Emergency Protected Timelock
    // ---

    function deployEmergencyProtectedTimelock(
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams,
        Executor adminExecutor
    ) internal returns (EmergencyProtectedTimelock timelock) {
        timelock = new EmergencyProtectedTimelock(sanityCheckParams, address(adminExecutor));
    }

    // ---
    // Dual Governance Configuration
    // ---

    function deployDualGovernanceConfigProvider()
        internal
        returns (ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider)
    {
        dualGovernanceConfigProvider = new ImmutableDualGovernanceConfigProvider(
            DualGovernanceConfig.Context({
                firstSealRageQuitSupport: 3 * PERCENT,
                secondSealRageQuitSupport: 15 * PERCENT,
                //
                minAssetsLockDuration: Durations.from(5 hours),
                dynamicTimelockMinDuration: Durations.from(3 days),
                dynamicTimelockMaxDuration: Durations.from(30 days),
                //
                vetoSignallingMinActiveDuration: Durations.from(5 hours),
                vetoSignallingDeactivationMaxDuration: Durations.from(5 days),
                vetoCooldownDuration: Durations.from(4 days),
                //
                rageQuitExtensionDelay: Durations.from(7 days),
                rageQuitEthWithdrawalsMinTimelock: Durations.from(60 days),
                rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber: 2,
                rageQuitEthWithdrawalsTimelockGrowthCoeffs: [uint256(0), 0, 0]
            })
        );
    }

    // ---
    // Dual Governance
    // ---

    function deployDualGovernance(
        ITimelock timelock,
        IResealManager resealManager,
        IDualGovernanceConfigProvider configProvider,
        DualGovernance.SanityCheckParams memory dualGovernanceSanityCheckParams,
        Escrow.SanityCheckParams memory escrowSanityCheckParams,
        Escrow.ProtocolDependencies memory escrowProtocolDependencies
    ) internal returns (DualGovernance dualGovernance) {
        dualGovernance = new DualGovernance(
            timelock,
            resealManager,
            configProvider,
            dualGovernanceSanityCheckParams,
            escrowSanityCheckParams,
            escrowProtocolDependencies
        );
    }

    // ---
    // Reseal Manager
    // ---
    function deployResealManager(ITimelock timelock) internal returns (ResealManager resealManager) {
        resealManager = new ResealManager(timelock);
    }

    // ---
    // Timelocked Governance
    // ---
    function deployTimelockedGovernance(
        address governance,
        ITimelock timelock
    ) internal returns (TimelockedGovernance) {
        return new TimelockedGovernance(governance, timelock);
    }

    // ---
    // Committees
    // ---

    function deployEmergencyActivationCommittee(
        address adminExecutor,
        address emergencyProtectedTimelock,
        address[] memory committeeMembers,
        uint256 executionQuorum
    ) internal returns (EmergencyActivationCommittee) {
        return new EmergencyActivationCommittee({
            owner: adminExecutor,
            committeeMembers: committeeMembers,
            executionQuorum: executionQuorum,
            emergencyProtectedTimelock: emergencyProtectedTimelock
        });
    }

    function deployEmergencyExecutionCommittee(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) internal returns (EmergencyExecutionCommittee) {
        return new EmergencyExecutionCommittee(owner, committeeMembers, executionQuorum, emergencyProtectedTimelock);
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

    function deployTiebreakerSubCommittee(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address tiebreakerCore
    ) internal returns (TiebreakerSubCommittee) {
        return new TiebreakerSubCommittee(owner, committeeMembers, executionQuorum, tiebreakerCore);
    }

    // ---
    // Dual Governance Setup Deployment
    // ---

    struct DualGovernanceSetup {
        Executor adminExecutor;
        ResealManager resealManager;
        EmergencyProtectedTimelock timelock;
        TimelockedGovernance emergencyGovernance;
        ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider;
        DualGovernance dualGovernance;
    }

    function deployDualGovernanceContracts(
        IStETH stETH,
        IWstETH wstETH,
        IWithdrawalQueue withdrawalQueue,
        address emergencyGovernance
    ) internal returns (DualGovernanceSetup memory setup) {
        address tmpExecutorOwner = address(this);
        setup.adminExecutor = deployExecutor({owner: tmpExecutorOwner});

        setup.timelock = deployEmergencyProtectedTimelock({
            adminExecutor: setup.adminExecutor,
            sanityCheckParams: EmergencyProtectedTimelock.SanityCheckParams({
                maxAfterSubmitDelay: Durations.from(45 days),
                maxAfterScheduleDelay: Durations.from(45 days),
                maxEmergencyModeDuration: Durations.from(365 days),
                maxEmergencyProtectionDuration: Durations.from(180 days)
            })
        });

        setup.resealManager = deployResealManager(setup.timelock);
        setup.dualGovernanceConfigProvider = deployDualGovernanceConfigProvider();
        setup.emergencyGovernance = deployTimelockedGovernance(emergencyGovernance, setup.timelock);

        setup.dualGovernance = deployDualGovernance({
            timelock: setup.timelock,
            resealManager: setup.resealManager,
            configProvider: setup.dualGovernanceConfigProvider,
            dualGovernanceSanityCheckParams: DualGovernance.SanityCheckParams({
                minTiebreakerActivationTimeout: Durations.from(180 days),
                maxTiebreakerActivationTimeout: Durations.from(365 days),
                maxSealableWithdrawalBlockersCount: 255
            }),
            escrowSanityCheckParams: Escrow.SanityCheckParams({minWithdrawalsBatchSize: 4}),
            escrowProtocolDependencies: Escrow.ProtocolDependencies({
                stETH: stETH,
                wstETH: wstETH,
                withdrawalQueue: withdrawalQueue
            })
        });
    }
}
