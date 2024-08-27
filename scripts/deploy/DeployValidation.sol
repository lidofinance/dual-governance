// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {EmergencyExecutionCommittee} from "contracts/committees/EmergencyExecutionCommittee.sol";
import {EmergencyActivationCommittee} from "contracts/committees/EmergencyActivationCommittee.sol";
import {DGDeployConfig, ConfigValues} from "./Config.s.sol";

library DeployValidation {
    struct DeployResult {
        address deployer; // TODO: not used, del?
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

        checkAdminExecutor(res.adminExecutor, res.timelock);
        checkTimelock(res, dgDeployConfig);
        checkEmergencyActivationCommittee(res.emergencyActivationCommittee, res.adminExecutor);
        checkEmergencyExecutionCommittee(res.emergencyExecutionCommittee, res.adminExecutor);
        checkTimelockedGovernance();
        checkResealManager();
        // TODO: check dualGovernanceConfigProvider?
        checkDualGovernance();
        checkTiebreakerCoreCommittee();
        checkTiebreakerSubCommittee1();
        checkTiebreakerSubCommittee2();
        checkResealCommittee();
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
        // committees
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
        address adminExecutor
    ) internal view {
        require(EmergencyActivationCommittee(emergencyActivationCommittee).owner() == adminExecutor);
        // TODO: check members?
        // TODO: check quorum?
    }

    function checkEmergencyExecutionCommittee(
        address emergencyExecutionCommittee,
        address adminExecutor
    ) internal view {
        require(EmergencyExecutionCommittee(emergencyExecutionCommittee).owner() == adminExecutor);
        // TODO: check members?
        // TODO: check quorum?
    }

    function checkTimelockedGovernance() internal view {
        // TODO: implement
    }

    function checkResealManager() internal view {
        // TODO: implement
    }

    function checkDualGovernance() internal view {
        // TODO: implement
    }

    function checkTiebreakerCoreCommittee() internal view {
        // TODO: implement
    }

    function checkTiebreakerSubCommittee1() internal view {
        // TODO: implement
    }

    function checkTiebreakerSubCommittee2() internal view {
        // TODO: implement
    }

    function checkResealCommittee() internal view {
        // TODO: implement
    }
}
