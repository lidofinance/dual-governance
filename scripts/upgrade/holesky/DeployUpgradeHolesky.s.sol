// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGDeployArtifactLoader} from "scripts/utils/DGDeployArtifactLoader.sol";
import {DGSetupDeployArtifacts} from "scripts/utils/contracts-deployment.sol";

import {RolesValidatorHolesky} from "./RolesValidatorHolesky.sol";
import {DGUpgradeHolesky} from "./DGUpgradeHolesky.sol";

import {TimeConstraints} from "../TimeConstraints.sol";

contract DeployUpgradeHolesky is DGDeployArtifactLoader {
    function run() public {
        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        DGSetupDeployArtifacts.Context memory _deployArtifact = _loadEnv();

        vm.startBroadcast();

        RolesValidatorHolesky rolesValidator = new RolesValidatorHolesky();
        vm.label(address(rolesValidator), "ROLES_VALIDATOR");

        TimeConstraints timeConstraints = new TimeConstraints();
        vm.label(address(timeConstraints), "TIME_CONSTRAINTS");

        // TODO: add launch verifier address
        address launchVerifier = address(0);

        DGUpgradeHolesky dgUpgradeHolesky = new DGUpgradeHolesky(
            address(_deployArtifact.deployedContracts.dualGovernance),
            address(_deployArtifact.deployedContracts.adminExecutor),
            address(_deployArtifact.deployedContracts.resealManager),
            address(rolesValidator),
            launchVerifier,
            address(timeConstraints)
        );
        vm.label(address(dgUpgradeHolesky), "DG_UPGRADE_CONTRACT");
        vm.stopBroadcast();
    }
}
