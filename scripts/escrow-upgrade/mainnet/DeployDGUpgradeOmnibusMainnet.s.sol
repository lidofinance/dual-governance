// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Duration} from "contracts/types/Duration.sol";

import {DGDeployArtifactLoader} from "scripts/utils/DGDeployArtifactLoader.sol";
import {DGSetupDeployArtifacts} from "scripts/utils/contracts-deployment.sol";
import {DGLaunchConfig} from "scripts/utils/contracts-deployment.sol";

import {DGUpgradeOmnibus} from "../DGUpgradeOmnibus.sol";
import {DGUpgradeStateVerifier} from "../DGUpgradeStateVerifier.sol";

import {console} from "forge-std/console.sol";

contract DeployDGUpgradeOmnibusMainnet is DGDeployArtifactLoader {
    address constant VOTING = 0x2e59A20f205bB85a89C53f1936454680651E618e;

    function run() public {
        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        DGSetupDeployArtifacts.Context memory _deployArtifact = _loadEnv();

        address dualGovernance = address(_deployArtifact.deployedContracts.dualGovernance);
        address timelock = address(_deployArtifact.deployedContracts.timelock);
        address adminExecutor = address(_deployArtifact.deployedContracts.adminExecutor);
        address tiebreakerCoreCommittee = address(_deployArtifact.deployedContracts.tiebreakerCoreCommittee);
        Duration tiebreakerActivationTimeout = _deployArtifact.deployConfig.dualGovernance.tiebreakerActivationTimeout;
        address accountingOracle = _deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[0];
        address validatorsExitBusOracle = _deployArtifact.deployConfig.dualGovernance.sealableWithdrawalBlockers[1];
        address resealManager = address(_deployArtifact.deployedContracts.resealManager);

        console.log("=====================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", msg.sender);
        console.log("=====================================");
        console.log("Deploying omnibus builder contract with the following params:\n");
        console.log("=====================================");
        console.log("Voting:", VOTING);
        console.log("Dual Governance:", dualGovernance);
        console.log("Timelock:", timelock);
        console.log("Admin Executor:", adminExecutor);
        console.log("Tiebreaker Core Committee:", tiebreakerCoreCommittee);
        console.log("Tiebreaker Activation Timeout:", tiebreakerActivationTimeout.toSeconds());
        console.log("Accounting Oracle:", accountingOracle);
        console.log("Validators Exit Bus Oracle:", validatorsExitBusOracle);
        console.log("Reseal Manager:", resealManager);
        console.log("=====================================");
        console.log("\n");

        vm.startBroadcast();
        DGUpgradeStateVerifier dgUpgradeStateVerifier = new DGUpgradeStateVerifier(
            VOTING,
            dualGovernance,
            timelock,
            adminExecutor,
            tiebreakerCoreCommittee,
            tiebreakerActivationTimeout,
            accountingOracle,
            validatorsExitBusOracle,
            resealManager
        );
        vm.label(address(dgUpgradeStateVerifier), "DG_UPGRADE_STATE_VERIFIER");
        console.log("DGUpgradeStateVerifier deployed successfully at ", address(dgUpgradeStateVerifier));

        DGUpgradeOmnibus dgUpgradeOmnibus = new DGUpgradeOmnibus(
            VOTING,
            dualGovernance,
            timelock,
            adminExecutor,
            tiebreakerCoreCommittee,
            tiebreakerActivationTimeout,
            accountingOracle,
            validatorsExitBusOracle,
            resealManager,
            address(dgUpgradeStateVerifier)
        );
        vm.label(address(dgUpgradeOmnibus), "DG_UPGRADE_OMNIBUS");
        vm.stopBroadcast();

        console.log("DGUpgradeOmnibus deployed successfully at ", address(dgUpgradeOmnibus));
    }
}
