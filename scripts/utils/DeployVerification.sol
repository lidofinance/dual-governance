// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable custom-errors, reason-string */

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations} from "contracts/types/Duration.sol";
import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IEscrowBase} from "contracts/interfaces/IEscrowBase.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {Escrow} from "contracts/Escrow.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {State as EscrowState} from "contracts/libraries/EscrowState.sol";

import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {
    DGSetupDeployConfig,
    DGSetupDeployArtifacts,
    DGSetupDeployedContracts,
    TimelockContractDeployConfig
} from "../utils/contracts-deployment.sol";

import {TiebreakerDeployConfig, TiebreakerSubCommitteeDeployConfig} from "../utils/deployment/Tiebreaker.sol";

library DeployVerification {
    function verify(DGSetupDeployArtifacts.Context memory deployArtifact) internal view {
        checkImmutables(deployArtifact);
        checkContractsConfiguration({deployArtifact: deployArtifact, expectedProposalsCount: 0});
    }

    function verify(
        DGSetupDeployArtifacts.Context memory deployArtifact,
        uint256 expectedProposalsCount
    ) internal view {
        checkImmutables(deployArtifact);
        checkContractsConfiguration(deployArtifact, expectedProposalsCount);
    }

    function checkImmutables(DGSetupDeployArtifacts.Context memory deployArtifact) internal view {
        checkEmergencyProtectedTimelockImmutables(
            deployArtifact.deployedContracts, deployArtifact.deployConfig.timelock.sanityCheckParams
        );
        checkEmergencyActivationCommittee(deployArtifact.deployConfig);
        checkEmergencyExecutionCommittee(deployArtifact.deployConfig);
        checkTimelockedGovernance(deployArtifact.deployedContracts, deployArtifact.deployConfig);
        checkResealManager(deployArtifact.deployedContracts);
        checkDualGovernanceAndEscrowImmutables(deployArtifact.deployedContracts, deployArtifact.deployConfig);
    }

    function checkContractsConfiguration(
        DGSetupDeployArtifacts.Context memory deployArtifact,
        uint256 expectedProposalsCount
    ) internal view {
        checkAdminExecutor(deployArtifact.deployedContracts.adminExecutor, deployArtifact.deployedContracts.timelock);
        checkEmergencyProtectedTimelockConfiguration(
            deployArtifact.deployedContracts, deployArtifact.deployConfig.timelock, expectedProposalsCount
        );
        checkDualGovernanceConfiguration(deployArtifact.deployedContracts, deployArtifact.deployConfig);
        checkTiebreaker(deployArtifact.deployedContracts, deployArtifact.deployConfig.tiebreaker);

        checkResealCommittee(deployArtifact.deployConfig);
    }

    function checkAdminExecutor(Executor executor, IEmergencyProtectedTimelock timelock) internal view {
        require(executor.owner() == address(timelock), "AdminExecutor owner != EmergencyProtectedTimelock");
    }

    function checkEmergencyProtectedTimelockImmutables(
        DGSetupDeployedContracts.Context memory deployedContracts,
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams
    ) internal view {
        IEmergencyProtectedTimelock timelockInstance = deployedContracts.timelock;
        require(
            EmergencyProtectedTimelock(address(timelockInstance)).MIN_EXECUTION_DELAY() // TODO: property MIN_EXECUTION_DELAY is missing in interface IEmergencyProtectedTimelock
                == sanityCheckParams.minExecutionDelay,
            "Incorrect parameter MIN_EXECUTION_DELAY"
        );
        require(
            timelockInstance.MAX_AFTER_SUBMIT_DELAY() == sanityCheckParams.maxAfterSubmitDelay,
            "Incorrect parameter MAX_AFTER_SUBMIT_DELAY"
        );
        require(
            timelockInstance.MAX_AFTER_SCHEDULE_DELAY() == sanityCheckParams.maxAfterScheduleDelay,
            "Incorrect parameter MAX_AFTER_SCHEDULE_DELAY"
        );
        require(
            timelockInstance.MAX_EMERGENCY_MODE_DURATION() == sanityCheckParams.maxEmergencyModeDuration,
            "Incorrect parameter MAX_EMERGENCY_MODE_DURATION"
        );
        require(
            timelockInstance.MAX_EMERGENCY_PROTECTION_DURATION() == sanityCheckParams.maxEmergencyProtectionDuration,
            "Incorrect parameter MAX_EMERGENCY_PROTECTION_DURATION"
        );
    }

    function checkEmergencyProtectedTimelockConfiguration(
        DGSetupDeployedContracts.Context memory contracts,
        TimelockContractDeployConfig.Context memory timelockConfig,
        uint256 expectedProposalsCount
    ) internal view {
        IEmergencyProtectedTimelock timelockInstance = contracts.timelock;

        require(
            timelockInstance.getAdminExecutor() == address(contracts.adminExecutor),
            "Incorrect adminExecutor address in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.getEmergencyActivationCommittee() == timelockConfig.emergencyActivationCommittee,
            "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.getEmergencyExecutionCommittee() == timelockConfig.emergencyExecutionCommittee,
            "Incorrect emergencyExecutionCommittee address in EmergencyProtectedTimelock"
        );

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
            timelockInstance.getEmergencyProtectionDetails();

        require(
            details.emergencyProtectionEndsAfter == timelockConfig.emergencyProtectionEndDate,
            "Incorrect value for emergencyProtectionEndsAfter"
        );
        require(
            details.emergencyModeDuration == timelockConfig.emergencyModeDuration,
            "Incorrect value for emergencyModeDuration"
        );

        require(
            details.emergencyModeEndsAfter == Timestamps.ZERO,
            "Incorrect value for emergencyModeEndsAfter (Emergency mode is activated)"
        );

        require(
            timelockInstance.getEmergencyGovernance() == address(contracts.emergencyGovernance),
            "Incorrect emergencyGovernance address in EmergencyProtectedTimelock"
        );

        require(
            timelockInstance.getAfterSubmitDelay() == timelockConfig.afterSubmitDelay,
            "Incorrect parameter AFTER_SUBMIT_DELAY"
        );
        require(
            timelockInstance.getAfterScheduleDelay() == timelockConfig.afterScheduleDelay,
            "Incorrect parameter AFTER_SCHEDULE_DELAY"
        );
        require(
            timelockInstance.getGovernance() == address(contracts.dualGovernance),
            "Incorrect governance address in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.isEmergencyProtectionEnabled()
                == (details.emergencyProtectionEndsAfter >= Timestamps.now()),
            "EmergencyProtection is Disabled in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.isEmergencyModeActive() == false, "EmergencyMode is Active in EmergencyProtectedTimelock"
        );

        require(
            timelockInstance.getProposalsCount() == expectedProposalsCount,
            "Unexpected ProposalsCount in EmergencyProtectedTimelock"
        );
    }

    function checkEmergencyActivationCommittee(DGSetupDeployConfig.Context memory dgDeployConfig) internal pure {
        require(
            dgDeployConfig.timelock.emergencyActivationCommittee != address(0), "Incorrect emergencyActivationCommittee"
        );
    }

    function checkEmergencyExecutionCommittee(DGSetupDeployConfig.Context memory dgDeployConfig) internal pure {
        require(
            dgDeployConfig.timelock.emergencyExecutionCommittee != address(0), "Incorrect emergencyExecutionCommittee"
        );
    }

    function checkTimelockedGovernance(
        DGSetupDeployedContracts.Context memory contracts,
        DGSetupDeployConfig.Context memory dgDeployConfig
    ) internal view {
        TimelockedGovernance emergencyTimelockedGovernance = contracts.emergencyGovernance;
        require(
            emergencyTimelockedGovernance.GOVERNANCE() == dgDeployConfig.timelock.emergencyGovernanceProposer,
            "TimelockedGovernance governance != Lido voting"
        );
        require(
            address(emergencyTimelockedGovernance.TIMELOCK()) == address(contracts.timelock),
            "Incorrect address for timelock in TimelockedGovernance"
        );
    }

    function checkResealManager(DGSetupDeployedContracts.Context memory contracts) internal view {
        require(
            address(contracts.resealManager.EMERGENCY_PROTECTED_TIMELOCK()) == address(contracts.timelock),
            "Incorrect address for EMERGENCY_PROTECTED_TIMELOCK in ResealManager"
        );
    }

    function checkDualGovernanceConfiguration(
        DGSetupDeployedContracts.Context memory contracts,
        DGSetupDeployConfig.Context memory dgDeployConfig
    ) internal view {
        IDualGovernance dg = contracts.dualGovernance;
        require(
            address(dg.getResealManager()) == address(contracts.resealManager),
            "Incorrect address for resealManager in DualGovernance"
        );
        require(
            address(dg.getResealCommittee()) == address(dgDeployConfig.dualGovernance.resealCommittee),
            "Incorrect address for resealCommittee in DualGovernance"
        );

        ISignallingEscrow vetoSignallingEscrow = ISignallingEscrow(dg.getVetoSignallingEscrow());
        require(
            vetoSignallingEscrow.getEscrowState() == EscrowState.SignallingEscrow,
            "Incorrect state of VetoSignallingEscrow"
        );
        require(
            vetoSignallingEscrow.getRageQuitSupport().toUint256() == 0,
            "Incorrect rageQuitSupport value in VetoSignallingEscrow"
        );
        require(
            vetoSignallingEscrow.getMinAssetsLockDuration()
                == dgDeployConfig.dualGovernanceConfigProvider.minAssetsLockDuration,
            "Incorrect value of minAssetsLockDuration in VetoSignallingEscrow"
        );

        ISignallingEscrow.SignallingEscrowDetails memory signallingEscrowDetails =
            vetoSignallingEscrow.getSignallingEscrowDetails();

        require(
            signallingEscrowDetails.totalStETHClaimedETH.toUint256() == 0,
            "Incorrect SignallingEscrowDetails.totalStETHClaimedETH"
        );
        require(
            signallingEscrowDetails.totalStETHLockedShares.toUint256() == 0,
            "Incorrect SignallingEscrowDetails.totalStETHLockedShares"
        );
        require(
            signallingEscrowDetails.totalUnstETHUnfinalizedShares.toUint256() == 0,
            "Incorrect SignallingEscrowDetails.totalUnstETHUnfinalizedShares"
        );
        require(
            signallingEscrowDetails.totalUnstETHFinalizedETH.toUint256() == 0,
            "Incorrect SignallingEscrowDetails.totalUnstETHFinalizedETH"
        );

        require(
            dg.isProposer(address(dgDeployConfig.dualGovernance.adminProposer)) == true,
            "Lido voting is not set as a proposer"
        );
        require(dg.isExecutor(address(contracts.adminExecutor)) == true, "adminExecutor is not set as an executor");
        require(dg.getRageQuitEscrow() == address(0), "DG is in incorrect state - RageQuit started");

        IDualGovernance.StateDetails memory stateDetails = dg.getStateDetails();
        require(
            stateDetails.persistedStateEnteredAt <= Timestamps.now(), "Incorrect DualGovernance persistedStateEnteredAt"
        );
        require(
            stateDetails.vetoSignallingReactivationTime == Timestamps.ZERO,
            "Incorrect DualGovernance state vetoSignallingReactivationTime"
        );
        require(
            stateDetails.normalOrVetoCooldownExitedAt == Timestamps.ZERO,
            "Incorrect DualGovernance state normalOrVetoCooldownExitedAt"
        );
        require(stateDetails.rageQuitRound == 0, "Incorrect DualGovernance state rageQuitRound");
        require(
            stateDetails.vetoSignallingDuration == Durations.ZERO,
            "Incorrect DualGovernance state vetoSignallingDuration"
        );

        ITiebreaker.TiebreakerDetails memory ts = dg.getTiebreakerDetails();
        require(
            ts.tiebreakerActivationTimeout == dgDeployConfig.dualGovernance.tiebreakerActivationTimeout,
            "Incorrect parameter TIEBREAKER_CONFIG.ACTIVATION_TIMEOUT"
        );
        require(
            ts.tiebreakerCommittee == address(contracts.tiebreakerCoreCommittee), "Incorrect tiebreakerCoreCommittee"
        );
        require(
            ts.sealableWithdrawalBlockers.length == dgDeployConfig.dualGovernance.sealableWithdrawalBlockers.length,
            "Incorrect amount of sealableWithdrawalBlockers"
        );

        for (uint256 i = 0; i < dgDeployConfig.dualGovernance.sealableWithdrawalBlockers.length; ++i) {
            require(
                ts.sealableWithdrawalBlockers[i] == dgDeployConfig.dualGovernance.sealableWithdrawalBlockers[i],
                "Incorrect sealableWithdrawalBlocker"
            );
        }
    }

    function checkDualGovernanceAndEscrowImmutables(
        DGSetupDeployedContracts.Context memory contracts,
        DGSetupDeployConfig.Context memory dgDeployConfig
    ) internal view {
        IDualGovernance dg = contracts.dualGovernance;
        require(
            address(dg.TIMELOCK()) == address(contracts.timelock), "Incorrect address for timelock in DualGovernance"
        );
        require(
            dg.MIN_TIEBREAKER_ACTIVATION_TIMEOUT()
                == dgDeployConfig.dualGovernance.sanityCheckParams.minTiebreakerActivationTimeout,
            "Incorrect parameter TIEBREAKER_CONFIG.MIN_ACTIVATION_TIMEOUT"
        );
        require(
            dg.MAX_TIEBREAKER_ACTIVATION_TIMEOUT()
                == dgDeployConfig.dualGovernance.sanityCheckParams.maxTiebreakerActivationTimeout,
            "Incorrect parameter TIEBREAKER_CONFIG.MAX_ACTIVATION_TIMEOUT"
        );
        require(
            dg.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT()
                == dgDeployConfig.dualGovernance.sanityCheckParams.maxSealableWithdrawalBlockersCount,
            "Incorrect parameter MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT"
        );

        Escrow escrowTemplate = Escrow(payable(address(IEscrowBase(dg.getVetoSignallingEscrow()).ESCROW_MASTER_COPY())));
        require(escrowTemplate.DUAL_GOVERNANCE() == dg, "Escrow has incorrect DualGovernance address");
        require(
            escrowTemplate.ST_ETH() == dgDeployConfig.dualGovernance.signallingTokens.stETH,
            "Escrow has incorrect StETH address"
        );
        require(
            escrowTemplate.WST_ETH() == dgDeployConfig.dualGovernance.signallingTokens.wstETH,
            "Escrow has incorrect WstETH address"
        );
        require(
            escrowTemplate.WITHDRAWAL_QUEUE() == dgDeployConfig.dualGovernance.signallingTokens.withdrawalQueue,
            "Escrow has incorrect WithdrawalQueue address"
        );
        require(
            escrowTemplate.MIN_WITHDRAWALS_BATCH_SIZE()
                == dgDeployConfig.dualGovernance.sanityCheckParams.minWithdrawalsBatchSize,
            "Incorrect parameter MIN_WITHDRAWALS_BATCH_SIZE"
        );
        require(
            escrowTemplate.MAX_MIN_ASSETS_LOCK_DURATION()
                == dgDeployConfig.dualGovernance.sanityCheckParams.maxMinAssetsLockDuration,
            "Incorrect parameter MAX_MIN_ASSETS_LOCK_DURATION"
        );

        DualGovernanceConfig.Context memory dgConfig = dg.getConfigProvider().getDualGovernanceConfig();
        DualGovernanceConfig.Context memory dgConfigProviderConfig = dgDeployConfig.dualGovernanceConfigProvider;
        require(
            dgConfig.firstSealRageQuitSupport == dgConfigProviderConfig.firstSealRageQuitSupport,
            "Incorrect parameter FIRST_SEAL_RAGE_QUIT_SUPPORT"
        );

        require(
            dgConfig.secondSealRageQuitSupport == dgConfigProviderConfig.secondSealRageQuitSupport,
            "Incorrect parameter SECOND_SEAL_RAGE_QUIT_SUPPORT"
        );
        require(
            dgConfig.minAssetsLockDuration == dgConfigProviderConfig.minAssetsLockDuration,
            "Incorrect parameter MIN_ASSETS_LOCK_DURATION"
        );
        require(
            dgConfig.vetoSignallingMinDuration == dgConfigProviderConfig.vetoSignallingMinDuration,
            "Incorrect parameter VETO_SIGNALLING_MIN_DURATION"
        );
        require(
            dgConfig.vetoSignallingMaxDuration == dgConfigProviderConfig.vetoSignallingMaxDuration,
            "Incorrect parameter VETO_SIGNALLING_MAX_DURATION"
        );
        require(
            dgConfig.vetoSignallingMinActiveDuration == dgConfigProviderConfig.vetoSignallingMinActiveDuration,
            "Incorrect parameter VETO_SIGNALLING_MIN_ACTIVE_DURATION"
        );
        require(
            dgConfig.vetoSignallingDeactivationMaxDuration
                == dgConfigProviderConfig.vetoSignallingDeactivationMaxDuration,
            "Incorrect parameter VETO_SIGNALLING_DEACTIVATION_MAX_DURATION"
        );
        require(
            dgConfig.vetoCooldownDuration == dgConfigProviderConfig.vetoCooldownDuration,
            "Incorrect parameter VETO_COOLDOWN_DURATION"
        );
        require(
            dgConfig.rageQuitExtensionPeriodDuration == dgConfigProviderConfig.rageQuitExtensionPeriodDuration,
            "Incorrect parameter RAGE_QUIT_EXTENSION_PERIOD_DURATION"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsMinDelay == dgConfigProviderConfig.rageQuitEthWithdrawalsMinDelay,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsMaxDelay == dgConfigProviderConfig.rageQuitEthWithdrawalsMaxDelay,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsDelayGrowth == dgConfigProviderConfig.rageQuitEthWithdrawalsDelayGrowth,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH"
        );
    }

    function checkTiebreaker(
        DGSetupDeployedContracts.Context memory contracts,
        TiebreakerDeployConfig.Context memory tiebreakerConfig
    ) internal view {
        TiebreakerCoreCommittee tcc = contracts.tiebreakerCoreCommittee;
        require(tcc.owner() == address(contracts.adminExecutor), "TiebreakerCoreCommittee owner != adminExecutor");
        require(
            tcc.getTimelockDuration() == tiebreakerConfig.executionDelay,
            "Incorrect parameter TIEBREAKER_CONFIG.EXECUTION_DELAY"
        );

        for (uint256 i = 0; i < contracts.tiebreakerSubCommittees.length; ++i) {
            require(
                tcc.isMember(address(contracts.tiebreakerSubCommittees[i])) == true,
                "Incorrect member of TiebreakerCoreCommittee"
            );
        }

        require(tcc.getQuorum() == tiebreakerConfig.quorum, "Incorrect quorum in TiebreakerCoreCommittee");
        require(tcc.getProposalsLength() == 0, "Incorrect proposals count in TiebreakerCoreCommittee");

        // Check TiebreakerSubCommittees
        for (uint256 i = 0; i < contracts.tiebreakerSubCommittees.length; i++) {
            require(
                contracts.tiebreakerSubCommittees[i].owner() == address(contracts.adminExecutor),
                "TiebreakerSubCommittee owner != adminExecutor"
            );
            require(
                contracts.tiebreakerSubCommittees[i].getTimelockDuration() == Durations.from(0),
                "TiebreakerSubCommittee timelock should be 0"
            );

            address[] memory members = tiebreakerConfig.committees[i].members;

            for (uint256 j = 0; j < members.length; ++j) {
                require(
                    contracts.tiebreakerSubCommittees[i].isMember(members[j]) == true,
                    "Incorrect member of TiebreakerSubCommittee"
                );
            }
            require(
                contracts.tiebreakerSubCommittees[i].getQuorum() == tiebreakerConfig.committees[i].quorum,
                "Incorrect quorum in TiebreakerSubCommittee"
            );
            require(
                contracts.tiebreakerSubCommittees[i].getProposalsLength() == 0,
                "Incorrect proposals count in TiebreakerSubCommittee"
            );
        }
    }

    function checkResealCommittee(DGSetupDeployConfig.Context memory dgDeployConfig) internal pure {
        require(dgDeployConfig.dualGovernance.resealCommittee != address(0), "Incorrect resealCommittee");
    }
}
