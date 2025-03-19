// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RolesValidatorHolesky} from "./RolesValidatorHolesky.sol";
import {DGUpgradeHolesky} from "./DGUpgradeHolesky.sol";

import {DGDeployArtifactLoader} from "../../utils/DGDeployArtifactLoader.sol";
import {DGSetupDeployArtifacts} from "../../utils/contracts-deployment.sol";

contract DeployUpgradeHolesky is DGDeployArtifactLoader {
    function run() public {
        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        DGSetupDeployArtifacts.Context memory _deployArtifact = _loadEnv();

        vm.startBroadcast();

        RolesValidatorHolesky rolesValidator = new RolesValidatorHolesky();
        vm.label(address(rolesValidator), "ROLES_VALIDATOR");

        vm.stopBroadcast();
        address launchVerifier = address(0); // TODO: add launch verifier address

        vm.startBroadcast();
        DGUpgradeHolesky dgUpgradeHolesky = new DGUpgradeHolesky(
            address(_deployArtifact.deployedContracts.dualGovernance),
            address(_deployArtifact.deployedContracts.adminExecutor),
            address(_deployArtifact.deployedContracts.resealManager),
            address(rolesValidator),
            launchVerifier
        );
        vm.label(address(dgUpgradeHolesky), "DG_UPGRADE_CONTRACT");
        vm.stopBroadcast();
    }
}
