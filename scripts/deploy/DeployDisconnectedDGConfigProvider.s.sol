// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {PercentsD16, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";
import {Durations} from "contracts/types/Duration.sol";

import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";

import {
    ImmutableDualGovernanceConfigProviderDeployConfig,
    ImmutableDualGovernanceConfigProviderDeployArtifacts,
    ImmutableDualGovernanceConfigProviderDeployedContracts
} from "../utils/deployment/ImmutableDualGovernanceConfigProvider.sol";

import {ContractsDeployment} from "../utils/contracts-deployment.sol";

contract DeployDisconnectedDGConfigProvider is Script {
    using ImmutableDualGovernanceConfigProviderDeployConfig for DualGovernanceConfig.Context;
    using
    ImmutableDualGovernanceConfigProviderDeployArtifacts
    for ImmutableDualGovernanceConfigProviderDeployArtifacts.Context;
    using
    ImmutableDualGovernanceConfigProviderDeployedContracts
    for ImmutableDualGovernanceConfigProviderDeployedContracts.Context;

    function run() public {
        ImmutableDualGovernanceConfigProviderDeployArtifacts.Context memory deployArtifact;

        deployArtifact.deployConfig = DualGovernanceConfig.Context({
            firstSealRageQuitSupport: PercentsD16.from(HUNDRED_PERCENT_D16 - 1),
            secondSealRageQuitSupport: PercentsD16.from(HUNDRED_PERCENT_D16),
            minAssetsLockDuration: Durations.from(1),
            vetoSignallingMinDuration: Durations.from(0),
            vetoSignallingMaxDuration: Durations.from(1),
            vetoSignallingMinActiveDuration: Durations.from(0),
            vetoSignallingDeactivationMaxDuration: Durations.from(0),
            vetoCooldownDuration: Durations.from(0),
            rageQuitExtensionPeriodDuration: Durations.from(0),
            rageQuitEthWithdrawalsMinDelay: Durations.from(0),
            rageQuitEthWithdrawalsMaxDelay: Durations.from(0),
            rageQuitEthWithdrawalsDelayGrowth: Durations.from(0)
        });

        deployArtifact.deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        vm.startBroadcast();

        deployArtifact.deployedContracts.dualGovernanceConfigProvider =
            ContractsDeployment.deployDualGovernanceConfigProvider(deployArtifact.deployConfig);

        vm.stopBroadcast();

        console.log("");
        console.log("Disconnected Dual Governance Config Provider deployed successfully");
        deployArtifact.deployedContracts.print();

        string memory deployArtifactFileName = string.concat(
            "deploy-artifact-disconnected-dg-config-provider-",
            vm.toString(block.chainid),
            "-",
            vm.toString(block.timestamp),
            ".toml"
        );

        deployArtifact.save(deployArtifactFileName);
    }
}
