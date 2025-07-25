// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {
    DGSetupDeployConfig,
    DGSetupDeployArtifacts,
    ContractsDeployment,
    DGSetupDeployedContracts
} from "../utils/contracts-deployment.sol";
import {DeployVerification} from "../utils/DeployVerification.sol";

import {DeployFiles} from "../utils/DeployFiles.sol";

contract DeployConfigurable is Script {
    using DGSetupDeployConfig for DGSetupDeployConfig.Context;
    using DGSetupDeployArtifacts for DGSetupDeployArtifacts.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    function run() public {
        string memory configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");

        console.log("Loading config file: %s", configFileName);
        DGSetupDeployConfig.Context memory deployConfig =
            DGSetupDeployConfig.load({configFilePath: DeployFiles.resolveDeployConfig(configFileName)});

        if (deployConfig.chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: deployConfig.chainId});
        }

        console.log("Loaded config file: ");
        console.log("\n");
        deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        console.log("Deployer account: %x", deployer);

        vm.startBroadcast();

        DGSetupDeployedContracts.Context memory deployedContracts =
            ContractsDeployment.deployDGSetup(deployer, deployConfig);

        vm.stopBroadcast();

        console.log("DG deployed successfully");
        deployedContracts.print();

        DGSetupDeployArtifacts.Context memory deployArtifact =
            DGSetupDeployArtifacts.Context({deployConfig: deployConfig, deployedContracts: deployedContracts});

        console.log("Verifying deploy");

        DeployVerification.verify(deployArtifact);

        console.log(unicode"Verified ✅");

        string memory deployArtifactFileName =
            string.concat("deploy-artifact-", vm.toString(block.chainid), "-", vm.toString(block.timestamp));

        deployArtifact.save(string.concat(deployArtifactFileName, ".toml"));
    }
}
