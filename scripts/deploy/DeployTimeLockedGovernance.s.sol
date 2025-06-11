// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {
    TimelockedGovernanceDeployConfig,
    TimelockedGovernanceDeployArtifacts,
    TimelockedGovernanceDeployedContracts
} from "../utils/contracts-deployment.sol";
import {DeployFiles} from "../utils/DeployFiles.sol";

contract DeployTimeLockedGovernance is Script {
    using TimelockedGovernanceDeployConfig for TimelockedGovernanceDeployConfig.Context;
    using TimelockedGovernanceDeployArtifacts for TimelockedGovernanceDeployArtifacts.Context;
    using TimelockedGovernanceDeployedContracts for TimelockedGovernanceDeployedContracts.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    TimelockedGovernanceDeployConfig.Context internal _config;

    function run() public {
        string memory configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");
        console.log("Loading config file: %s", configFileName);

        TimelockedGovernanceDeployConfig.Context memory deployConfig =
            TimelockedGovernanceDeployConfig.load(DeployFiles.resolveDeployConfig(configFileName), "");

        deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        vm.startBroadcast();

        TimelockedGovernance timelockedGovernance =
            new TimelockedGovernance(deployConfig.governance, deployConfig.timelock);

        TimelockedGovernanceDeployedContracts.Context memory deployedContracts =
            TimelockedGovernanceDeployedContracts.Context({timelockedGovernance: timelockedGovernance});

        vm.stopBroadcast();

        console.log("\n");
        console.log("TimelockedGovernance deployed successfully");
        deployedContracts.print();

        TimelockedGovernanceDeployArtifacts.Context memory deployArtifact = TimelockedGovernanceDeployArtifacts.Context({
            deployConfig: deployConfig,
            deployedContracts: deployedContracts
        });

        string memory deployArtifactFileName =
            string.concat("deploy-artifact-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".toml");

        deployArtifact.save(deployArtifactFileName);
        console.log("Deploy artifact saved to: %s", deployArtifactFileName);
    }
}
