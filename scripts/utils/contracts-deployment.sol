// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Executor} from "contracts/Executor.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {ImmutableDualGovernanceConfigProvider} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

import {DeployFiles} from "./deploy-files.sol";
import {ConfigFileReader, ConfigFileBuilder, JsonKeys} from "./config-files.sol";

// solhint-disable-next-line const-name-snakecase
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

error InvalidParameter(string parameter);
error InvalidChainId(uint256 actual, uint256 expected);

using JsonKeys for string;
using ConfigFileBuilder for ConfigFileBuilder.Context;

library TimelockContractDeployConfig {
    using ConfigFileReader for ConfigFileReader.Context;

    struct Context {
        Duration afterSubmitDelay;
        Duration afterScheduleDelay;
        EmergencyProtectedTimelock.SanityCheckParams sanityCheckParams;
        Duration emergencyModeDuration;
        Timestamp emergencyProtectionEndDate;
        address emergencyGovernanceProposer;
        address emergencyActivationCommittee;
        address emergencyExecutionCommittee;
    }

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (Context memory ctx) {
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        string memory $ = configRootKey.root();
        string memory $sanityCheckParams = $.key("sanity_check_params");
        string memory $emergencyProtection = $.key("emergency_protection");

        return Context({
            afterSubmitDelay: file.readDuration($.key("after_submit_delay")),
            afterScheduleDelay: file.readDuration($.key("after_schedule_delay")),
            sanityCheckParams: EmergencyProtectedTimelock.SanityCheckParams({
                minExecutionDelay: file.readDuration($sanityCheckParams.key("min_execution_delay")),
                maxAfterSubmitDelay: file.readDuration($sanityCheckParams.key("max_after_submit_delay")),
                maxAfterScheduleDelay: file.readDuration($sanityCheckParams.key("max_after_schedule_delay")),
                maxEmergencyModeDuration: file.readDuration($sanityCheckParams.key("max_emergency_mode_duration")),
                maxEmergencyProtectionDuration: file.readDuration($sanityCheckParams.key("max_emergency_protection_duration"))
            }),
            emergencyGovernanceProposer: file.readAddress($emergencyProtection.key("emergency_governance_proposer")),
            emergencyActivationCommittee: file.readAddress($emergencyProtection.key("emergency_activation_committee")),
            emergencyExecutionCommittee: file.readAddress($emergencyProtection.key("emergency_execution_committee")),
            emergencyModeDuration: file.readDuration($emergencyProtection.key("emergency_mode_duration")),
            emergencyProtectionEndDate: file.readTimestamp($emergencyProtection.key("emergency_protection_end_date"))
        });
    }

    function validate(Context memory ctx) internal pure {
        if (ctx.afterSubmitDelay > ctx.sanityCheckParams.maxAfterSubmitDelay) {
            revert InvalidParameter("after_submit_delay");
        }

        if (ctx.afterScheduleDelay > ctx.sanityCheckParams.maxAfterScheduleDelay) {
            revert InvalidParameter("after_schedule_delay");
        }

        if (ctx.emergencyModeDuration > ctx.sanityCheckParams.maxEmergencyModeDuration) {
            revert InvalidParameter("emergency_mode_duration");
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("after_schedule_delay", ctx.afterScheduleDelay);
        builder.set("after_submit_delay", ctx.afterSubmitDelay);
        builder.set("sanity_check_params", _sanityCheckParamsToJSON(ctx));
        builder.set("emergency_protection", _emergencyProtectionToJSON(ctx));

        return builder.content;
    }

    function _sanityCheckParamsToJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("min_execution_delay", ctx.sanityCheckParams.minExecutionDelay);
        builder.set("max_after_submit_delay", ctx.sanityCheckParams.maxAfterSubmitDelay);
        builder.set("max_after_schedule_delay", ctx.sanityCheckParams.maxAfterScheduleDelay);
        builder.set("max_emergency_mode_duration", ctx.sanityCheckParams.maxEmergencyModeDuration);
        builder.set("max_emergency_protection_duration", ctx.sanityCheckParams.maxEmergencyProtectionDuration);

        return builder.content;
    }

    function _emergencyProtectionToJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("emergency_mode_duration", ctx.emergencyModeDuration);
        builder.set("emergency_protection_end_date", ctx.emergencyProtectionEndDate);
        builder.set("emergency_governance_proposer", ctx.emergencyGovernanceProposer);
        builder.set("emergency_activation_committee", ctx.emergencyActivationCommittee);
        builder.set("emergency_execution_committee", ctx.emergencyExecutionCommittee);

        return builder.content;
    }
}

