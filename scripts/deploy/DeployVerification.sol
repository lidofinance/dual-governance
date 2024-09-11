// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations} from "contracts/types/Duration.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";
import {Executor} from "contracts/Executor.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {ResealCommittee} from "contracts/committees/ResealCommittee.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {TiebreakerCore} from "contracts/committees/TiebreakerCore.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
import {EmergencyExecutionCommittee} from "contracts/committees/EmergencyExecutionCommittee.sol";
import {EmergencyActivationCommittee} from "contracts/committees/EmergencyActivationCommittee.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {Escrow} from "contracts/Escrow.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {State} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {DeployConfig, LidoContracts, getSubCommitteeData} from "./Config.sol";

// TODO: long error texts in require()

library DeployVerification {
    struct DeployedAddresses {
        address payable adminExecutor;
        address timelock;
        address emergencyGovernance;
        address emergencyActivationCommittee;
        address emergencyExecutionCommittee;
        address resealManager;
        address dualGovernance;
        address resealCommittee;
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
        checkEmergencyActivationCommittee(res, dgDeployConfig);
        checkEmergencyExecutionCommittee(res, dgDeployConfig);
        checkTimelockedGovernance(res, lidoAddresses);
        checkResealManager(res);
        checkDualGovernance(res, dgDeployConfig, lidoAddresses);
        checkTiebreakerCoreCommittee(res, dgDeployConfig);

        for (uint256 i = 0; i < dgDeployConfig.TIEBREAKER_SUB_COMMITTEES_COUNT; ++i) {
            checkTiebreakerSubCommittee(res, dgDeployConfig, i);
        }

        checkResealCommittee(res, dgDeployConfig);
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
            timelockInstance.getEmergencyActivationCommittee() == res.emergencyActivationCommittee,
            "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
        );
        require(
            timelockInstance.getEmergencyExecutionCommittee() == res.emergencyExecutionCommittee,
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

    function checkEmergencyActivationCommittee(
        DeployedAddresses memory res,
        DeployConfig memory dgDeployConfig
    ) internal view {
        EmergencyActivationCommittee committee = EmergencyActivationCommittee(res.emergencyActivationCommittee);
        require(committee.owner() == res.adminExecutor, "EmergencyActivationCommittee owner != adminExecutor");
        require(
            committee.EMERGENCY_PROTECTED_TIMELOCK() == res.timelock,
            "EmergencyActivationCommittee EMERGENCY_PROTECTED_TIMELOCK != timelock"
        );

        for (uint256 i = 0; i < dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS.length; ++i) {
            require(
                committee.isMember(dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS[i]) == true,
                "Incorrect member of EmergencyActivationCommittee"
            );
        }
        require(
            committee.quorum() == dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM,
            "EmergencyActivationCommittee has incorrect quorum set"
        );
    }

    function checkEmergencyExecutionCommittee(
        DeployedAddresses memory res,
        DeployConfig memory dgDeployConfig
    ) internal view {
        EmergencyExecutionCommittee committee = EmergencyExecutionCommittee(res.emergencyExecutionCommittee);
        require(committee.owner() == res.adminExecutor, "EmergencyExecutionCommittee owner != adminExecutor");
        require(
            committee.EMERGENCY_PROTECTED_TIMELOCK() == res.timelock,
            "EmergencyExecutionCommittee EMERGENCY_PROTECTED_TIMELOCK != timelock"
        );

        for (uint256 i = 0; i < dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS.length; ++i) {
            require(
                committee.isMember(dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS[i]) == true,
                "Incorrect member of EmergencyExecutionCommittee"
            );
        }
        require(
            committee.quorum() == dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_QUORUM,
            "EmergencyExecutionCommittee has incorrect quorum set"
        );
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

        Escrow escrowTemplate = Escrow(payable(dg.ESCROW_MASTER_COPY()));
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
            PercentD16.unwrap(dgConfig.firstSealRageQuitSupport)
                == PercentD16.unwrap(dgDeployConfig.FIRST_SEAL_RAGE_QUIT_SUPPORT),
            "Incorrect parameter FIRST_SEAL_RAGE_QUIT_SUPPORT"
        );
        require(
            PercentD16.unwrap(dgConfig.secondSealRageQuitSupport)
                == PercentD16.unwrap(dgDeployConfig.SECOND_SEAL_RAGE_QUIT_SUPPORT),
            "Incorrect parameter SECOND_SEAL_RAGE_QUIT_SUPPORT"
        );
        require(
            dgConfig.minAssetsLockDuration == dgDeployConfig.MIN_ASSETS_LOCK_DURATION,
            "Incorrect parameter MIN_ASSETS_LOCK_DURATION"
        );
        require(
            dgConfig.dynamicTimelockMinDuration == dgDeployConfig.DYNAMIC_TIMELOCK_MIN_DURATION,
            "Incorrect parameter DYNAMIC_TIMELOCK_MIN_DURATION"
        );
        require(
            dgConfig.dynamicTimelockMaxDuration == dgDeployConfig.DYNAMIC_TIMELOCK_MAX_DURATION,
            "Incorrect parameter DYNAMIC_TIMELOCK_MAX_DURATION"
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
            dgConfig.rageQuitExtensionDelay == dgDeployConfig.RAGE_QUIT_EXTENSION_DELAY,
            "Incorrect parameter RAGE_QUIT_EXTENSION_DELAY"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsMinTimelock == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber
                == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER,
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[0]
                == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[0],
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[0]"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[1]
                == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[1],
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[1]"
        );
        require(
            dgConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[2]
                == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[2],
            "Incorrect parameter RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[2]"
        );

        require(dg.getState() == State.Normal, "Incorrect DualGovernance state");
        require(dg.getProposers().length == 1, "Incorrect amount of proposers");
        require(dg.isProposer(address(lidoAddresses.voting)) == true, "Lido voting is not set as a proposers[0]");

        IDualGovernance.StateDetails memory stateDetails = dg.getStateDetails();
        require(stateDetails.state == State.Normal, "Incorrect DualGovernance state");
        require(stateDetails.enteredAt <= Timestamps.now(), "Incorrect DualGovernance state enteredAt");
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
        require(stateDetails.dynamicDelay == Durations.ZERO, "Incorrect DualGovernance state dynamicDelay");

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
        TiebreakerCore tcc = TiebreakerCore(res.tiebreakerCoreCommittee);
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

    function checkResealCommittee(DeployedAddresses memory res, DeployConfig memory dgDeployConfig) internal view {
        ResealCommittee rc = ResealCommittee(res.resealCommittee);
        require(rc.owner() == res.adminExecutor, "ResealCommittee owner != adminExecutor");
        require(rc.timelockDuration() == Durations.from(0), "ResealCommittee timelock should be 0");
        require(rc.DUAL_GOVERNANCE() == res.dualGovernance, "Incorrect dualGovernance in ResealCommittee");

        for (uint256 i = 0; i < dgDeployConfig.RESEAL_COMMITTEE_MEMBERS.length; ++i) {
            require(
                rc.isMember(dgDeployConfig.RESEAL_COMMITTEE_MEMBERS[i]) == true, "Incorrect member of ResealCommittee"
            );
        }
        require(rc.quorum() == dgDeployConfig.RESEAL_COMMITTEE_QUORUM, "Incorrect quorum in ResealCommittee");
    }
}
