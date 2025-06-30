// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DGSetupDeployArtifacts, DGSetupDeployedContracts} from "../utils/contracts-deployment.sol";
import {DeployVerification} from "../utils/DeployVerification.sol";

contract Verify is Script {
    using DGSetupDeployArtifacts for DGSetupDeployArtifacts.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;

    error InvalidChainId(uint256 actual, uint256 expected);

    function run() external view {
        string memory deployArtifactFileName = vm.envString("DEPLOY_ARTIFACT_FILE_NAME");

        console.log("Loading config from artifact file: %s", deployArtifactFileName);

        DGSetupDeployArtifacts.Context memory deployArtifact = DGSetupDeployArtifacts.load(deployArtifactFileName);

        if (deployArtifact.deployConfig.chainId != block.chainid) {
            revert InvalidChainId({actual: block.chainid, expected: deployArtifact.deployConfig.chainId});
        }
        console.log("Using the following DG contracts addresses (from file", deployArtifactFileName, "):");
        deployArtifact.deployedContracts.print();

        console.log("Verifying deploy");

        DeployVerification.verify(deployArtifact);

        console.log(unicode"Verified ✅");
    }
}
