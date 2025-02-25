// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */
import {console} from "forge-std/console.sol";

import {DGDeployArtifactLoader} from "../utils/DGDeployArtifactLoader.sol";
import {DGSetupDeployArtifacts} from "../utils/contracts-deployment.sol";

import {Voting} from "./Voting.sol";

contract DeployVoting is DGDeployArtifactLoader {
    function run() public {
        vm.label(msg.sender, "DEPLOYER");

        DGSetupDeployArtifacts.Context memory _deployArtifact = _loadEnv();

        address dualGovernance = address(_deployArtifact.deployedContracts.dualGovernance);
        address adminExecutor = address(_deployArtifact.deployedContracts.adminExecutor);
        address resealManager = address(_deployArtifact.deployedContracts.resealManager);
        console.log("\n\n");
        console.log("Deploying Voting contract with the following params:\n");
        console.log("=====================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", msg.sender);
        console.log("\n");
        console.log("Dual Governance:", dualGovernance);
        console.log("Admin Executor:", adminExecutor);
        console.log("Reseal Manager:", resealManager);
        console.log("=====================================");

        vm.startBroadcast();

        Voting votingCalldataBuilder =
            new Voting({dualGovernance: dualGovernance, adminExecutor: adminExecutor, resealManager: resealManager});

        console.log("Deploying Voting calldata builder...");

        vm.stopBroadcast();

        console.log("Voting calldata builder contract deployed successfully at", address(votingCalldataBuilder));
    }
}
