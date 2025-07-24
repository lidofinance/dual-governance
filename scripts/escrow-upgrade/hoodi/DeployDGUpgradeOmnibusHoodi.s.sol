// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

import {DGUpgradeOmnibusHoodi} from "./DGUpgradeOmnibusHoodi.sol";
import {DGUpgradeStateVerifierHoodi} from "./DGUpgradeStateVerifierHoodi.sol";

import {DGSetupDeployArtifacts} from "scripts/utils/contracts-deployment.sol";
import {ImmutableDualGovernanceConfigProviderDeployArtifacts} from
    "scripts/utils/deployment/ImmutableDualGovernanceConfigProvider.sol";

contract DeployDGUpgradeOmnibusHoodi is Script {
    function run() public {
        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        string memory deployArtifactFileName = vm.envString("DEPLOY_ARTIFACT_FILE_NAME");
        string memory dgConfigProviderDeployArtifactFileName =
            vm.envString("DG_CONFIG_PROVIDER_DEPLOY_ARTIFACT_FILE_NAME");

        DGSetupDeployArtifacts.Context memory deployArtifact = DGSetupDeployArtifacts.load(deployArtifactFileName);

        ImmutableDualGovernanceConfigProviderDeployArtifacts.Context memory dgConfigProviderDeployArtifact =
            ImmutableDualGovernanceConfigProviderDeployArtifacts.load(dgConfigProviderDeployArtifactFileName);

        address newDualGovernance = address(deployArtifact.deployedContracts.dualGovernance);
        address newTiebreakerCoreCommittee = address(deployArtifact.deployedContracts.tiebreakerCoreCommittee);
        address configProviderForOldDualGovernance =
            address(dgConfigProviderDeployArtifact.deployedContracts.dualGovernanceConfigProvider);

        console.log("=====================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", msg.sender);
        console.log("=====================================");
        console.log("Using deploy artifacts:");
        console.log("Dual Governance:", deployArtifactFileName);
        console.log("Dual Governance Config Provider:", dgConfigProviderDeployArtifactFileName);
        console.log("=====================================");
        console.log("\n");
        console.log("Deploying omnibus builder contract with the following params:\n");
        console.log("=====================================");
        console.log("\n");
        console.log("New Dual Governance:", newDualGovernance);
        console.log("New Tiebreaker Core Committee:", newTiebreakerCoreCommittee);
        console.log("Config Provider for disabled Dual Governance:", configProviderForOldDualGovernance);
        console.log("\n");
        console.log("=====================================");
        console.log("\n");

        vm.startBroadcast();
        DGUpgradeStateVerifierHoodi dgUpgradeStateVerifier = new DGUpgradeStateVerifierHoodi(
            newDualGovernance, newTiebreakerCoreCommittee, configProviderForOldDualGovernance
        );
        vm.label(address(dgUpgradeStateVerifier), "DG_UPGRADE_STATE_VERIFIER");
        console.log("DGUpgradeStateVerifier deployed successfully at ", address(dgUpgradeStateVerifier));

        DGUpgradeOmnibusHoodi dgUpgradeOmnibus = new DGUpgradeOmnibusHoodi(
            address(dgUpgradeStateVerifier),
            newDualGovernance,
            newTiebreakerCoreCommittee,
            configProviderForOldDualGovernance
        );
        vm.label(address(dgUpgradeOmnibus), "DG_UPGRADE_OMNIBUS");
        vm.stopBroadcast();

        console.log("DGUpgradeOmnibus deployed successfully at ", address(dgUpgradeOmnibus));
    }
}
