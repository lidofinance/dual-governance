// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

import {Duration} from "contracts/types/Duration.sol";

import {DGUpgradeOmnibus} from "../DGUpgradeOmnibus.sol";
import {DGUpgradeStateVerifier} from "../DGUpgradeStateVerifier.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";

import {
    DGSetupDeployArtifacts,
    ImmutableDualGovernanceConfigProviderDeployArtifacts
} from "scripts/utils/contracts-deployment.sol";

contract DeployDGUpgradeOmnibusHoodi is Script {
    function run() public {
        LidoUtils.Context memory _lidoUtils = LidoUtils.hoodi();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        string memory deployArtifactFileName = vm.envString("DEPLOY_ARTIFACT_FILE_NAME");
        string memory dgConfigProviderDeployArtifactFileName =
            vm.envString("DG_CONFIG_PROVIDER_DEPLOY_ARTIFACT_FILE_NAME");

        DGSetupDeployArtifacts.Context memory deployArtifact = DGSetupDeployArtifacts.load(deployArtifactFileName);

        ImmutableDualGovernanceConfigProviderDeployArtifacts.Context memory dgConfigProviderDeployArtifact =
            ImmutableDualGovernanceConfigProviderDeployArtifacts.load(dgConfigProviderDeployArtifactFileName);

        address timelock = address(deployArtifact.deployedContracts.timelock);
        address adminExecutor = address(deployArtifact.deployedContracts.adminExecutor);
        Duration tiebreakerActivationTimeout = deployArtifact.deployConfig.dualGovernance.tiebreakerActivationTimeout;
        address accountingOracle = deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[0];
        address validatorsExitBusOracle = deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[1];
        address resealManager = address(deployArtifact.deployedContracts.resealManager);

        address newDualGovernance = address(deployArtifact.deployedContracts.dualGovernance);
        address newTiebreakerCoreCommittee = address(deployArtifact.deployedContracts.tiebreakerCoreCommittee);
        address configProviderForOldDualGovernance =
            address(dgConfigProviderDeployArtifact.deployedContracts.dualGovernanceConfigProvider);

        address voting = address(_lidoUtils.voting);
        address dualGovernance = address(_lidoUtils.dualGovernance);

        console.log("=====================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", msg.sender);
        console.log("=====================================");
        console.log("Deploying omnibus builder contract with the following params:\n");
        console.log("=====================================");
        console.log("Voting:", voting);
        console.log("Dual Governance:", dualGovernance);
        console.log("\n");
        console.log("New Dual Governance:", newDualGovernance);
        console.log("New Tiebreaker Core Committee:", newTiebreakerCoreCommittee);
        console.log("Config Provider for old Dual Governance:", configProviderForOldDualGovernance);
        console.log("\n");
        console.log("Timelock:", timelock);
        console.log("Admin Executor:", adminExecutor);
        console.log("Tiebreaker Activation Timeout:", tiebreakerActivationTimeout.toSeconds());
        console.log("Accounting Oracle:", accountingOracle);
        console.log("Validators Exit Bus Oracle:", validatorsExitBusOracle);
        console.log("Reseal Manager:", resealManager);
        console.log("=====================================");
        console.log("\n");

        vm.startBroadcast();
        DGUpgradeStateVerifier dgUpgradeStateVerifier = new DGUpgradeStateVerifier(
            voting,
            newDualGovernance,
            timelock,
            adminExecutor,
            newTiebreakerCoreCommittee,
            tiebreakerActivationTimeout,
            accountingOracle,
            validatorsExitBusOracle,
            resealManager,
            configProviderForOldDualGovernance
        );
        vm.label(address(dgUpgradeStateVerifier), "DG_UPGRADE_STATE_VERIFIER");
        console.log("DGUpgradeStateVerifier deployed successfully at ", address(dgUpgradeStateVerifier));

        DGUpgradeOmnibus dgUpgradeOmnibus = new DGUpgradeOmnibus(
            voting,
            dualGovernance,
            newDualGovernance,
            timelock,
            adminExecutor,
            newTiebreakerCoreCommittee,
            tiebreakerActivationTimeout,
            accountingOracle,
            validatorsExitBusOracle,
            resealManager,
            address(dgUpgradeStateVerifier),
            configProviderForOldDualGovernance
        );
        vm.label(address(dgUpgradeOmnibus), "DG_UPGRADE_OMNIBUS");
        vm.stopBroadcast();

        console.log("DGUpgradeOmnibus deployed successfully at ", address(dgUpgradeOmnibus));
    }
}
