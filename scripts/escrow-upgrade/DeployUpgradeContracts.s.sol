// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {ImmutableDualGovernanceConfigProvider} from "contracts/ImmutableDualGovernanceConfigProvider.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {Escrow} from "contracts/Escrow.sol";

import {DGSetupDeployArtifacts, ContractsDeployment} from "../utils/contracts-deployment.sol";

import {TiebreakerDeployConfig, TiebreakerDeployedContracts} from "../utils/deployment/Tiebreaker.sol";

contract DeployUpgradeContracts is Script {
    using DGSetupDeployArtifacts for DGSetupDeployArtifacts.Context;
    using TiebreakerDeployConfig for TiebreakerDeployConfig.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error InvalidAddress(string key);

    function run() public {
        DGSetupDeployArtifacts.Context memory _deployArtifact;

        string memory deployArtifactFile = vm.envString("DEPLOY_ARTIFACT_FILE_NAME");
        _deployArtifact = DGSetupDeployArtifacts.load(deployArtifactFile);

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        if (_deployArtifact.deployConfig.chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: _deployArtifact.deployConfig.chainId});
        }

        ITimelock timelock = _deployArtifact.deployedContracts.timelock;
        ResealManager resealManager = _deployArtifact.deployedContracts.resealManager;
        ImmutableDualGovernanceConfigProvider configProvider =
            _deployArtifact.deployedContracts.dualGovernanceConfigProvider;

        if (address(timelock) == address(0)) revert InvalidAddress("timelock");
        if (address(resealManager) == address(0)) revert InvalidAddress("reseal_manager");
        if (address(configProvider) == address(0)) revert InvalidAddress("config_provider");

        DualGovernance.DualGovernanceComponents memory components = DualGovernance.DualGovernanceComponents({
            timelock: timelock,
            resealManager: resealManager,
            configProvider: configProvider
        });

        console.log("Deploying DualGovernance...");
        vm.startBroadcast();
        DualGovernance dualGovernance =
            ContractsDeployment.deployDualGovernance(components, _deployArtifact.deployConfig.dualGovernance);
        vm.stopBroadcast();

        _deployArtifact.deployedContracts.dualGovernance = dualGovernance;
        _deployArtifact.deployedContracts.escrowMasterCopy =
            Escrow(payable(address(ISignallingEscrow(dualGovernance.getVetoSignallingEscrow()).ESCROW_MASTER_COPY())));

        console.log("DualGovernance deployed at: %s", address(_deployArtifact.deployedContracts.dualGovernance));

        console.log("Deploying TiebreakerCoreCommittee...");

        address adminExecutor = address(_deployArtifact.deployedContracts.adminExecutor);

        _deployArtifact.deployConfig.tiebreaker.chainId = block.chainid;
        _deployArtifact.deployConfig.tiebreaker.owner = adminExecutor;
        _deployArtifact.deployConfig.tiebreaker.dualGovernance = address(dualGovernance);

        _deployArtifact.deployConfig.tiebreaker.print();
        vm.startBroadcast();
        TiebreakerDeployedContracts.Context memory tiebreakerDeployedContracts =
            ContractsDeployment.deployTiebreaker(_deployArtifact.deployConfig.tiebreaker, deployer);
        vm.stopBroadcast();

        _deployArtifact.deployedContracts.tiebreakerCoreCommittee = tiebreakerDeployedContracts.tiebreakerCoreCommittee;
        _deployArtifact.deployedContracts.tiebreakerSubCommittees = tiebreakerDeployedContracts.tiebreakerSubCommittees;

        console.log("Deployed contracts:");
        console.log();
        console.log("DualGovernance: %s", address(_deployArtifact.deployedContracts.dualGovernance));
        console.log("EscrowMasterCopy: %s", address(_deployArtifact.deployedContracts.escrowMasterCopy));
        console.log("TiebreakerCoreCommittee: %s", address(_deployArtifact.deployedContracts.tiebreakerCoreCommittee));
        console.log("TiebreakerSubCommittees:");
        for (uint256 i = 0; i < _deployArtifact.deployedContracts.tiebreakerSubCommittees.length; i++) {
            console.log(" - %s", address(_deployArtifact.deployedContracts.tiebreakerSubCommittees[i]));
        }

        string memory deployArtifactFileName =
            string.concat("deploy-artifact-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".toml");

        _deployArtifact.save(deployArtifactFileName);
    }
}
