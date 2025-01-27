// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DGSetupDeployVerification} from "./DGSetupDeployVerification.sol";
import {
    DGSetupDeployConfig,
    DGSetupDeployArtifacts,
    ContractsDeployment,
    DGSetupDeployedContracts
} from "../utils/contracts-deployment.sol";

import {DeployFiles} from "../utils/deploy-files.sol";

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
        console.log(deployConfig.toJSON());

        deployConfig.validate();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        console.log("Deployer account: %x", deployer);

        vm.startBroadcast();

        DGSetupDeployedContracts.Context memory deployedContracts =
            ContractsDeployment.deployDGSetup(deployer, deployConfig);

        vm.stopBroadcast();

        console.log("DG deployed successfully");
        deployedContracts.print();

        console.log("Verifying deploy");

        DGSetupDeployVerification.verify(deployedContracts, deployConfig, false);

        console.log(unicode"Verified ✅");

        string memory deployArtifactFileName =
            string.concat("deploy-artifact-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".toml");

        DGSetupDeployArtifacts.create(deployConfig, deployedContracts).save(deployArtifactFileName);
    }
}
