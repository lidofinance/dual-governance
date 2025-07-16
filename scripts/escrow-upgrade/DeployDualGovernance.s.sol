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

import {
    DualGovernanceContractDeployConfig,
    TiebreakerDeployConfig,
    DGSetupDeployArtifacts,
    TiebreakerDeployedContracts,
    ContractsDeployment,
    DGSetupDeployedContracts
} from "../utils/contracts-deployment.sol";
import {ConfigFileReader, ConfigFileBuilder, JsonKeys} from "../utils/ConfigFiles.sol";
import {DeployFiles} from "scripts/utils/DeployFiles.sol";

contract DeployDualGovernance is Script {
    using DualGovernanceContractDeployConfig for DualGovernanceContractDeployConfig.Context;
    using JsonKeys for string;
    using TiebreakerDeployConfig for TiebreakerDeployConfig.Context;
    using TiebreakerDeployedContracts for TiebreakerDeployedContracts.Context;
    using DGSetupDeployArtifacts for DGSetupDeployArtifacts.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error InvalidAddress(string key);

    struct DeployConfig {
        uint256 chainId;
        ITimelock timelock;
        ResealManager resealManager;
        ImmutableDualGovernanceConfigProvider configProvider;
        DualGovernanceContractDeployConfig.Context dualGovernanceConfig;
        TiebreakerDeployConfig.Context tiebreakerConfig;
    }

    struct DeployedContracts {
        DualGovernance dualGovernance;
        TiebreakerDeployedContracts.Context tiebreakerDeployedContracts;
    }

    function run() public {
        DGSetupDeployArtifacts.Context memory _deployArtifact;
        DeployConfig memory _deployConfig;

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        string memory artifactFileName = vm.envString("DEPLOY_ARTIFACT_FILE_NAME");
        console.log("Loading config from artifact file: %s", artifactFileName);
        console.log("\n");
        console.log("=================================================");

        _deployArtifact = DGSetupDeployArtifacts.load(artifactFileName);

        if (_deployArtifact.deployConfig.chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: _deployArtifact.deployConfig.chainId});
        }

        _deployConfig.timelock = _deployArtifact.deployedContracts.timelock;
        _deployConfig.resealManager = _deployArtifact.deployedContracts.resealManager;
        _deployConfig.configProvider = _deployArtifact.deployedContracts.dualGovernanceConfigProvider;

        if (address(_deployConfig.timelock) == address(0)) revert InvalidAddress("timelock");
        if (address(_deployConfig.resealManager) == address(0)) revert InvalidAddress("reseal_manager");
        if (address(_deployConfig.configProvider) == address(0)) revert InvalidAddress("config_provider");

        _deployConfig.dualGovernanceConfig = _deployArtifact.deployConfig.dualGovernance;
        _deployConfig.dualGovernanceConfig.validate();

        _deployConfig.dualGovernanceConfig.print();

        DualGovernance.DualGovernanceComponents memory components = DualGovernance.DualGovernanceComponents({
            timelock: _deployConfig.timelock,
            resealManager: _deployConfig.resealManager,
            configProvider: _deployConfig.configProvider
        });

        console.log("Deploying DualGovernance...");
        vm.startBroadcast();
        DualGovernance dualGovernance = new DualGovernance(
            components,
            _deployConfig.dualGovernanceConfig.signallingTokens,
            _deployConfig.dualGovernanceConfig.sanityCheckParams
        );
        vm.stopBroadcast();

        _deployArtifact.deployedContracts.dualGovernance = dualGovernance;
        _deployArtifact.deployedContracts.escrowMasterCopy =
            Escrow(payable(address(ISignallingEscrow(dualGovernance.getVetoSignallingEscrow()).ESCROW_MASTER_COPY())));

        console.log("DualGovernance deployed at: %s", address(_deployArtifact.deployedContracts.dualGovernance));

        _deployConfig.tiebreakerConfig.chainId = _deployArtifact.deployConfig.chainId;
        _deployConfig.tiebreakerConfig.owner = address(_deployArtifact.deployedContracts.adminExecutor);
        _deployConfig.tiebreakerConfig.dualGovernance = address(_deployArtifact.deployedContracts.dualGovernance);

        _deployConfig.tiebreakerConfig.config = _deployArtifact.deployConfig.tiebreaker;

        console.log("=================================================");

        _deployConfig.tiebreakerConfig.print();

        console.log("Deploying TiebreakerCoreCommittee...");

        vm.startBroadcast();
        TiebreakerDeployedContracts.Context memory tiebreakerDeployedContracts =
            ContractsDeployment.deployTiebreaker(_deployConfig.tiebreakerConfig, deployer);
        vm.stopBroadcast();

        _deployArtifact.deployedContracts.tiebreakerCoreCommittee = tiebreakerDeployedContracts.tiebreakerCoreCommittee;
        _deployArtifact.deployedContracts.tiebreakerSubCommittees = tiebreakerDeployedContracts.tiebreakerSubCommittees;

        _deployArtifact.deployedContracts.print();

        string memory deployArtifactFileName =
            string.concat("deploy-artifact-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".toml");
        console.log("=================================================");
        console.log("Saving deploy artifact to: %s", deployArtifactFileName);
        _deployArtifact.save(deployArtifactFileName);
    }
}
