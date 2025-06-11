// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {
    TiebreakerDeployConfig,
    TiebreakerDeployedContracts,
    TiebreakerDeployArtifacts,
    ContractsDeployment
} from "../utils/contracts-deployment.sol";
import {DeployFiles} from "../utils/DeployFiles.sol";

contract DeployTiebreaker is Script {
    using TiebreakerDeployConfig for TiebreakerDeployConfig.Context;
    using TiebreakerDeployedContracts for TiebreakerDeployedContracts.Context;
    using TiebreakerDeployArtifacts for TiebreakerDeployArtifacts.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    function run() public {
        TiebreakerDeployArtifacts.Context memory _deployArtifact;
        string memory configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");
        console.log("Loading config file: %s", configFileName);

        _deployArtifact.deployConfig = TiebreakerDeployConfig.load(DeployFiles.resolveDeployConfig(configFileName), "");

        _deployArtifact.deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        uint256 expectedChainId = _deployArtifact.deployConfig.chainId;
        if (expectedChainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: expectedChainId});
        }

        vm.startBroadcast();

        _deployArtifact.deployedContracts = ContractsDeployment.deployTiebreaker(_deployArtifact.deployConfig, deployer);

        vm.stopBroadcast();

        console.log("\n");
        console.log("Tiebreaker deployed successfully");
        _deployArtifact.deployedContracts.print();

        string memory deployArtifactFileName =
            string.concat("deploy-artifact-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".toml");

        _deployArtifact.save(deployArtifactFileName);
        console.log("Deploy artifact saved to: %s", deployArtifactFileName);
    }
}
