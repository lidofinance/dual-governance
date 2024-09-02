// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations} from "contracts/types/Duration.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";
import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {ResealCommittee} from "contracts/committees/ResealCommittee.sol";
import {TiebreakerCore} from "contracts/committees/TiebreakerCore.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
import {EmergencyExecutionCommittee} from "contracts/committees/EmergencyExecutionCommittee.sol";
import {EmergencyActivationCommittee} from "contracts/committees/EmergencyActivationCommittee.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {Escrow} from "contracts/Escrow.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {State} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {DGDeployConfig, LidoAddresses, ConfigValues} from "./Config.s.sol";

library DeployValidation {
    struct DeployResult {
        address payable adminExecutor;
        address timelock;
        address emergencyGovernance;
        address emergencyActivationCommittee;
        address emergencyExecutionCommittee;
        address resealManager;
        address dualGovernance;
        address resealCommittee;
        address tiebreakerCoreCommittee;
        address tiebreakerSubCommittee1;
        address tiebreakerSubCommittee2;
    }

    function check(DeployResult memory res) internal {
        DGDeployConfig configProvider = new DGDeployConfig();
        ConfigValues memory dgDeployConfig = configProvider.loadAndValidate();
        LidoAddresses memory lidoAddresses = configProvider.lidoAddresses(dgDeployConfig);

        checkAdminExecutor(res.adminExecutor, res.timelock);
        checkTimelock(res, dgDeployConfig);
        checkEmergencyActivationCommittee(res.emergencyActivationCommittee, res.adminExecutor, dgDeployConfig);
        checkEmergencyExecutionCommittee(res.emergencyExecutionCommittee, res.adminExecutor, dgDeployConfig);
        checkTimelockedGovernance(res, lidoAddresses);
        checkResealManager(res);
        checkDualGovernance(res, dgDeployConfig, lidoAddresses);
        checkTiebreakerCoreCommittee(res, dgDeployConfig);
        checkTiebreakerSubCommittee1(res, dgDeployConfig);
        checkTiebreakerSubCommittee2(res, dgDeployConfig);
        checkResealCommittee(res, dgDeployConfig);
    }

    function checkAdminExecutor(address payable executor, address timelock) internal view {
        require(Executor(executor).owner() == timelock);
    }

    function checkTimelock(DeployResult memory res, ConfigValues memory dgDeployConfig) internal view {
        EmergencyProtectedTimelock timelockInstance = EmergencyProtectedTimelock(res.timelock);
        require(timelockInstance.getAdminExecutor() == res.adminExecutor);
        require(timelockInstance.MAX_AFTER_SUBMIT_DELAY() == dgDeployConfig.MAX_AFTER_SUBMIT_DELAY);
        require(timelockInstance.MAX_AFTER_SCHEDULE_DELAY() == dgDeployConfig.MAX_AFTER_SCHEDULE_DELAY);
        require(timelockInstance.MAX_EMERGENCY_MODE_DURATION() == dgDeployConfig.MAX_EMERGENCY_MODE_DURATION);
        require(
            timelockInstance.MAX_EMERGENCY_PROTECTION_DURATION() == dgDeployConfig.MAX_EMERGENCY_PROTECTION_DURATION
        );

        require(
            timelockInstance.getEmergencyProtectionContext().emergencyActivationCommittee
                == res.emergencyActivationCommittee
        );
        require(
            timelockInstance.getEmergencyProtectionContext().emergencyExecutionCommittee
                == res.emergencyExecutionCommittee
        );
        require(
            timelockInstance.getEmergencyProtectionContext().emergencyProtectionEndsAfter
                <= dgDeployConfig.EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now())
        );
        require(
            timelockInstance.getEmergencyProtectionContext().emergencyModeDuration
                == dgDeployConfig.EMERGENCY_MODE_DURATION
        );
        require(timelockInstance.getEmergencyProtectionContext().emergencyGovernance == res.emergencyGovernance);
        require(timelockInstance.getAfterSubmitDelay() == dgDeployConfig.AFTER_SUBMIT_DELAY);
        require(timelockInstance.getGovernance() == res.dualGovernance);
    }

    function checkEmergencyActivationCommittee(
        address emergencyActivationCommittee,
        address adminExecutor,
        ConfigValues memory dgDeployConfig
    ) internal view {
        EmergencyActivationCommittee committee = EmergencyActivationCommittee(emergencyActivationCommittee);
        require(committee.owner() == adminExecutor);

        for (uint256 i = 0; i < dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS.length; ++i) {
            require(committee.isMember(dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS[i]) == true);
        }
        require(committee.quorum() == dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM);
    }

    function checkEmergencyExecutionCommittee(
        address emergencyExecutionCommittee,
        address adminExecutor,
        ConfigValues memory dgDeployConfig
    ) internal view {
        EmergencyExecutionCommittee committee = EmergencyExecutionCommittee(emergencyExecutionCommittee);
        require(committee.owner() == adminExecutor);

        for (uint256 i = 0; i < dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS.length; ++i) {
            require(committee.isMember(dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS[i]) == true);
        }
        require(committee.quorum() == dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_QUORUM);
    }

    function checkTimelockedGovernance(DeployResult memory res, LidoAddresses memory lidoAddresses) internal view {
        TimelockedGovernance emergencyTimelockedGovernance = TimelockedGovernance(res.emergencyGovernance);
        require(emergencyTimelockedGovernance.GOVERNANCE() == address(lidoAddresses.voting));
        require(address(emergencyTimelockedGovernance.TIMELOCK()) == res.timelock);
    }

    function checkResealManager(DeployResult memory res) internal view {
        require(address(ResealManager(res.resealManager).EMERGENCY_PROTECTED_TIMELOCK()) == res.timelock);
    }

    function checkDualGovernance(
        DeployResult memory res,
        ConfigValues memory dgDeployConfig,
        LidoAddresses memory lidoAddresses
    ) internal view {
        DualGovernance dg = DualGovernance(res.dualGovernance);
        require(address(dg.TIMELOCK()) == res.timelock);
        require(address(dg.RESEAL_MANAGER()) == res.resealManager);
        require(dg.MIN_TIEBREAKER_ACTIVATION_TIMEOUT() == dgDeployConfig.MIN_TIEBREAKER_ACTIVATION_TIMEOUT);
        require(dg.MAX_TIEBREAKER_ACTIVATION_TIMEOUT() == dgDeployConfig.MAX_TIEBREAKER_ACTIVATION_TIMEOUT);
        require(dg.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT() == dgDeployConfig.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT);

        Escrow escrowTemplate = Escrow(payable(dg.ESCROW_MASTER_COPY()));
        require(escrowTemplate.DUAL_GOVERNANCE() == dg);
        require(escrowTemplate.ST_ETH() == lidoAddresses.stETH);
        require(escrowTemplate.WST_ETH() == lidoAddresses.wstETH);
        require(escrowTemplate.WITHDRAWAL_QUEUE() == lidoAddresses.withdrawalQueue);
        require(escrowTemplate.MIN_WITHDRAWALS_BATCH_SIZE() == dgDeployConfig.MIN_WITHDRAWALS_BATCH_SIZE);

        DualGovernanceConfig.Context memory dgConfig = dg.getConfigProvider().getDualGovernanceConfig();
        require(
            PercentD16.unwrap(dgConfig.firstSealRageQuitSupport)
                == PercentD16.unwrap(dgDeployConfig.FIRST_SEAL_RAGE_QUIT_SUPPORT)
        );
        require(
            PercentD16.unwrap(dgConfig.secondSealRageQuitSupport)
                == PercentD16.unwrap(dgDeployConfig.SECOND_SEAL_RAGE_QUIT_SUPPORT)
        );
        require(dgConfig.minAssetsLockDuration == dgDeployConfig.MIN_ASSETS_LOCK_DURATION);
        require(dgConfig.dynamicTimelockMinDuration == dgDeployConfig.DYNAMIC_TIMELOCK_MIN_DURATION);
        require(dgConfig.dynamicTimelockMaxDuration == dgDeployConfig.DYNAMIC_TIMELOCK_MAX_DURATION);
        require(dgConfig.vetoSignallingMinActiveDuration == dgDeployConfig.VETO_SIGNALLING_MIN_ACTIVE_DURATION);
        require(
            dgConfig.vetoSignallingDeactivationMaxDuration == dgDeployConfig.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION
        );
        require(dgConfig.vetoCooldownDuration == dgDeployConfig.VETO_COOLDOWN_DURATION);
        require(dgConfig.rageQuitExtensionDelay == dgDeployConfig.RAGE_QUIT_EXTENSION_DELAY);
        require(dgConfig.rageQuitEthWithdrawalsMinTimelock == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK);
        require(
            dgConfig.rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber
                == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER
        );
        require(
            dgConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[0]
                == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[0]
        );
        require(
            dgConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[1]
                == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[1]
        );
        require(
            dgConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[2]
                == dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[2]
        );

        require(dg.getCurrentState() == State.Normal);
    }

    function checkTiebreakerCoreCommittee(DeployResult memory res, ConfigValues memory dgDeployConfig) internal view {
        TiebreakerCore tcc = TiebreakerCore(res.tiebreakerCoreCommittee);
        require(tcc.owner() == res.adminExecutor);
        require(tcc.timelockDuration() == dgDeployConfig.TIEBREAKER_EXECUTION_DELAY);

        // TODO: N sub committees
        require(tcc.isMember(res.tiebreakerSubCommittee1) == true);
        require(tcc.isMember(res.tiebreakerSubCommittee2) == true);
        require(tcc.quorum() == 2);
    }

    function checkTiebreakerSubCommittee1(DeployResult memory res, ConfigValues memory dgDeployConfig) internal view {
        TiebreakerSubCommittee tsc = TiebreakerSubCommittee(res.tiebreakerSubCommittee1);
        require(tsc.owner() == res.adminExecutor);
        require(tsc.timelockDuration() == Durations.from(0)); // TODO: is it correct?

        for (uint256 i = 0; i < dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS.length; ++i) {
            require(tsc.isMember(dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS[i]) == true);
        }
        require(tsc.quorum() == dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_1_QUORUM);
    }

    function checkTiebreakerSubCommittee2(DeployResult memory res, ConfigValues memory dgDeployConfig) internal view {
        TiebreakerSubCommittee tsc = TiebreakerSubCommittee(res.tiebreakerSubCommittee2);
        require(tsc.owner() == res.adminExecutor);
        require(tsc.timelockDuration() == Durations.from(0), "TiebreakerSubCommittee2 timelock should be 0"); // TODO: is it correct?

        for (uint256 i = 0; i < dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS.length; ++i) {
            require(tsc.isMember(dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS[i]) == true);
        }
        require(tsc.quorum() == dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_2_QUORUM);
    }

    function checkResealCommittee(DeployResult memory res, ConfigValues memory dgDeployConfig) internal view {
        ResealCommittee rc = ResealCommittee(res.resealCommittee);
        require(rc.owner() == res.adminExecutor);
        require(rc.timelockDuration() == Durations.from(0), "ResealCommittee timelock should be 0"); // TODO: is it correct?

        for (uint256 i = 0; i < dgDeployConfig.RESEAL_COMMITTEE_MEMBERS.length; ++i) {
            require(rc.isMember(dgDeployConfig.RESEAL_COMMITTEE_MEMBERS[i]) == true);
        }
        require(rc.quorum() == dgDeployConfig.RESEAL_COMMITTEE_QUORUM);
    }
}