struct TiebreakerCommitteeDeployConfig {
    uint256 quorum;
    address[] members;
}

library TiebreakerContractDeployConfig {
    using ConfigFileReader for ConfigFileReader.Context;

    struct Context {
        uint256 quorum;
        uint256 committeesCount;
        Duration executionDelay;
        TiebreakerCommitteeDeployConfig[] committees;
    }

    function load(string memory configFilePath, string memory configRootKey) internal view returns (Context memory) {
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        string memory $ = JsonKeys.root(configRootKey);

        uint256 tiebreakerCommitteesCount = file.readUint($.key("committees_count"));

        TiebreakerCommitteeDeployConfig[] memory tiebreakerCommitteeConfigs =
            new TiebreakerCommitteeDeployConfig[](tiebreakerCommitteesCount);

        for (uint256 i = 0; i < tiebreakerCommitteeConfigs.length; ++i) {
            string memory $committees = $.index("committees", i);
            tiebreakerCommitteeConfigs[i].quorum = file.readUint($committees.key("quorum"));
            tiebreakerCommitteeConfigs[i].members = file.readAddressArray($committees.key("members"));
        }

        return Context({
            quorum: file.readUint($.key("quorum")),
            executionDelay: file.readDuration($.key("execution_delay")),
            committeesCount: tiebreakerCommitteesCount,
            committees: tiebreakerCommitteeConfigs
        });
    }

    function validate(Context memory ctx) internal pure {
        if (ctx.quorum == 0 || ctx.quorum > ctx.committeesCount) {
            revert InvalidParameter("tiebreaker.quorum");
        }

        if (ctx.committeesCount != ctx.committees.length) {
            revert InvalidParameter("tiebreaker.committees_count");
        }

        for (uint256 i = 0; i < ctx.committeesCount; ++i) {
            if (ctx.committees[i].quorum == 0 || ctx.committees[i].quorum > ctx.committees[i].members.length) {
                revert InvalidParameter(string.concat("tiebreaker.committees[", vm.toString(i), "].quorum"));
            }
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        string[] memory tiebreakerCommitteesContent = new string[](ctx.committees.length);

        for (uint256 i = 0; i < tiebreakerCommitteesContent.length; ++i) {
            // forgefmt: disable-next-item
            tiebreakerCommitteesContent[i] = ConfigFileBuilder.create()
                .set("quorum", ctx.committees[i].quorum)
                .set("members", ctx.committees[i].members)
                .content;
        }

        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("quorum", ctx.quorum);
        builder.set("committees_count", ctx.committeesCount);
        builder.set("execution_delay", ctx.executionDelay);
        builder.set("committees", tiebreakerCommitteesContent);

        return builder.content;
    }
}

library DualGovernanceContractDeployConfig {
    using ConfigFileReader for ConfigFileReader.Context;

    struct Context {
        address adminProposer;
        address resealCommittee;
        address proposalsCanceller;
        address[] sealableWithdrawalBlockers;
        Duration tiebreakerActivationTimeout;
        DualGovernance.SignallingTokens signallingTokens;
        DualGovernance.SanityCheckParams sanityCheckParams;
    }

    function load(string memory configFilePath, string memory configRootKey) internal view returns (Context memory) {
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        string memory $ = configRootKey.root();
        // solhint-disable-next-line var-name-mixedcase
        string memory $sanity_check = $.key("sanity_check_params");
        // solhint-disable-next-line var-name-mixedcase
        string memory $signalling_tokens = $.key("signalling_tokens");

        return Context({
            adminProposer: file.readAddress($.key("admin_proposer")),
            resealCommittee: file.readAddress($.key("reseal_committee")),
            proposalsCanceller: file.readAddress($.key("proposals_canceller")),
            tiebreakerActivationTimeout: file.readDuration($.key("tiebreaker_activation_timeout")),
            sealableWithdrawalBlockers: file.readAddressArray($.key("sealable_withdrawal_blockers")),
            sanityCheckParams: DualGovernance.SanityCheckParams({
                minWithdrawalsBatchSize: file.readUint($sanity_check.key("min_withdrawals_batch_size")),
                minTiebreakerActivationTimeout: file.readDuration($sanity_check.key("min_tiebreaker_activation_timeout")),
                maxTiebreakerActivationTimeout: file.readDuration($sanity_check.key("max_tiebreaker_activation_timeout")),
                maxSealableWithdrawalBlockersCount: file.readUint($sanity_check.key("max_sealable_withdrawal_blockers_count")),
                maxMinAssetsLockDuration: file.readDuration($sanity_check.key("max_min_assets_lock_duration"))
            }),
            signallingTokens: DualGovernance.SignallingTokens({
                stETH: IStETH(file.readAddress($signalling_tokens.key("st_eth"))),
                wstETH: IWstETH(file.readAddress($signalling_tokens.key("wst_eth"))),
                withdrawalQueue: IWithdrawalQueue(file.readAddress($signalling_tokens.key("withdrawal_queue")))
            })
        });
    }

    function validate(Context memory ctx) internal pure {
        if (ctx.sanityCheckParams.minTiebreakerActivationTimeout > ctx.sanityCheckParams.maxTiebreakerActivationTimeout)
        {
            revert InvalidParameter("dual_governance.sanity_check_params.min_activation_timeout");
        }

        if (
            ctx.tiebreakerActivationTimeout > ctx.sanityCheckParams.maxTiebreakerActivationTimeout
                || ctx.tiebreakerActivationTimeout < ctx.sanityCheckParams.minTiebreakerActivationTimeout
        ) {
            revert InvalidParameter("dual_governance.tiebreaker.activation_timeout");
        }

        if (ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount == 0) {
            revert InvalidParameter("max_sealable_withdrawal_blockers_count");
        }

        if (ctx.sealableWithdrawalBlockers.length > ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount) {
            revert InvalidParameter("tiebreaker.sealable_withdrawal_blockers");
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();
        // forgefmt: disable-next-item
        {
            ConfigFileBuilder.Context memory sanityCheckParamsBuilder = ConfigFileBuilder.create();

            sanityCheckParamsBuilder.set("min_withdrawals_batch_size", ctx.sanityCheckParams.minWithdrawalsBatchSize);
            sanityCheckParamsBuilder.set("min_tiebreaker_activation_timeout", ctx.sanityCheckParams.minTiebreakerActivationTimeout);
            sanityCheckParamsBuilder.set("max_tiebreaker_activation_timeout", ctx.sanityCheckParams.maxTiebreakerActivationTimeout);
            sanityCheckParamsBuilder.set("max_sealable_withdrawal_blockers_count", ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount);
            sanityCheckParamsBuilder.set("max_min_assets_lock_duration", ctx.sanityCheckParams.maxMinAssetsLockDuration);

            ConfigFileBuilder.Context memory signallingTokensBuilder = ConfigFileBuilder.create();

            signallingTokensBuilder.set("st_eth", address(ctx.signallingTokens.stETH));
            signallingTokensBuilder.set("wst_eth", address(ctx.signallingTokens.wstETH));
            signallingTokensBuilder.set("withdrawal_queue", address(ctx.signallingTokens.withdrawalQueue));

            builder.set("admin_proposer", ctx.adminProposer);
            builder.set("reseal_committee", ctx.resealCommittee);
            builder.set("proposals_canceller", ctx.proposalsCanceller);
            builder.set("signalling_tokens", signallingTokensBuilder.content);
            builder.set("sanity_check_params", sanityCheckParamsBuilder.content);
            builder.set("tiebreaker_activation_timeout", ctx.tiebreakerActivationTimeout);
            builder.set("sealable_withdrawal_blockers", ctx.sealableWithdrawalBlockers);
        }

        return builder.content;
    }
}

library DualGovernanceConfigProviderContractDeployConfig {
    using ConfigFileReader for ConfigFileReader.Context;

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (DualGovernanceConfig.Context memory ctx) {
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);
        string memory $ = configRootKey.root();

        return DualGovernanceConfig.Context({
            firstSealRageQuitSupport: file.readPercentD16BP($.key("first_seal_rage_quit_support")),
            secondSealRageQuitSupport: file.readPercentD16BP($.key("second_seal_rage_quit_support")),
            //
            minAssetsLockDuration: file.readDuration($.key("min_assets_lock_duration")),
            //
            vetoSignallingMinDuration: file.readDuration($.key("veto_signalling_min_duration")),
            vetoSignallingMaxDuration: file.readDuration($.key("veto_signalling_max_duration")),
            vetoSignallingMinActiveDuration: file.readDuration($.key("veto_signalling_min_active_duration")),
            vetoSignallingDeactivationMaxDuration: file.readDuration($.key("veto_signalling_max_duration")),
            vetoCooldownDuration: file.readDuration($.key("veto_cooldown_duration")),
            //
            rageQuitExtensionPeriodDuration: file.readDuration($.key("rage_quit_extension_period_duration")),
            rageQuitEthWithdrawalsMinDelay: file.readDuration($.key("rage_quit_eth_withdrawals_min_delay")),
            rageQuitEthWithdrawalsMaxDelay: file.readDuration($.key("rage_quit_eth_withdrawals_max_delay")),
            rageQuitEthWithdrawalsDelayGrowth: file.readDuration($.key("rage_quit_eth_withdrawals_delay_growth"))
        });
    }

    function validate(DualGovernanceConfig.Context memory ctx) internal pure {
        DualGovernanceConfig.validate(ctx);
    }

    function toJSON(DualGovernanceConfig.Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        // forgefmt: disable-next-item
        {
            builder.set("first_seal_rage_quit_support", ctx.firstSealRageQuitSupport.toUint256() / 1e14);
            builder.set("second_seal_rage_quit_support", ctx.secondSealRageQuitSupport.toUint256() / 1e14);

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
}

library DGSetupDeployConfig {
    using ConfigFileReader for ConfigFileReader.Context;
    using TimelockContractDeployConfig for TimelockContractDeployConfig.Context;
    using TiebreakerContractDeployConfig for TiebreakerContractDeployConfig.Context;
    using DualGovernanceContractDeployConfig for DualGovernanceContractDeployConfig.Context;
    using DualGovernanceConfigProviderContractDeployConfig for DualGovernanceConfig.Context;

    struct Context {
        uint256 chainId;
        TimelockContractDeployConfig.Context timelock;
        TiebreakerContractDeployConfig.Context tiebreaker;
        DualGovernanceContractDeployConfig.Context dualGovernance;
        DualGovernanceConfig.Context dualGovernanceConfigProvider;
    }

    function load(string memory configFilePath) internal view returns (Context memory ctx) {
        return load(configFilePath, "");
    }

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (Context memory ctx) {
        string memory $ = configRootKey.root();
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        ctx.chainId = file.readUint($.key("chain_id"));
        ctx.timelock = TimelockContractDeployConfig.load(configFilePath, $.key("timelock"));
        ctx.tiebreaker = TiebreakerContractDeployConfig.load(configFilePath, $.key("tiebreaker"));
        ctx.dualGovernance = DualGovernanceContractDeployConfig.load(configFilePath, $.key("dual_governance"));
        ctx.dualGovernanceConfigProvider = DualGovernanceConfigProviderContractDeployConfig.load(
            configFilePath, $.key("dual_governance_config_provider")
        );
    }

    function validate(Context memory ctx) internal pure {
        ctx.timelock.validate();
        ctx.tiebreaker.validate();
        ctx.dualGovernance.validate();
        ctx.dualGovernanceConfigProvider.validate();
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("chain_id", ctx.chainId);
        builder.set("timelock", ctx.timelock.toJSON());
        builder.set("tiebreaker", ctx.tiebreaker.toJSON());
        builder.set("dual_governance", ctx.dualGovernance.toJSON());
        builder.set("dual_governance_config_provider", ctx.dualGovernanceConfigProvider.toJSON());

        return builder.content;
    }
}

library DGSetupDeployedContracts {
    using JsonKeys for string;
    using ConfigFileReader for ConfigFileReader.Context;
    using ConfigFileBuilder for ConfigFileBuilder.Context;

    struct Context {
        Executor adminExecutor;
        Escrow escrowMasterCopy;
        EmergencyProtectedTimelock timelock;
        TimelockedGovernance emergencyGovernance;
        ResealManager resealManager;
        DualGovernance dualGovernance;
        ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider;
        TiebreakerCoreCommittee tiebreakerCoreCommittee;
        TiebreakerSubCommittee[] tiebreakerSubCommittees;
    }

    function load(
        string memory deployedContractsFilePath,
        string memory prefix
    ) internal view returns (Context memory ctx) {
        string memory $ = prefix.root();
        ConfigFileReader.Context memory deployedContract = ConfigFileReader.load(deployedContractsFilePath);

        ctx.adminExecutor = Executor(payable(deployedContract.readAddress($.key("admin_executor"))));
        ctx.timelock = EmergencyProtectedTimelock(deployedContract.readAddress($.key("timelock")));
        ctx.emergencyGovernance = TimelockedGovernance(deployedContract.readAddress($.key("emergency_governance")));
        ctx.resealManager = ResealManager(deployedContract.readAddress($.key("reseal_manager")));
        ctx.dualGovernance = DualGovernance(deployedContract.readAddress($.key("dual_governance")));
        ctx.escrowMasterCopy = Escrow(payable(deployedContract.readAddress($.key("escrow_master_copy"))));
        ctx.dualGovernanceConfigProvider = ImmutableDualGovernanceConfigProvider(
            deployedContract.readAddress($.key("dual_governance_config_provider"))
        );
        ctx.tiebreakerCoreCommittee =
            TiebreakerCoreCommittee(deployedContract.readAddress($.key("tiebreaker_core_committee")));

        address[] memory tiebreakerSubCommittees = deployedContract.readAddressArray($.key("tiebreaker_sub_committees"));
        ctx.tiebreakerSubCommittees = new TiebreakerSubCommittee[](tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            ctx.tiebreakerSubCommittees[i] = TiebreakerSubCommittee(tiebreakerSubCommittees[i]);
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();

        configBuilder.set("admin_executor", address(ctx.adminExecutor));
        configBuilder.set("timelock", address(ctx.timelock));
        configBuilder.set("emergency_governance", address(ctx.emergencyGovernance));
        configBuilder.set("reseal_manager", address(ctx.resealManager));
        configBuilder.set("dual_governance", address(ctx.dualGovernance));
        configBuilder.set("escrow_master_copy", address(ctx.escrowMasterCopy));
        configBuilder.set("dual_governance_config_provider", address(ctx.dualGovernanceConfigProvider));
        configBuilder.set("tiebreaker_core_committee", address(ctx.tiebreakerCoreCommittee));
        configBuilder.set("tiebreaker_sub_committees", _getTiebreakerSubCommitteeAddresses(ctx));

        return configBuilder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("DualGovernance address", address(ctx.dualGovernance));
        console.log("EscrowMasterCopy address", address(ctx.escrowMasterCopy));
        console.log("ResealManager address", address(ctx.resealManager));
        console.log("TiebreakerCoreCommittee address", address(ctx.tiebreakerCoreCommittee));

        address[] memory tiebreakerSubCommittees = _getTiebreakerSubCommitteeAddresses(ctx);

        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            console.log("TiebreakerSubCommittee[%d] address %x", i, tiebreakerSubCommittees[i]);
        }

        console.log("AdminExecutor address", address(ctx.adminExecutor));
        console.log("EmergencyProtectedTimelock address", address(ctx.timelock));
        console.log("EmergencyGovernance address", address(ctx.emergencyGovernance));
    }

    function _getTiebreakerSubCommitteeAddresses(Context memory ctx)
        private
        pure
        returns (address[] memory tiebreakerSubCommittees)
    {
        tiebreakerSubCommittees = new address[](ctx.tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            tiebreakerSubCommittees[i] = address(ctx.tiebreakerSubCommittees[i]);
        }
    }
}

library DGSetupDeployArtifacts {
    using ConfigFileBuilder for ConfigFileBuilder.Context;
    using DGSetupDeployConfig for DGSetupDeployConfig.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;

    struct Context {
        DGSetupDeployConfig.Context deployConfig;
        DGSetupDeployedContracts.Context deployedContracts;
    }

    function create(
        DGSetupDeployConfig.Context memory deployConfig,
        DGSetupDeployedContracts.Context memory deployedContracts
    ) internal pure returns (Context memory ctx) {
        ctx.deployConfig = deployConfig;
        ctx.deployedContracts = deployedContracts;
    }

    function load(string memory deployArtifactFileName) internal view returns (Context memory ctx) {
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(deployArtifactFileName);
        ctx.deployConfig = DGSetupDeployConfig.load(deployArtifactFilePath, "deploy_config");
        ctx.deployedContracts = DGSetupDeployedContracts.load(deployArtifactFilePath, "deployed_contracts");
    }

    function validate(Context memory ctx) internal pure {
        ctx.deployConfig.validate();
    }

    function save(Context memory ctx, string memory fileName) internal {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();

        // forgefmt: disable-next-item
        configBuilder
            .set("deploy_config", ctx.deployConfig.toJSON())
            .set("deployed_contracts", ctx.deployedContracts.toJSON())
            .write(DeployFiles.resolveDeployArtifact(fileName));
    }
}

library TGSetupDeployConfig {
    struct Context {
        uint256 chainId;
        address governance;
        TimelockContractDeployConfig.Context timelock;
    }
}

library TGSetupDeployedContracts {
    struct Context {
        Executor adminExecutor;
        EmergencyProtectedTimelock timelock;
        TimelockedGovernance timelockedGovernance;
    }
}

library TimelockedGovernanceDeployConfig {
    using ConfigFileReader for ConfigFileReader.Context;

    struct Context {
        uint256 chainId;
        address governance;
        EmergencyProtectedTimelock timelock;
    }

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (Context memory ctx) {
        string memory $ = configRootKey.root();
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        ctx.governance = file.readAddress($.key("governance"));
        ctx.timelock = EmergencyProtectedTimelock(file.readAddress($.key("timelock")));
    }

    function validate(Context memory ctx) internal view {
        if (ctx.chainId != block.chainid) {
            revert InvalidChainId({actual: block.chainid, expected: ctx.chainId});
        }
        if (address(ctx.timelock) == address(0)) {
            revert InvalidParameter("timelock");
        }
        if (ctx.governance == address(0)) {
            revert InvalidParameter("governance");
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("governance", ctx.governance);
        builder.set("timelock", address(ctx.timelock));

        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("Governance address", ctx.governance);
        console.log("Timelock address", address(ctx.timelock));
    }
}

library TimelockedGovernanceDeployedContracts {
    using ConfigFileReader for ConfigFileReader.Context;

    struct Context {
        TimelockedGovernance timelockedGovernance;
    }

    function load(
        string memory deployedContractsFilePath,
        string memory prefix
    ) internal view returns (Context memory ctx) {
        string memory $ = prefix.root();
        ConfigFileReader.Context memory deployedContract = ConfigFileReader.load(deployedContractsFilePath);

        ctx.timelockedGovernance = TimelockedGovernance(deployedContract.readAddress($.key("timelocked_governance")));
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("timelocked_governance", address(ctx.timelockedGovernance));

        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("TimelockedGovernance address", address(ctx.timelockedGovernance));
    }
}

library ContractsDeployment {
    function deployTGSetup(
        address deployer,
        TGSetupDeployConfig.Context memory config
    ) internal returns (TGSetupDeployedContracts.Context memory contracts) {
        contracts.adminExecutor = deployExecutor({owner: deployer});

        contracts.timelock = deployEmergencyProtectedTimelock(
            contracts.adminExecutor,
            config.timelock.afterSubmitDelay,
            config.timelock.afterScheduleDelay,
            config.timelock.sanityCheckParams
        );

        contracts.timelockedGovernance =
            deployTimelockedGovernance({governance: config.governance, timelock: contracts.timelock});

        configureEmergencyProtectedTimelock(contracts.adminExecutor, contracts.timelock, config.timelock);
        finalizeEmergencyProtectedTimelockDeploy(
            contracts.adminExecutor, contracts.timelock, address(contracts.timelockedGovernance)
        );
    }

    function deployDGSetup(
        address deployer,
        DGSetupDeployConfig.Context memory deployConfig
    ) internal returns (DGSetupDeployedContracts.Context memory contracts) {
        contracts.adminExecutor = deployExecutor({owner: deployer});

        contracts.timelock = deployEmergencyProtectedTimelock(
            contracts.adminExecutor,
            deployConfig.timelock.afterSubmitDelay,
            deployConfig.timelock.afterScheduleDelay,
            deployConfig.timelock.sanityCheckParams
        );

        contracts.resealManager = deployResealManager(contracts.timelock);

        contracts.dualGovernanceConfigProvider =
            deployDualGovernanceConfigProvider(deployConfig.dualGovernanceConfigProvider);

        contracts.dualGovernance = deployDualGovernance(
            DualGovernance.DualGovernanceComponents({
                timelock: contracts.timelock,
                resealManager: contracts.resealManager,
                configProvider: contracts.dualGovernanceConfigProvider
            }),
            deployConfig.dualGovernance.signallingTokens,
            deployConfig.dualGovernance.sanityCheckParams
        );

        contracts.tiebreakerCoreCommittee = deployEmptyTiebreakerCoreCommittee({
            owner: deployer, // temporary set owner to deployer, to add sub committees manually
            dualGovernance: address(contracts.dualGovernance),
            executionDelay: deployConfig.tiebreaker.executionDelay
        });

        contracts.tiebreakerSubCommittees = deployTiebreakerSubCommittees(
            address(contracts.adminExecutor), contracts.tiebreakerCoreCommittee, deployConfig.tiebreaker.committees
        );

        configureTiebreakerCommittee(
            contracts.adminExecutor,
            contracts.dualGovernance,
            contracts.tiebreakerCoreCommittee,
            contracts.tiebreakerSubCommittees,
            deployConfig.tiebreaker,
            deployConfig.dualGovernance
        );

        // ---
        // Finalize Setup
        // ---

        configureDualGovernance(contracts.adminExecutor, contracts.dualGovernance, deployConfig.dualGovernance);

        contracts.emergencyGovernance =
            configureEmergencyProtectedTimelock(contracts.adminExecutor, contracts.timelock, deployConfig.timelock);

        finalizeEmergencyProtectedTimelockDeploy(
            contracts.adminExecutor, contracts.timelock, address(contracts.dualGovernance)
        );
    }

    function deployExecutor(address owner) internal returns (Executor) {
        return new Executor(owner);
    }

    function deployEmergencyProtectedTimelock(
        Executor adminExecutor,
        Duration afterSubmitDelay,
        Duration afterScheduleDelay,
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams
    ) internal returns (EmergencyProtectedTimelock) {
        return new EmergencyProtectedTimelock(
            sanityCheckParams, address(adminExecutor), afterSubmitDelay, afterScheduleDelay
        );
    }

    function deployTimelockedGovernance(
        address governance,
        ITimelock timelock
    ) internal returns (TimelockedGovernance) {
        return new TimelockedGovernance(governance, timelock);
    }

    function deployResealManager(ITimelock timelock) internal returns (ResealManager) {
        return new ResealManager(timelock);
    }

    function deployDualGovernanceConfigProvider(DualGovernanceConfig.Context memory dgConfig)
        internal
        returns (ImmutableDualGovernanceConfigProvider)
    {
        return new ImmutableDualGovernanceConfigProvider(dgConfig);
    }

    function deployDualGovernance(
        DualGovernance.DualGovernanceComponents memory components,
        DualGovernance.SignallingTokens memory signallingTokens,
        DualGovernance.SanityCheckParams memory sanityCheckParams
    ) internal returns (DualGovernance) {
        return new DualGovernance(components, signallingTokens, sanityCheckParams);
    }

    function deployEmptyTiebreakerCoreCommittee(
        address owner,
        address dualGovernance,
        Duration executionDelay
    ) internal returns (TiebreakerCoreCommittee) {
        return new TiebreakerCoreCommittee({owner: owner, dualGovernance: dualGovernance, timelock: executionDelay});
    }

    function deployTiebreakerSubCommittees(
        address owner,
        TiebreakerCoreCommittee tiebreakerCoreCommittee,
        TiebreakerCommitteeDeployConfig[] memory tiebreakerSubCommittees
    ) internal returns (TiebreakerSubCommittee[] memory coreCommitteeMembers) {
        coreCommitteeMembers = new TiebreakerSubCommittee[](tiebreakerSubCommittees.length);

        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            coreCommitteeMembers[i] = deployTiebreakerSubCommittee({
                owner: owner,
                quorum: tiebreakerSubCommittees[i].quorum,
                members: tiebreakerSubCommittees[i].members,
                tiebreakerCoreCommittee: address(tiebreakerCoreCommittee)
            });
        }
    }

    function deployTiebreakerSubCommittee(
        address owner,
        uint256 quorum,
        address[] memory members,
        address tiebreakerCoreCommittee
    ) internal returns (TiebreakerSubCommittee) {
        return new TiebreakerSubCommittee({
            owner: owner,
            executionQuorum: quorum,
            committeeMembers: members,
            tiebreakerCoreCommittee: tiebreakerCoreCommittee
        });
    }

    function configureTiebreakerCommittee(
        Executor adminExecutor,
        DualGovernance dualGovernance,
        TiebreakerCoreCommittee tiebreakerCoreCommittee,
        TiebreakerSubCommittee[] memory tiebreakerSubCommittees,
        TiebreakerContractDeployConfig.Context memory tiebreakerConfig,
        DualGovernanceContractDeployConfig.Context memory dgDeployConfig
    ) internal {
        address[] memory coreCommitteeMemberAddresses = new address[](tiebreakerSubCommittees.length);

        for (uint256 i = 0; i < coreCommitteeMemberAddresses.length; ++i) {
            coreCommitteeMemberAddresses[i] = address(tiebreakerSubCommittees[i]);
        }

        tiebreakerCoreCommittee.addMembers(coreCommitteeMemberAddresses, tiebreakerConfig.quorum);
        tiebreakerCoreCommittee.transferOwnership(address(adminExecutor));

        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerActivationTimeout, dgDeployConfig.tiebreakerActivationTimeout)
        );
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerCommittee, address(tiebreakerCoreCommittee))
        );

        for (uint256 i = 0; i < dgDeployConfig.sealableWithdrawalBlockers.length; ++i) {
            adminExecutor.execute(
                address(dualGovernance),
                0,
                abi.encodeCall(
                    dualGovernance.addTiebreakerSealableWithdrawalBlocker, dgDeployConfig.sealableWithdrawalBlockers[i]
                )
            );
        }
    }

    function configureDualGovernance(
        Executor adminExecutor,
        DualGovernance dualGovernance,
        DualGovernanceContractDeployConfig.Context memory dgDeployConfig
    ) internal {
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.registerProposer, (dgDeployConfig.adminProposer, address(adminExecutor)))
        );
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setProposalsCanceller, dgDeployConfig.proposalsCanceller)
        );
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setResealCommittee, dgDeployConfig.resealCommittee)
        );
    }

    function configureEmergencyProtectedTimelock(
        Executor adminExecutor,
        EmergencyProtectedTimelock timelock,
        TimelockContractDeployConfig.Context memory timelockConfig
    ) internal returns (TimelockedGovernance emergencyGovernance) {
        if (timelockConfig.emergencyGovernanceProposer != address(0)) {
            emergencyGovernance =
                deployTimelockedGovernance({governance: timelockConfig.emergencyGovernanceProposer, timelock: timelock});
            adminExecutor.execute(
                address(timelock), 0, abi.encodeCall(timelock.setEmergencyGovernance, (address(emergencyGovernance)))
            );
        }

        if (timelockConfig.emergencyActivationCommittee != address(0)) {
            console.log(
                "Setting the emergency activation committee to %x...", timelockConfig.emergencyActivationCommittee
            );
            adminExecutor.execute(
                address(timelock),
                0,
                abi.encodeCall(
                    timelock.setEmergencyProtectionActivationCommittee, (timelockConfig.emergencyActivationCommittee)
                )
            );
            console.log("Emergency activation committee set successfully.");
        }

        if (timelockConfig.emergencyExecutionCommittee != address(0)) {
            console.log(
                "Setting the emergency execution committee to %x...", timelockConfig.emergencyExecutionCommittee
            );
            adminExecutor.execute(
                address(timelock),
                0,
                abi.encodeCall(
                    timelock.setEmergencyProtectionExecutionCommittee, (timelockConfig.emergencyExecutionCommittee)
                )
            );
            console.log("Emergency execution committee set successfully.");
        }

        if (timelockConfig.emergencyProtectionEndDate != Timestamps.ZERO) {
            adminExecutor.execute(
                address(timelock),
                0,
                abi.encodeCall(timelock.setEmergencyProtectionEndDate, (timelockConfig.emergencyProtectionEndDate))
            );
        }

        if (timelockConfig.emergencyModeDuration != Durations.ZERO) {
            adminExecutor.execute(
                address(timelock),
                0,
                abi.encodeCall(timelock.setEmergencyModeDuration, (timelockConfig.emergencyModeDuration))
            );
        }
    }

    function finalizeEmergencyProtectedTimelockDeploy(
        Executor adminExecutor,
        EmergencyProtectedTimelock timelock,
        address governance
    ) internal {
        adminExecutor.execute(address(timelock), 0, abi.encodeCall(timelock.setGovernance, (governance)));
        adminExecutor.transferOwnership(address(timelock));
    }
}
