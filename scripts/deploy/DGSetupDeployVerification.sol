// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable custom-errors, reason-string */

import {State as EscrowState} from "contracts/libraries/EscrowState.sol";
import {IEscrowBase} from "contracts/interfaces/IEscrowBase.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";

import {
    DGSetupDeployedContracts,
    DGSetupDeployConfig,
    TiebreakerContractDeployConfig,
    DualGovernanceContractDeployConfig,
    TiebreakerCommitteeDeployConfig,
    TimelockContractDeployConfig
} from "scripts/utils/contracts-deployment.sol";

import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";

import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Executor} from "contracts/Executor.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

library DGSetupDeployVerification {
    error InvalidDuration(string name, Duration actual, Duration expected);
    error InvalidAddress(string name, address actual, address expected);

    function verify(
        DGSetupDeployedContracts.Context memory contracts,
        DGSetupDeployConfig.Context memory config,
        bool onchainVotingCheck
    ) internal view {
        checkImmutables(contracts, config);
        checkContractsConfiguration(contracts, config, onchainVotingCheck);
    }

    function checkImmutables(
        DGSetupDeployedContracts.Context memory contracts,
        DGSetupDeployConfig.Context memory config
    ) internal view {
        checkEmergencyProtectedTimelockImmutables(contracts, config.timelock);
        checkTimelockedGovernance(contracts, config.timelock);
        checkResealManager(contracts);
        checkDualGovernanceAndEscrowImmutables(contracts, config);
        checkDualGovernanceConfig({
            actual: contracts.dualGovernance.getConfigProvider().getDualGovernanceConfig(),
            expected: config.dualGovernanceConfigProvider
        });
    }

    function checkContractsConfiguration(
        DGSetupDeployedContracts.Context memory contracts,
        DGSetupDeployConfig.Context memory config,
        bool onchainVotingCheck
    ) internal view {
        checkAdminExecutor(contracts.adminExecutor, contracts.timelock);
        checkEmergencyProtectedTimelockConfiguration(contracts, config.timelock, onchainVotingCheck);
        checkDualGovernanceConfiguration(contracts, config);
        checkTiebreakerCoreCommittee(contracts, config.tiebreaker);
    }

    function checkAdminExecutor(Executor executor, EmergencyProtectedTimelock timelock) internal view {
        require(executor.owner() == address(timelock), "AdminExecutor owner != EmergencyProtectedTimelock");
    }

    function checkEmergencyProtectedTimelockImmutables(
        DGSetupDeployedContracts.Context memory contracts,
        TimelockContractDeployConfig.Context memory config
    ) internal view {
        EmergencyProtectedTimelock timelock = contracts.timelock;
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams = config.sanityCheckParams;

        require(
            timelock.MIN_EXECUTION_DELAY() == sanityCheckParams.minExecutionDelay,
            "Incorrect parameter MIN_EXECUTION_DELAY"
        );
        require(
            timelock.MAX_AFTER_SUBMIT_DELAY() == sanityCheckParams.maxAfterSubmitDelay,
            "Incorrect parameter MAX_AFTER_SUBMIT_DELAY"
        );
        require(
            timelock.MAX_AFTER_SCHEDULE_DELAY() == sanityCheckParams.maxAfterScheduleDelay,
            "Incorrect parameter MAX_AFTER_SCHEDULE_DELAY"
        );
        require(
            timelock.MAX_EMERGENCY_MODE_DURATION() == sanityCheckParams.maxEmergencyModeDuration,
            "Incorrect parameter MAX_EMERGENCY_MODE_DURATION"
        );
        require(
            timelock.MAX_EMERGENCY_PROTECTION_DURATION() == sanityCheckParams.maxEmergencyProtectionDuration,
            "Incorrect parameter MAX_EMERGENCY_PROTECTION_DURATION"
        );
    }

    function checkEmergencyProtectedTimelockConfiguration(
        DGSetupDeployedContracts.Context memory contracts,
        TimelockContractDeployConfig.Context memory config,
        bool onchainVotingCheck
    ) internal view {
        EmergencyProtectedTimelock timelock = contracts.timelock;
        require(
            timelock.getAdminExecutor() == address(contracts.adminExecutor),
            "Incorrect adminExecutor address in EmergencyProtectedTimelock"
        );
        require(
            timelock.getEmergencyActivationCommittee() == config.emergencyActivationCommittee,
            "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
        );
        require(
            timelock.getEmergencyExecutionCommittee() == config.emergencyExecutionCommittee,
            "Incorrect emergencyExecutionCommittee address in EmergencyProtectedTimelock"
        );

        EmergencyProtectedTimelock.EmergencyProtectionDetails memory details = timelock.getEmergencyProtectionDetails();
        require(
            details.emergencyProtectionEndsAfter == config.emergencyProtectionEndDate,
            "Incorrect value for emergencyProtectionEndsAfter"
        );
        require(
            details.emergencyModeDuration == config.emergencyModeDuration, "Incorrect value for emergencyModeDuration"
        );

        if (!onchainVotingCheck) {
            require(
                details.emergencyModeEndsAfter == Timestamps.ZERO,
                "Incorrect value for emergencyModeEndsAfter (Emergency mode is activated)"
            );
        }

        if (onchainVotingCheck) {
            require(
                timelock.getEmergencyGovernance() == address(contracts.emergencyGovernance),
                "Incorrect emergencyGovernance address in EmergencyProtectedTimelock"
            );
        }

        require(timelock.getAfterSubmitDelay() == config.afterSubmitDelay, "Incorrect parameter AFTER_SUBMIT_DELAY");
        require(
            timelock.getAfterScheduleDelay() == config.afterScheduleDelay, "Incorrect parameter AFTER_SCHEDULE_DELAY"
        );
        require(
            timelock.getGovernance() == address(contracts.dualGovernance),
            "Incorrect governance address in EmergencyProtectedTimelock"
        );
        require(
            timelock.isEmergencyProtectionEnabled() == (details.emergencyProtectionEndsAfter >= Timestamps.now()),
            "EmergencyProtection is Disabled in EmergencyProtectedTimelock"
        );
        require(timelock.isEmergencyModeActive() == false, "EmergencyMode is Active in EmergencyProtectedTimelock");

        if (onchainVotingCheck) {
            require(timelock.getProposalsCount() == 1, "ProposalsCount != 1 in EmergencyProtectedTimelock");
        } else {
            require(timelock.getProposalsCount() == 0, "ProposalsCount > 1 in EmergencyProtectedTimelock");
        }
    }

    function checkTimelockedGovernance(
        DGSetupDeployedContracts.Context memory contracts,
        TimelockContractDeployConfig.Context memory config
    ) internal view {
        TimelockedGovernance emergencyGovernance = contracts.emergencyGovernance;
        require(
            emergencyGovernance.GOVERNANCE() == config.emergencyGovernanceProposer,
            "TimelockedGovernance governance != Lido voting"
        );
        require(
            address(emergencyGovernance.TIMELOCK()) == address(contracts.timelock),
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
        DGSetupDeployConfig.Context memory config
    ) internal view {
        DualGovernance dg = contracts.dualGovernance;

        TiebreakerContractDeployConfig.Context memory tbConfig = config.tiebreaker;
        DualGovernanceContractDeployConfig.Context memory dgConfig = config.dualGovernance;

        require(
            address(dg.getResealManager()) == address(contracts.resealManager),
            "Incorrect address for resealManager in DualGovernance"
        );
        require(
            address(dg.getResealCommittee()) == address(dgConfig.resealCommittee),
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
            vetoSignallingEscrow.getMinAssetsLockDuration() == config.dualGovernanceConfigProvider.minAssetsLockDuration,
            "Incorrect value of minAssetsLockDuration in VetoSignallingEscrow"
        );

        ISignallingEscrow.SignallingEscrowDetails memory signallingEscrowDetails =
            vetoSignallingEscrow.getSignallingEscrowDetails();

        require(
            signallingEscrowDetails.totalStETHClaimedETH.toUint256() == 0,
            "Incorrect SignallingEscrowDetails.totalStETHClaimedETH"
        );
        // TODO: Double check if we need this assertion
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

        // require(dg.getPersistedState() == State.Normal, "Incorrect DualGovernance persisted state");
        // require(dg.getEffectiveState() == State.Normal, "Incorrect DualGovernance effective state");
        // require(dg.getProposers().length == 1, "Incorrect amount of proposers");
        require(
            dg.isProposer(address(config.dualGovernance.adminProposer)) == true, "Lido voting is not set as a proposer"
        );
        require(dg.isExecutor(address(contracts.adminExecutor)) == true, "adminExecutor is not set as an executor");
        // require(dg.canSubmitProposal() == true, "DG is in incorrect state - can't submit proposal");
        require(dg.getRageQuitEscrow() == address(0), "DG is in incorrect state - RageQuit started");

        IDualGovernance.StateDetails memory stateDetails = dg.getStateDetails();
        // require(stateDetails.effectiveState == State.Normal, "Incorrect DualGovernance effectiveState");
        // require(stateDetails.persistedState == State.Normal, "Incorrect DualGovernance persistedState");
        require(
            stateDetails.persistedStateEnteredAt <= Timestamps.now(), "Incorrect DualGovernance persistedStateEnteredAt"
        );
        /* require(
            stateDetails.vetoSignallingActivatedAt == Timestamps.ZERO,
            "Incorrect DualGovernance state vetoSignallingActivatedAt"
        ); */
        require(
            stateDetails.vetoSignallingReactivationTime == Timestamps.ZERO,
            "Incorrect DualGovernance state vetoSignallingReactivationTime"
        );
        require(
            stateDetails.normalOrVetoCooldownExitedAt == Timestamps.ZERO,
            "Incorrect DualGovernance state normalOrVetoCooldownExitedAt"
        );
        require(stateDetails.rageQuitRound == 0, "Incorrect DualGovernance state rageQuitRound");
        // TODO: Double check if we need this assertion.
        require(
            stateDetails.vetoSignallingDuration == Durations.ZERO,
            "Incorrect DualGovernance state vetoSignallingDuration"
        );

        ITiebreaker.TiebreakerDetails memory ts = dg.getTiebreakerDetails();
        require(
            ts.tiebreakerActivationTimeout == dgConfig.tiebreakerActivationTimeout,
            "Incorrect parameter TIEBREAKER_CONFIG.ACTIVATION_TIMEOUT"
        );
        require(
            ts.tiebreakerCommittee == address(contracts.tiebreakerCoreCommittee), "Incorrect tiebreakerCoreCommittee"
        );
        require(
            ts.sealableWithdrawalBlockers.length == dgConfig.sealableWithdrawalBlockers.length,
            "Incorrect amount of sealableWithdrawalBlockers"
        );

        for (uint256 i = 0; i < dgConfig.sealableWithdrawalBlockers.length; ++i) {
            require(
                ts.sealableWithdrawalBlockers[i] == dgConfig.sealableWithdrawalBlockers[i],
                "Incorrect sealableWithdrawalBlocker"
            );
        }
    }

    function checkDualGovernanceAndEscrowImmutables(
        DGSetupDeployedContracts.Context memory contracts,
        DGSetupDeployConfig.Context memory config
    ) internal view {
        IDualGovernance dg = contracts.dualGovernance;

        TiebreakerContractDeployConfig.Context memory tbConfig = config.tiebreaker;
        DualGovernanceContractDeployConfig.Context memory dgConfig = config.dualGovernance;

        require(
            address(dg.TIMELOCK()) == address(contracts.timelock), "Incorrect address for timelock in DualGovernance"
        );
        require(
            dg.MIN_TIEBREAKER_ACTIVATION_TIMEOUT() == dgConfig.sanityCheckParams.minTiebreakerActivationTimeout,
            "Incorrect parameter TIEBREAKER_CONFIG.MIN_ACTIVATION_TIMEOUT"
        );
        require(
            dg.MAX_TIEBREAKER_ACTIVATION_TIMEOUT() == dgConfig.sanityCheckParams.maxTiebreakerActivationTimeout,
            "Incorrect parameter TIEBREAKER_CONFIG.MAX_ACTIVATION_TIMEOUT"
        );
        require(
            dg.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT() == dgConfig.sanityCheckParams.maxSealableWithdrawalBlockersCount,
            "Incorrect parameter MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT"
        );

        Escrow escrowTemplate = Escrow(payable(address(IEscrowBase(dg.getVetoSignallingEscrow()).ESCROW_MASTER_COPY())));
        require(escrowTemplate.DUAL_GOVERNANCE() == dg, "Escrow has incorrect DualGovernance address");
        require(escrowTemplate.ST_ETH() == dgConfig.signallingTokens.stETH, "Escrow has incorrect StETH address");
        require(escrowTemplate.WST_ETH() == dgConfig.signallingTokens.wstETH, "Escrow has incorrect WstETH address");
        require(
            escrowTemplate.WITHDRAWAL_QUEUE() == dgConfig.signallingTokens.withdrawalQueue,
            "Escrow has incorrect WithdrawalQueue address"
        );
        require(
            escrowTemplate.MIN_WITHDRAWALS_BATCH_SIZE() == dgConfig.sanityCheckParams.minWithdrawalsBatchSize,
            "Incorrect parameter MIN_WITHDRAWALS_BATCH_SIZE"
        );
        require(
            escrowTemplate.MAX_MIN_ASSETS_LOCK_DURATION() == dgConfig.sanityCheckParams.maxMinAssetsLockDuration,
            "Incorrect parameter MAX_MIN_ASSETS_LOCK_DURATION"
        );
    }

    function checkDualGovernanceConfig(
        DualGovernanceConfig.Context memory actual,
        DualGovernanceConfig.Context memory expected
    ) internal view {
        require(
            actual.firstSealRageQuitSupport == expected.firstSealRageQuitSupport,
            "Incorrect parameter FIRST_SEAL_RAGE_QUIT_SUPPORT"
        );
        require(
            actual.secondSealRageQuitSupport == expected.secondSealRageQuitSupport,
            "Incorrect parameter SECOND_SEAL_RAGE_QUIT_SUPPORT"
        );
        require(
            actual.minAssetsLockDuration == expected.minAssetsLockDuration,
            "Incorrect parameter MIN_ASSETS_LOCK_DURATION"
        );
        require(
            actual.vetoSignallingMinDuration == expected.vetoSignallingMinDuration,
            "Incorrect parameter VETO_SIGNALLING_MIN_DURATION"
        );
        require(
            actual.vetoSignallingMaxDuration == expected.vetoSignallingMaxDuration,
            "Incorrect parameter VETO_SIGNALLING_MAX_DURATION"
        );
        require(
            actual.vetoSignallingMinActiveDuration == expected.vetoSignallingMinActiveDuration,
            "Incorrect parameter VETO_SIGNALLING_MIN_ACTIVE_DURATION"
        );
        require(
            actual.vetoSignallingDeactivationMaxDuration == expected.vetoSignallingDeactivationMaxDuration,
            "Incorrect parameter VETO_SIGNALLING_DEACTIVATION_MAX_DURATION"
        );
        require(
            actual.vetoCooldownDuration == expected.vetoCooldownDuration, "Incorrect parameter VETO_COOLDOWN_DURATION"
        );
        require(
            actual.rageQuitExtensionPeriodDuration == expected.rageQuitExtensionPeriodDuration,
            "Incorrect parameter RAGE_QUIT_EXTENSION_PERIOD_DURATION"
        );
        require(
            actual.rageQuitEthWithdrawalsMinDelay == expected.rageQuitEthWithdrawalsMinDelay,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY"
        );
        require(
            actual.rageQuitEthWithdrawalsMaxDelay == expected.rageQuitEthWithdrawalsMaxDelay,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY"
        );
        require(
            actual.rageQuitEthWithdrawalsDelayGrowth == expected.rageQuitEthWithdrawalsDelayGrowth,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH"
        );
    }

    function checkTiebreakerCoreCommittee(
        DGSetupDeployedContracts.Context memory contracts,
        TiebreakerContractDeployConfig.Context memory config
    ) internal view {
        TiebreakerCoreCommittee tcc = contracts.tiebreakerCoreCommittee;

        require(tcc.owner() == address(contracts.adminExecutor), "TiebreakerCoreCommittee owner != adminExecutor");

        require(
            tcc.getTimelockDuration() == config.executionDelay, "Incorrect parameter TIEBREAKER_CONFIG.EXECUTION_DELAY"
        );

        uint256 membersCount = config.committeesCount;

        address[] memory tccMembers = tcc.getMembers();

        require(tccMembers.length == config.committeesCount, "Incorrect Tiebreaker sub committees count");

        for (uint256 i = 0; i < membersCount; ++i) {
            require(
                tcc.isMember(address(contracts.tiebreakerSubCommittees[i])) == true,
                "Sub committee is not a member of TiebreakerCoreCommittee"
            );
            checkTiebreakerSubCommittee(contracts, config.committees[i], TiebreakerSubCommittee(tccMembers[i]));
        }

        require(tcc.getQuorum() == config.quorum, "Incorrect quorum in TiebreakerCoreCommittee");
        require(tcc.getProposalsLength() == 0, "Incorrect proposals count in TiebreakerCoreCommittee");
    }

    function checkTiebreakerSubCommittee(
        DGSetupDeployedContracts.Context memory contracts,
        TiebreakerCommitteeDeployConfig memory dgTiebreakerSubCommitteeDeployConfig,
        TiebreakerSubCommittee tsc
    ) internal view {
        require(tsc.owner() == address(contracts.adminExecutor), "TiebreakerSubCommittee owner != adminExecutor");
        require(tsc.getTimelockDuration() == Durations.from(0), "TiebreakerSubCommittee timelock should be 0");

        address[] memory members = dgTiebreakerSubCommitteeDeployConfig.members;

        for (uint256 i = 0; i < members.length; ++i) {
            require(tsc.isMember(members[i]) == true, "Incorrect member of TiebreakerSubCommittee");
        }
        require(
            tsc.getQuorum() == dgTiebreakerSubCommitteeDeployConfig.quorum, "Incorrect quorum in TiebreakerSubCommittee"
        );
        require(tsc.getProposalsLength() == 0, "Incorrect proposals count in TiebreakerSubCommittee");
    }
}
