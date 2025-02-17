// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";
import {DGDeployArtifactLoader} from "../utils/DGDeployArtifactLoader.sol";
import {DGSetupDeployArtifacts} from "../utils/contracts-deployment.sol";
import {DGLaunchVerifier} from "./DGLaunchVerifier.sol";

contract DeployDGLaunchVerifier is DGDeployArtifactLoader {
    function run() public {
        vm.label(msg.sender, "DEPLOYER");

        DGSetupDeployArtifacts.Context memory _deployArtifact = _loadEnv();

        vm.startBroadcast();

        DGLaunchVerifier verifier = new DGLaunchVerifier(
            DGLaunchVerifier.ConstructorParams({
                timelock: address(_deployArtifact.deployedContracts.timelock),
                dualGovernance: address(_deployArtifact.deployedContracts.dualGovernance),
                emergencyGovernance: address(_deployArtifact.deployedContracts.emergencyGovernance),
                emergencyActivationCommittee: _deployArtifact.deployConfig.timelock.emergencyActivationCommittee,
                emergencyExecutionCommittee: _deployArtifact.deployConfig.timelock.emergencyExecutionCommittee,
                emergencyProtectionEndDate: _deployArtifact.deployConfig.timelock.emergencyProtectionEndDate,
                emergencyModeDuration: _deployArtifact.deployConfig.timelock.emergencyModeDuration,
                proposalsCount: 2
            })
        );

        vm.stopBroadcast();

        console.log("DGLaunchVerifier deployed successfully at", address(verifier));
    }
}
