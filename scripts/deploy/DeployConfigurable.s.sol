// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DeployVerification} from "./DeployVerification.sol";
import {
    DGDeployConfig, DGDeployArtifacts, ContractsDeployment, DGDeployedContracts
} from "./ContractsDeploymentNew.sol";

string constant CONFIG_FILES_DIR = "deploy-config";
string constant DEPLOY_ARTIFACTS_DIR = "deploy-artifacts";

contract DeployConfigurable is Script {
    using DGDeployConfig for DGDeployConfig.Context;
    using DGDeployArtifacts for DGDeployArtifacts.Context;
    using DGDeployedContracts for DGDeployedContracts.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    function run() public {
        string memory configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");
        string memory configFilePath = string.concat(vm.projectRoot(), "/", CONFIG_FILES_DIR, "/", configFileName);

        console.log("Loading config file: %s", configFilePath);
        DGDeployConfig.Context memory deployConfig = DGDeployConfig.load(configFilePath);

        if (deployConfig.chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: deployConfig.chainId});
        }

        console.log("Loaded config file: ");
        deployConfig.print();

        deployConfig.validate();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        console.log("Deployer account: %x", deployer);
        // vm.prompt("Validate the Config and proceed if everything is good.");

        vm.startBroadcast();

        DGDeployedContracts.Context memory deployedContracts = ContractsDeployment.deployDGSetup(deployer, deployConfig);

        vm.stopBroadcast();

        console.log("DG deployed successfully");
        deployedContracts.print();

        console.log("Verifying deploy");

        console.log("TODO: implement verification");
        // DeployVerification.verify(_contracts, _config, _lidoAddresses, false);

        console.log(unicode"Verified ✅");

        string memory deployArtifactFileName =
            string.concat("deploy-artifact-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".toml");
        string memory deployArtifactsFilePath =
            string.concat(vm.projectRoot(), "/", DEPLOY_ARTIFACTS_DIR, "/", deployArtifactFileName);

        DGDeployArtifacts.create(deployConfig, deployedContracts).save(deployArtifactsFilePath);
    }
}
