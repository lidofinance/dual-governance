// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployConfig, LidoContracts} from "./Config.sol";
import {DGDeployConfigProvider} from "./EnvConfig.s.sol";
import {DeployVerification} from "./DeployVerification.sol";

contract Verify is Script {
    using DeployVerification for DeployVerification.DeployedAddresses;

    DeployConfig internal config;
    LidoContracts internal lidoAddresses;
    address private deployer;
    uint256 private pk;

    function run() external {
        string memory chainName = vm.envString("CHAIN");
        DGDeployConfigProvider configProvider = new DGDeployConfigProvider();
        config = configProvider.loadAndValidate();
        lidoAddresses = configProvider.getLidoAddresses(chainName);

        DeployVerification.DeployedAddresses memory res = loadDeployedAddresses();

        printAddresses(res);

        console.log("Verifying deploy");

        res.verify(config, lidoAddresses);

        console.log(unicode"Verified ✅");
    }

    function loadDeployedAddresses() internal view returns (DeployVerification.DeployedAddresses memory) {
        return DeployVerification.DeployedAddresses({
            adminExecutor: payable(vm.envAddress("ADMIN_EXECUTOR")),
            timelock: vm.envAddress("TIMELOCK"),
            emergencyGovernance: vm.envAddress("EMERGENCY_GOVERNANCE"),
            emergencyActivationCommittee: vm.envAddress("EMERGENCY_ACTIVATION_COMMITTEE"),
            emergencyExecutionCommittee: vm.envAddress("EMERGENCY_EXECUTION_COMMITTEE"),
            resealManager: vm.envAddress("RESEAL_MANAGER"),
            dualGovernance: vm.envAddress("DUAL_GOVERNANCE"),
            resealCommittee: vm.envAddress("RESEAL_COMMITTEE"),
            tiebreakerCoreCommittee: vm.envAddress("TIEBREAKER_CORE_COMMITTEE"),
            tiebreakerSubCommittees: vm.envAddress("TIEBREAKER_SUB_COMMITTEES", ",")
        });
    }

    function printAddresses(DeployVerification.DeployedAddresses memory res) internal view {
        console.log("Using the following DG contracts addresses");
        console.log("DualGovernance address", res.dualGovernance);
        console.log("ResealManager address", res.resealManager);
        console.log("TiebreakerCoreCommittee address", res.tiebreakerCoreCommittee);

        for (uint256 i = 0; i < res.tiebreakerSubCommittees.length; ++i) {
            console.log("TiebreakerSubCommittee #", i, "address", res.tiebreakerSubCommittees[i]);
        }

        console.log("AdminExecutor address", res.adminExecutor);
        console.log("EmergencyProtectedTimelock address", res.timelock);
        console.log("EmergencyGovernance address", res.emergencyGovernance);
        console.log("EmergencyActivationCommittee address", res.emergencyActivationCommittee);
        console.log("EmergencyExecutionCommittee address", res.emergencyExecutionCommittee);
        console.log("ResealCommittee address", res.resealCommittee);
    }
}
