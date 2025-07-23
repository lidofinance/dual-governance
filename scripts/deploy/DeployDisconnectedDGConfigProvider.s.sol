// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {PercentsD16, PercentD16, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";

import {
    ImmutableDualGovernanceConfigProviderDeployConfig,
    ImmutableDualGovernanceConfigProviderDeployArtifacts,
    ImmutableDualGovernanceConfigProviderDeployedContracts,
    ContractsDeployment
} from "../utils/contracts-deployment.sol";

contract DeployDisconnectedDGConfigProvider is Script {
    using
    ImmutableDualGovernanceConfigProviderDeployConfig
    for ImmutableDualGovernanceConfigProviderDeployConfig.Context;
    using
    ImmutableDualGovernanceConfigProviderDeployArtifacts
    for ImmutableDualGovernanceConfigProviderDeployArtifacts.Context;
    using
    ImmutableDualGovernanceConfigProviderDeployedContracts
    for ImmutableDualGovernanceConfigProviderDeployedContracts.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    ImmutableDualGovernanceConfigProviderDeployArtifacts.Context internal _deployArtifact;

    function run() public {
        _deployArtifact.deployConfig.config = DualGovernanceConfig.Context({
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

        _deployArtifact.deployConfig.chainId = block.chainid;

        _deployArtifact.deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        vm.startBroadcast();

        _deployArtifact.deployedContracts.dualGovernanceConfigProvider =
            ContractsDeployment.deployDualGovernanceConfigProvider(_deployArtifact.deployConfig.config);

        vm.stopBroadcast();

        console.log("\n");
        console.log("Disconnected Dual Governance Config Provider deployed successfully");
        _deployArtifact.deployedContracts.print();

        string memory deployArtifactFileName = string.concat(
            "deploy-artifact-disconnected-dg-config-provider-",
            vm.toString(block.chainid),
            "-",
            vm.toString(block.timestamp),
            ".toml"
        );

        _deployArtifact.save(deployArtifactFileName);
    }
}
