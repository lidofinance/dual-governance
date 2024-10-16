// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations} from "contracts/types/Duration.sol";
import {Executor} from "contracts/Executor.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {Escrow} from "contracts/Escrow.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {State} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {DeployConfig, LidoContracts, getSubCommitteeData} from "./Config.sol";

library DeployVerification {
    struct DeployedAddresses {
        address payable adminExecutor;
        address timelock;
        address emergencyGovernance;
        address resealManager;
        address dualGovernance;
        address tiebreakerCoreCommittee;
        address[] tiebreakerSubCommittees;
    }

    function verify(
        DeployedAddresses memory res,
        DeployConfig memory dgDeployConfig,
        LidoContracts memory lidoAddresses
    ) internal view {
        checkAdminExecutor(res.adminExecutor, res.timelock);
        checkTimelock(res, dgDeployConfig);
        checkEmergencyActivationCommittee(dgDeployConfig);
        checkEmergencyExecutionCommittee(dgDeployConfig);
        checkTimelockedGovernance(res, lidoAddresses);
        checkResealManager(res);
        checkDualGovernance(res, dgDeployConfig, lidoAddresses);
        checkTiebreakerCoreCommittee(res, dgDeployConfig);

        for (uint256 i = 0; i < dgDeployConfig.TIEBREAKER_SUB_COMMITTEES_COUNT; ++i) {
            checkTiebreakerSubCommittee(res, dgDeployConfig, i);
        }

        checkResealCommittee(dgDeployConfig);
    }

    function checkAdminExecutor(address payable executor, address timelock) internal view {
        require(Executor(executor).owner() == timelock, "AdminExecutor owner != EmergencyProtectedTimelock");
    }

    function checkTimelock(DeployedAddresses memory res, DeployConfig memory dgDeployConfig) internal view {
        EmergencyProtectedTimelock timelockInstance = EmergencyProtectedTimelock(res.timelock);
        require(
            timelockInstance.getAdminExecutor() == res.adminExecutor,
            "Incorrect adminExecutor address in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.MAX_AFTER_SUBMIT_DELAY() == dgDeployConfig.MAX_AFTER_SUBMIT_DELAY,
            "Incorrect parameter MAX_AFTER_SUBMIT_DELAY"
        );
        require(
            timelockInstance.MAX_AFTER_SCHEDULE_DELAY() == dgDeployConfig.MAX_AFTER_SCHEDULE_DELAY,
            "Incorrect parameter MAX_AFTER_SCHEDULE_DELAY"
        );
        require(
            timelockInstance.MAX_EMERGENCY_MODE_DURATION() == dgDeployConfig.MAX_EMERGENCY_MODE_DURATION,
            "Incorrect parameter MAX_EMERGENCY_MODE_DURATION"
        );
        require(
            timelockInstance.MAX_EMERGENCY_PROTECTION_DURATION() == dgDeployConfig.MAX_EMERGENCY_PROTECTION_DURATION,
            "Incorrect parameter MAX_EMERGENCY_PROTECTION_DURATION"
        );

        require(
            timelockInstance.getEmergencyActivationCommittee() == dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE,
            "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.getEmergencyExecutionCommittee() == dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE,
            "Incorrect emergencyExecutionCommittee address in EmergencyProtectedTimelock"
        );

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
            timelockInstance.getEmergencyProtectionDetails();
        require(
            details.emergencyProtectionEndsAfter <= dgDeployConfig.EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()),
            "Incorrect value for emergencyProtectionEndsAfter"
        );
        require(
            details.emergencyModeDuration == dgDeployConfig.EMERGENCY_MODE_DURATION,
            "Incorrect value for emergencyModeDuration"
        );

        require(
            timelockInstance.getEmergencyGovernance() == res.emergencyGovernance,
            "Incorrect emergencyGovernance address in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.getAfterSubmitDelay() == dgDeployConfig.AFTER_SUBMIT_DELAY,
            "Incorrect parameter AFTER_SUBMIT_DELAY"
        );
        require(
            timelockInstance.getAfterScheduleDelay() == dgDeployConfig.AFTER_SCHEDULE_DELAY,
            "Incorrect parameter AFTER_SCHEDULE_DELAY"
        );
        require(
            timelockInstance.getGovernance() == res.dualGovernance,
            "Incorrect governance address in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.isEmergencyProtectionEnabled() == true,
            "EmergencyProtection is Disabled in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.isEmergencyModeActive() == false, "EmergencyMode is Active in EmergencyProtectedTimelock"
        );
        require(timelockInstance.getProposalsCount() == 0, "ProposalsCount > 0 in EmergencyProtectedTimelock");
    }

    function checkEmergencyActivationCommittee(DeployConfig memory dgDeployConfig) internal pure {
        // TODO: implement!
        require(dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE != address(0), "Incorrect emergencyActivationCommittee");
    }

    function checkEmergencyExecutionCommittee(DeployConfig memory dgDeployConfig) internal pure {
        // TODO: implement!
        require(dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE != address(0), "Incorrect emergencyExecutionCommittee");
    }

    function checkTimelockedGovernance(
        DeployedAddresses memory res,
        LidoContracts memory lidoAddresses
    ) internal view {
        TimelockedGovernance emergencyTimelockedGovernance = TimelockedGovernance(res.emergencyGovernance);
        require(
            emergencyTimelockedGovernance.GOVERNANCE() == address(lidoAddresses.voting),
            "TimelockedGovernance governance != Lido voting"
        );
        require(
            address(emergencyTimelockedGovernance.TIMELOCK()) == res.timelock,
            "Incorrect address for timelock in TimelockedGovernance"
        );
    }

    function checkResealManager(DeployedAddresses memory res) internal view {
        require(
            address(ResealManager(res.resealManager).EMERGENCY_PROTECTED_TIMELOCK()) == res.timelock,
            "Incorrect address for EMERGENCY_PROTECTED_TIMELOCK in ResealManager"
        );
    }

    function checkDualGovernance(
        DeployedAddresses memory res,
        DeployConfig memory dgDeployConfig,
        LidoContracts memory lidoAddresses
    ) internal view {
        DualGovernance dg = DualGovernance(res.dualGovernance);
        require(address(dg.TIMELOCK()) == res.timelock, "Incorrect address for timelock in DualGovernance");
        require(
            address(dg.RESEAL_MANAGER()) == res.resealManager, "Incorrect address for resealManager in DualGovernance"
        );
        require(
            dg.MIN_TIEBREAKER_ACTIVATION_TIMEOUT() == dgDeployConfig.MIN_TIEBREAKER_ACTIVATION_TIMEOUT,
            "Incorrect parameter MIN_TIEBREAKER_ACTIVATION_TIMEOUT"
        );
        require(
            dg.MAX_TIEBREAKER_ACTIVATION_TIMEOUT() == dgDeployConfig.MAX_TIEBREAKER_ACTIVATION_TIMEOUT,
            "Incorrect parameter MAX_TIEBREAKER_ACTIVATION_TIMEOUT"
        );
        require(
            dg.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT() == dgDeployConfig.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT,
            "Incorrect parameter MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT"
        );

        Escrow escrowTemplate = Escrow(payable(address(dg.ESCROW_MASTER_COPY())));
        require(escrowTemplate.DUAL_GOVERNANCE() == dg, "Escrow has incorrect DualGovernance address");
        require(escrowTemplate.ST_ETH() == lidoAddresses.stETH, "Escrow has incorrect StETH address");
        require(escrowTemplate.WST_ETH() == lidoAddresses.wstETH, "Escrow has incorrect WstETH address");
        require(
            escrowTemplate.WITHDRAWAL_QUEUE() == lidoAddresses.withdrawalQueue,
            "Escrow has incorrect WithdrawalQueue address"
        );
        require(
            escrowTemplate.MIN_WITHDRAWALS_BATCH_SIZE() == dgDeployConfig.MIN_WITHDRAWALS_BATCH_SIZE,
            "Incorrect parameter MIN_WITHDRAWALS_BATCH_SIZE"
        );

        DualGovernanceConfig.Context memory dgConfig = dg.getConfigProvider().getDualGovernanceConfig();
        require(
            dgConfig.firstSealRageQuitSupport == dgDeployConfig.FIRST_SEAL_RAGE_QUIT_SUPPORT,
            "Incorrect parameter FIRST_SEAL_RAGE_QUIT_SUPPORT"
        );
        require(
            dgConfig.secondSealRageQuitSupport == dgDeployConfig.SECOND_SEAL_RAGE_QUIT_SUPPORT,
            "Incorrect parameter SECOND_SEAL_RAGE_QUIT_SUPPORT"
        );
        require(
            dgConfig.minAssetsLockDuration == dgDeployConfig.MIN_ASSETS_LOCK_DURATION,
            "Incorrect parameter MIN_ASSETS_LOCK_DURATION"
        );
        require(
            dgConfig.vetoSignallingMinDuration == dgDeployConfig.VETO_SIGNALLING_MIN_DURATION,
            "Incorrect parameter VETO_SIGNALLING_MIN_DURATION"
        );
        require(
            dgConfig.vetoSignallingMaxDuration == dgDeployConfig.VETO_SIGNALLING_MAX_DURATION,
            "Incorrect parameter VETO_SIGNALLING_MAX_DURATION"
        );
        require(
            dgConfig.vetoSignallingMinActiveDuration == dgDeployConfig.VETO_SIGNALLING_MIN_ACTIVE_DURATION,
            "Incorrect parameter VETO_SIGNALLING_MIN_ACTIVE_DURATION"
        );
        require(
            dgConfig.vetoSignallingDeactivationMaxDuration == dgDeployConfig.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION,
            "Incorrect parameter VETO_SIGNALLING_DEACTIVATION_MAX_DURATION"
        );
        require(
            dgConfig.vetoCooldownDuration == dgDeployConfig.VETO_COOLDOWN_DURATION,
            "Incorrect parameter VETO_COOLDOWN_DURATION"
        );
        require(
            dgConfig.rageQuitExtensionPeriodDuration == dgDeployConfig.RAGE_QUIT_EXTENSION_PERIOD_DURATION,
            "Incorrect parameter RAGE_QUIT_EXTENSION_PERIOD_DURATION"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsMinDelay == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsMaxDelay == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsDelayGrowth == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH"
        );

        require(dg.getPersistedState() == State.Normal, "Incorrect DualGovernance persisted state");
        require(dg.getEffectiveState() == State.Normal, "Incorrect DualGovernance effective state");
        require(dg.getProposers().length == 1, "Incorrect amount of proposers");
        require(dg.isProposer(address(lidoAddresses.voting)) == true, "Lido voting is not set as a proposers[0]");
        require(dg.isExecutor(res.adminExecutor) == true, "adminExecutor is not set as a proposers[0].executor");

        IDualGovernance.StateDetails memory stateDetails = dg.getStateDetails();
        require(stateDetails.effectiveState == State.Normal, "Incorrect DualGovernance effectiveState");
        require(stateDetails.persistedState == State.Normal, "Incorrect DualGovernance persistedState");
        require(
            stateDetails.persistedStateEnteredAt <= Timestamps.now(), "Incorrect DualGovernance persistedStateEnteredAt"
        );
        require(
            stateDetails.vetoSignallingActivatedAt == Timestamps.ZERO,
            "Incorrect DualGovernance state vetoSignallingActivatedAt"
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
            ts.tiebreakerActivationTimeout == dgDeployConfig.TIEBREAKER_ACTIVATION_TIMEOUT,
            "Incorrect parameter TIEBREAKER_ACTIVATION_TIMEOUT"
        );
        require(ts.tiebreakerCommittee == res.tiebreakerCoreCommittee, "Incorrect tiebreakerCoreCommittee");
        require(ts.sealableWithdrawalBlockers.length == 1, "Incorrect amount of sealableWithdrawalBlockers");
        require(
            ts.sealableWithdrawalBlockers[0] == address(lidoAddresses.withdrawalQueue),
            "Lido withdrawalQueue is not set as a sealableWithdrawalBlockers[0]"
        );
    }

    function checkTiebreakerCoreCommittee(
        DeployedAddresses memory res,
        DeployConfig memory dgDeployConfig
    ) internal view {
        TiebreakerCoreCommittee tcc = TiebreakerCoreCommittee(res.tiebreakerCoreCommittee);
        require(tcc.owner() == res.adminExecutor, "TiebreakerCoreCommittee owner != adminExecutor");
        require(
            tcc.timelockDuration() == dgDeployConfig.TIEBREAKER_EXECUTION_DELAY,
            "Incorrect parameter TIEBREAKER_EXECUTION_DELAY"
        );

        for (uint256 i = 0; i < dgDeployConfig.TIEBREAKER_SUB_COMMITTEES_COUNT; ++i) {
            require(tcc.isMember(res.tiebreakerSubCommittees[i]) == true, "Incorrect member of TiebreakerCoreCommittee");
        }
        require(tcc.quorum() == dgDeployConfig.TIEBREAKER_CORE_QUORUM, "Incorrect quorum in TiebreakerCoreCommittee");
    }

    function checkTiebreakerSubCommittee(
        DeployedAddresses memory res,
        DeployConfig memory dgDeployConfig,
        uint256 index
    ) internal view {
        TiebreakerSubCommittee tsc = TiebreakerSubCommittee(res.tiebreakerSubCommittees[index]);
        require(tsc.owner() == res.adminExecutor, "TiebreakerSubCommittee owner != adminExecutor");
        require(tsc.timelockDuration() == Durations.from(0), "TiebreakerSubCommittee timelock should be 0");

        (uint256 quorum, address[] memory members) = getSubCommitteeData(index, dgDeployConfig);

        for (uint256 i = 0; i < members.length; ++i) {
            require(tsc.isMember(members[i]) == true, "Incorrect member of TiebreakerSubCommittee");
        }
        require(tsc.quorum() == quorum, "Incorrect quorum in TiebreakerSubCommittee");
    }

    function checkResealCommittee(DeployConfig memory dgDeployConfig) internal pure {
        // TODO: implement!
        require(dgDeployConfig.RESEAL_COMMITTEE != address(0), "Incorrect resealCommittee");
    }
}
