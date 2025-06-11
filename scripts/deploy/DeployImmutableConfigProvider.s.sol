// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Executor} from "contracts/Executor.sol";
import {
    ImmutableDualGovernanceConfigProviderDeployConfig,
    ImmutableDualGovernanceConfigProviderDeployArtifacts,
    ImmutableDualGovernanceConfigProviderDeployedContracts,
    ContractsDeployment
} from "../utils/contracts-deployment.sol";
import {DeployFiles} from "../utils/DeployFiles.sol";

contract DeployImmutableConfigProvider is Script {
    using
    ImmutableDualGovernanceConfigProviderDeployConfig
    for ImmutableDualGovernanceConfigProviderDeployConfig.Context;
    using
    ImmutableDualGovernanceConfigProviderDeployArtifacts
    for ImmutableDualGovernanceConfigProviderDeployArtifacts.Context;
    using
    ImmutableDualGovernanceConfigProviderDeployedContracts
    for ImmutableDualGovernanceConfigProviderDeployedContracts.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    ImmutableDualGovernanceConfigProviderDeployArtifacts.Context internal _deployArtifact;

    function run() public {
        string memory configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");
        console.log("Loading config file: %s", configFileName);

        _deployArtifact.deployConfig =
            ImmutableDualGovernanceConfigProviderDeployConfig.load(DeployFiles.resolveDeployConfig(configFileName), "");

        _deployArtifact.deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        uint256 expectedChainId = _deployArtifact.deployConfig.chainId;
        if (expectedChainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: expectedChainId});
        }

        vm.startBroadcast();

        _deployArtifact.deployedContracts.dualGovernanceConfigProvider =
            ContractsDeployment.deployDualGovernanceConfigProvider(_deployArtifact.deployConfig.config);

        vm.stopBroadcast();

        console.log("\n");
        console.log("Executor deployed successfully");
        _deployArtifact.deployedContracts.print();

        string memory deployArtifactFileName =
            string.concat("deploy-artifact-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".toml");

        _deployArtifact.save(deployArtifactFileName);

        console.log("\n");
        console.log("Deploy artifact saved to: %s", deployArtifactFileName);
    }
}
