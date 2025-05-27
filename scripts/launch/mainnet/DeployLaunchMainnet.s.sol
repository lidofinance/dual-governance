// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {DGDeployArtifactLoader} from "scripts/utils/DGDeployArtifactLoader.sol";
import {DGSetupDeployArtifacts} from "scripts/utils/contracts-deployment.sol";
import {DGLaunchConfig} from "scripts/utils/contracts-deployment.sol";

import {DGRolesValidatorMainnet} from "./DGRolesValidatorMainnet.sol";
import {DGLaunchOmnibusMainnet} from "./DGLaunchOmnibusMainnet.sol";
import {DGLaunchStateVerifier} from "../DGLaunchStateVerifier.sol";

import {Duration} from "contracts/types/Duration.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";

import {TimeConstraints} from "../TimeConstraints.sol";

import {console} from "forge-std/console.sol";

contract DeployLaunchMainnet is DGDeployArtifactLoader {
    function run() public {
        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        string memory deployArtifactFileName = vm.envString("DEPLOY_ARTIFACT_FILE_NAME");

        DGSetupDeployArtifacts.Context memory _deployArtifact = _loadEnv();
        DGLaunchConfig.Context memory dgLaunchConfig = DGSetupDeployArtifacts.loadDGLaunchConfig(deployArtifactFileName);

        address timelock = address(_deployArtifact.deployedContracts.timelock);
        address dualGovernance = address(_deployArtifact.deployedContracts.dualGovernance);
        address emergencyGovernance = address(dgLaunchConfig.daoEmergencyGovernance);
        address emergencyActivationCommittee = _deployArtifact.deployConfig.timelock.emergencyActivationCommittee;
        address emergencyExecutionCommittee = _deployArtifact.deployConfig.timelock.emergencyExecutionCommittee;
        Timestamp emergencyProtectionEndDate = _deployArtifact.deployConfig.timelock.emergencyProtectionEndDate;
        Duration emergencyModeDuration = _deployArtifact.deployConfig.timelock.emergencyModeDuration;
        uint256 proposalsCount = 2;

        address adminExecutor = address(_deployArtifact.deployedContracts.adminExecutor);
        address resealManager = address(_deployArtifact.deployedContracts.resealManager);

        vm.startBroadcast();

        console.log("=====================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", msg.sender);
        console.log("=====================================");
        console.log("Deploying Launch Verifier contract with the following params:\n");
        console.log("=====================================");
        console.log("Emergency Protected Timelock:", timelock);
        console.log("Dual Governance:", dualGovernance);
        console.log("Emergency Governance:", emergencyGovernance);
        console.log("Emergency Activation Committee:", emergencyActivationCommittee);
        console.log("Emergency Execution Committee:", emergencyExecutionCommittee);
        console.log("Emergency Protection End Date:", emergencyProtectionEndDate.toSeconds());
        console.log("Emergency Mode Duration:", emergencyModeDuration.toSeconds());
        console.log("Proposals Count:", proposalsCount);
        console.log("=====================================");

        DGLaunchStateVerifier launchVerifier = new DGLaunchStateVerifier(
            DGLaunchStateVerifier.ConstructorParams({
                timelock: timelock,
                dualGovernance: dualGovernance,
                emergencyGovernance: emergencyGovernance,
                emergencyActivationCommittee: emergencyActivationCommittee,
                emergencyExecutionCommittee: emergencyExecutionCommittee,
                emergencyProtectionEndDate: emergencyProtectionEndDate,
                emergencyModeDuration: emergencyModeDuration,
                proposalsCount: 2
            })
        );
        vm.label(address(launchVerifier), "LAUNCH_VERIFIER");

        DGRolesValidatorMainnet rolesValidator = new DGRolesValidatorMainnet(adminExecutor, resealManager);
        vm.label(address(rolesValidator), "ROLES_VALIDATOR");

        TimeConstraints timeConstraints = new TimeConstraints();
        vm.label(address(timeConstraints), "TIME_CONSTRAINTS");

        console.log("Deploying Mainnet omnibus builder contract with the following params:\n");
        console.log("=====================================");
        console.log("Dual Governance:", dualGovernance);
        console.log("Admin Executor:", adminExecutor);
        console.log("Reseal Manager:", resealManager);
        console.log("Roles Validator (deployed):", address(rolesValidator));
        console.log("Launch Verifier (deployed):", address(launchVerifier));
        console.log("Time Constraints (deployed):", address(timeConstraints));
        console.log("=====================================");

        DGLaunchOmnibusMainnet dgLaunchMainnet = new DGLaunchOmnibusMainnet(
            address(dualGovernance),
            address(adminExecutor),
            address(resealManager),
            address(rolesValidator),
            address(launchVerifier),
            address(timeConstraints)
        );
        vm.label(address(dgLaunchMainnet), "DG_LAUNCH_CONTRACT");
        vm.stopBroadcast();

        console.log("DGLaunchStateVerifier deployed successfully at ", address(launchVerifier));
        console.log("RolesValidatorMainnet deployed successfully at ", address(rolesValidator));
        console.log("TimeConstraints deployed successfully at ", address(timeConstraints));
        console.log("LaunchOmnibusMainnet deployed successfully at ", address(dgLaunchMainnet));
    }
}
