// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

import {DeployConfig, LidoContracts} from "./Config.sol";
import {DGDeployJSONConfigProvider} from "./JsonConfig.s.sol";
import {DeployVerification} from "./DeployVerification.sol";

contract Verify is Script {
    using DeployVerification for DeployVerification.DeployedAddresses;

    DeployConfig internal config;
    LidoContracts internal lidoAddresses;

    function run() external {
        string memory chainName = vm.envString("CHAIN");
        string memory configFilePath = vm.envString("DEPLOY_CONFIG_FILE_PATH");
        string memory deployedAddressesFilePath = vm.envString("DEPLOYED_ADDRESSES_FILE_PATH");

        DGDeployJSONConfigProvider configProvider = new DGDeployJSONConfigProvider(configFilePath);
        config = configProvider.loadAndValidate();
        lidoAddresses = configProvider.getLidoAddresses(chainName);

        DeployVerification.DeployedAddresses memory res = loadDeployedAddresses(deployedAddressesFilePath);

        printAddresses(res);

        console.log("Verifying deploy");

        res.verify(config, lidoAddresses);

        console.log(unicode"Verified ✅");
    }

    function loadDeployedAddresses(string memory deployedAddressesFilePath)
        internal
        view
        returns (DeployVerification.DeployedAddresses memory)
    {
        string memory deployedAddressesJson = loadDeployedAddressesFile(deployedAddressesFilePath);

        return DeployVerification.DeployedAddresses({
            adminExecutor: payable(stdJson.readAddress(deployedAddressesJson, ".ADMIN_EXECUTOR")),
            timelock: stdJson.readAddress(deployedAddressesJson, ".TIMELOCK"),
            emergencyGovernance: stdJson.readAddress(deployedAddressesJson, ".EMERGENCY_GOVERNANCE"),
            emergencyActivationCommittee: stdJson.readAddress(deployedAddressesJson, ".EMERGENCY_ACTIVATION_COMMITTEE"),
            emergencyExecutionCommittee: stdJson.readAddress(deployedAddressesJson, ".EMERGENCY_EXECUTION_COMMITTEE"),
            resealManager: stdJson.readAddress(deployedAddressesJson, ".RESEAL_MANAGER"),
            dualGovernance: stdJson.readAddress(deployedAddressesJson, ".DUAL_GOVERNANCE"),
            resealCommittee: stdJson.readAddress(deployedAddressesJson, ".RESEAL_COMMITTEE"),
            tiebreakerCoreCommittee: stdJson.readAddress(deployedAddressesJson, ".TIEBREAKER_CORE_COMMITTEE"),
            tiebreakerSubCommittees: stdJson.readAddressArray(deployedAddressesJson, ".TIEBREAKER_SUB_COMMITTEES")
        });
    }

    function printAddresses(DeployVerification.DeployedAddresses memory res) internal pure {
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

    function loadDeployedAddressesFile(string memory deployedAddressesFilePath)
        internal
        view
        returns (string memory deployedAddressesJson)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", deployedAddressesFilePath);
        deployedAddressesJson = vm.readFile(path);
    }
}
