// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {ImmutableDualGovernanceConfigProvider} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {ConfigFileReader, ConfigFileBuilder, JsonKeys} from "../ConfigFiles.sol";
import {DeployFiles} from "../DeployFiles.sol";
import {DecimalsFormatting} from "test/utils/formatting.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

using JsonKeys for string;
using ConfigFileReader for ConfigFileReader.Context;
using ConfigFileBuilder for ConfigFileBuilder.Context;

// solhint-disable-next-line const-name-snakecase
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

library ImmutableDualGovernanceConfigProviderDeployConfig {
    using DualGovernanceConfig for DualGovernanceConfig.Context;
    using DecimalsFormatting for PercentD16;

    error InvalidChainId(uint256 actual, uint256 expected);

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (DualGovernanceConfig.Context memory ctx) {
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        string memory $ = configRootKey.root();

        return DualGovernanceConfig.Context({
            firstSealRageQuitSupport: PercentsD16.from(file.readUint($.key("first_seal_rage_quit_support"))),
            secondSealRageQuitSupport: PercentsD16.from(file.readUint($.key("second_seal_rage_quit_support"))),
            minAssetsLockDuration: file.readDuration($.key("min_assets_lock_duration")),
            vetoSignallingMinDuration: file.readDuration($.key("veto_signalling_min_duration")),
            vetoSignallingMinActiveDuration: file.readDuration($.key("veto_signalling_min_active_duration")),
            vetoSignallingMaxDuration: file.readDuration($.key("veto_signalling_max_duration")),
            vetoSignallingDeactivationMaxDuration: file.readDuration($.key("veto_signalling_deactivation_max_duration")),
            vetoCooldownDuration: file.readDuration($.key("veto_cooldown_duration")),
            rageQuitEthWithdrawalsDelayGrowth: file.readDuration($.key("rage_quit_eth_withdrawals_delay_growth")),
            rageQuitEthWithdrawalsMaxDelay: file.readDuration($.key("rage_quit_eth_withdrawals_max_delay")),
            rageQuitEthWithdrawalsMinDelay: file.readDuration($.key("rage_quit_eth_withdrawals_min_delay")),
            rageQuitExtensionPeriodDuration: file.readDuration($.key("rage_quit_extension_period_duration"))
        });
    }

    function validate(DualGovernanceConfig.Context memory ctx) internal pure {
        DualGovernanceConfig.validate(ctx);
    }

    function toJSON(DualGovernanceConfig.Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();
        // forgefmt: disable-next-item
        {
            builder.set("first_seal_rage_quit_support", ctx.firstSealRageQuitSupport.toUint256());
            builder.set("second_seal_rage_quit_support", ctx.secondSealRageQuitSupport.toUint256());

            builder.set("min_assets_lock_duration", ctx.minAssetsLockDuration);

            builder.set("veto_signalling_min_duration", ctx.vetoSignallingMinDuration);
            builder.set("veto_signalling_min_active_duration", ctx.vetoSignallingMinActiveDuration);
            builder.set("veto_signalling_max_duration", ctx.vetoSignallingMaxDuration);
            builder.set("veto_signalling_deactivation_max_duration", ctx.vetoSignallingDeactivationMaxDuration);
            builder.set("veto_cooldown_duration", ctx.vetoCooldownDuration);

            builder.set("rage_quit_eth_withdrawals_delay_growth", ctx.rageQuitEthWithdrawalsDelayGrowth);
            builder.set("rage_quit_eth_withdrawals_max_delay", ctx.rageQuitEthWithdrawalsMaxDelay);
            builder.set("rage_quit_eth_withdrawals_min_delay",ctx.rageQuitEthWithdrawalsMinDelay);
            builder.set("rage_quit_extension_period_duration", ctx.rageQuitExtensionPeriodDuration);
        }

        return builder.content;
    }

    function print(DualGovernanceConfig.Context memory ctx) internal pure {
        console.log("===== DualGovernanceConfigProvider");
        console.log("First seal rage quit support", ctx.firstSealRageQuitSupport.format());
        console.log("Second seal rage quit support", ctx.secondSealRageQuitSupport.format());
        console.log("Min assets lock duration", ctx.minAssetsLockDuration.toSeconds());
        console.log("\n");
        console.log("Rage quit ETH withdrawals delay growth", ctx.rageQuitEthWithdrawalsDelayGrowth.toSeconds());
        console.log("Rage quit ETH withdrawals min delay", ctx.rageQuitEthWithdrawalsMinDelay.toSeconds());
        console.log("Rage quit ETH withdrawals max delay", ctx.rageQuitEthWithdrawalsMaxDelay.toSeconds());
        console.log("Rage quit extension period duration", ctx.rageQuitExtensionPeriodDuration.toSeconds());
        console.log("\n");
        console.log("Veto signalling min active duration", ctx.vetoSignallingMinActiveDuration.toSeconds());
        console.log("Veto signalling deactivation max duration", ctx.vetoSignallingDeactivationMaxDuration.toSeconds());
        console.log("Veto signalling max duration", ctx.vetoSignallingMaxDuration.toSeconds());
        console.log("Veto cooldown duration", ctx.vetoCooldownDuration.toSeconds());
        console.log("Veto signalling min duration", ctx.vetoSignallingMinDuration.toSeconds());
        console.log("\n");
    }
}

library ImmutableDualGovernanceConfigProviderDeployedContracts {
    struct Context {
        ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider;
    }

    function load(
        string memory deployedContractsFilePath,
        string memory prefix
    ) internal view returns (Context memory ctx) {
        string memory $ = prefix.root();
        ConfigFileReader.Context memory deployedContract = ConfigFileReader.load(deployedContractsFilePath);

        ctx.dualGovernanceConfigProvider = ImmutableDualGovernanceConfigProvider(
            deployedContract.readAddress($.key("dual_governance_config_provider"))
        );
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();
        builder.set("dual_governance_config_provider", address(ctx.dualGovernanceConfigProvider));
        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("ImmutableDualGovernanceConfigProvider address", address(ctx.dualGovernanceConfigProvider));
    }
}

library ImmutableDualGovernanceConfigProviderDeployArtifacts {
    using ImmutableDualGovernanceConfigProviderDeployConfig for DualGovernanceConfig.Context;
    using
    ImmutableDualGovernanceConfigProviderDeployedContracts
    for ImmutableDualGovernanceConfigProviderDeployedContracts.Context;

    struct Context {
        DualGovernanceConfig.Context deployConfig;
        ImmutableDualGovernanceConfigProviderDeployedContracts.Context deployedContracts;
    }

    function load(string memory deployArtifactFileName) internal view returns (Context memory ctx) {
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(deployArtifactFileName);
        ctx.deployConfig =
            ImmutableDualGovernanceConfigProviderDeployConfig.load(deployArtifactFilePath, "deploy_config");
        ctx.deployedContracts =
            ImmutableDualGovernanceConfigProviderDeployedContracts.load(deployArtifactFilePath, "deployed_contracts");
    }

    function validate(Context memory ctx) internal view {
        ctx.deployConfig.validate();
    }

    function save(Context memory ctx, string memory fileName) internal {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(fileName);

        // forgefmt: disable-next-item
        configBuilder
            .set("chain_id", vm.toString(block.chainid))
            .set("deploy_config", ctx.deployConfig.toJSON())
            .set("deployed_contracts", ctx.deployedContracts.toJSON())
            .write(deployArtifactFilePath);

        console.log("\n");
        console.log("Deploy artifact saved to: %s", deployArtifactFilePath);
    }
}
