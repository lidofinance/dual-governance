// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";

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

import {ImmutableDualGovernanceConfigProviderDeployConfig} from "./deployment/ImmutableDualGovernanceConfigProvider.sol";
import {
    TiebreakerDeployConfig,
    TiebreakerSubCommitteeDeployConfig,
    TiebreakerDeployedContracts
} from "./deployment/Tiebreaker.sol";

import {DeployFiles} from "./DeployFiles.sol";
import {ConfigFileReader, ConfigFileBuilder, JsonKeys} from "./ConfigFiles.sol";

import {IVotingProvider} from "./interfaces/IVotingProvider.sol";

// solhint-disable-next-line const-name-snakecase
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

error InvalidParameter(string parameter);
error InvalidChainId(uint256 actual, uint256 expected);

using JsonKeys for string;
using ConfigFileBuilder for ConfigFileBuilder.Context;
using ConfigFileReader for ConfigFileReader.Context;

library TimelockContractDeployConfig {
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
            revert InvalidParameter("timelock.after_submit_delay");
        }

        if (ctx.afterScheduleDelay > ctx.sanityCheckParams.maxAfterScheduleDelay) {
            revert InvalidParameter("timelock.after_schedule_delay");
        }

        if (ctx.emergencyModeDuration > ctx.sanityCheckParams.maxEmergencyModeDuration) {
            revert InvalidParameter("timelock.emergency_mode_duration");
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

    function print(Context memory ctx) internal pure {
        console.log("===== Timelock");
        console.log("After submit delay", ctx.afterSubmitDelay.toSeconds());
        console.log("After schedule delay", ctx.afterScheduleDelay.toSeconds());
        console.log("\n");
        console.log("===== Timelock. Sanity check params");
        console.log("Min execution delay", ctx.sanityCheckParams.minExecutionDelay.toSeconds());
        console.log("Max after submit delay", ctx.sanityCheckParams.maxAfterSubmitDelay.toSeconds());
        console.log("Max after schedule delay", ctx.sanityCheckParams.maxAfterScheduleDelay.toSeconds());
        console.log("Max emergency mode duration", ctx.sanityCheckParams.maxEmergencyModeDuration.toSeconds());
        console.log(
            "Max emergency protection duration", ctx.sanityCheckParams.maxEmergencyProtectionDuration.toSeconds()
        );
        console.log("\n");
        console.log("===== Timelock. Emergency protection");
        console.log("Emergency activation committee", ctx.emergencyActivationCommittee);
        console.log("Emergency execution committee", ctx.emergencyExecutionCommittee);
        console.log("Emergency governance proposer", ctx.emergencyGovernanceProposer);
        console.log("Emergency mode duration", ctx.emergencyModeDuration.toSeconds());
        console.log("Emergency protection end date", ctx.emergencyProtectionEndDate.toSeconds());
        console.log("\n");
    }
}

library DualGovernanceContractDeployConfig {
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
        string memory $sanityCheck = $.key("sanity_check_params");
        string memory $signallingTokens = $.key("signalling_tokens");

        return Context({
            adminProposer: file.readAddress($.key("admin_proposer")),
            resealCommittee: file.readAddress($.key("reseal_committee")),
            proposalsCanceller: file.readAddress($.key("proposals_canceller")),
            tiebreakerActivationTimeout: file.readDuration($.key("tiebreaker_activation_timeout")),
            sealableWithdrawalBlockers: file.readAddressArray($.key("sealable_withdrawal_blockers")),
            sanityCheckParams: DualGovernance.SanityCheckParams({
                minWithdrawalsBatchSize: file.readUint($sanityCheck.key("min_withdrawals_batch_size")),
                minTiebreakerActivationTimeout: file.readDuration($sanityCheck.key("min_tiebreaker_activation_timeout")),
                maxTiebreakerActivationTimeout: file.readDuration($sanityCheck.key("max_tiebreaker_activation_timeout")),
                maxSealableWithdrawalBlockersCount: file.readUint($sanityCheck.key("max_sealable_withdrawal_blockers_count")),
                maxMinAssetsLockDuration: file.readDuration($sanityCheck.key("max_min_assets_lock_duration"))
            }),
            signallingTokens: DualGovernance.SignallingTokens({
                stETH: IStETH(file.readAddress($signallingTokens.key("st_eth"))),
                wstETH: IWstETH(file.readAddress($signallingTokens.key("wst_eth"))),
                withdrawalQueue: IWithdrawalQueue(file.readAddress($signallingTokens.key("withdrawal_queue")))
            })
        });
    }

    function validate(Context memory ctx) internal pure {
        if (ctx.sanityCheckParams.minTiebreakerActivationTimeout > ctx.sanityCheckParams.maxTiebreakerActivationTimeout)
        {
            revert InvalidParameter("dual_governance.sanity_check_params.min_tiebreaker_activation_timeout");
        }

        if (
            ctx.tiebreakerActivationTimeout > ctx.sanityCheckParams.maxTiebreakerActivationTimeout
                || ctx.tiebreakerActivationTimeout < ctx.sanityCheckParams.minTiebreakerActivationTimeout
        ) {
            revert InvalidParameter("dual_governance.tiebreaker_activation_timeout");
        }

        if (ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount == 0) {
            revert InvalidParameter("dual_governance.sanity_check_params.max_sealable_withdrawal_blockers_count");
        }

        if (ctx.sealableWithdrawalBlockers.length > ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount) {
            revert InvalidParameter("dual_governance.sealable_withdrawal_blockers");
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

    function print(Context memory ctx) internal pure {
        console.log("===== DualGovernance");
        console.log("Admin proposer", ctx.adminProposer);
        console.log("Reseal committee", ctx.resealCommittee);
        console.log("Proposals canceller", ctx.proposalsCanceller);
        console.log("Tiebreaker activation timeout", ctx.tiebreakerActivationTimeout.toSeconds());
        for (uint256 i = 0; i < ctx.sealableWithdrawalBlockers.length; ++i) {
            console.log("Sealable withdrawal blocker [%d] %s", i, ctx.sealableWithdrawalBlockers[i]);
        }
        console.log("\n");
        console.log("===== DualGovernance. Signalling tokens");
        console.log("stETH address", address(ctx.signallingTokens.stETH));
        console.log("wstETH address", address(ctx.signallingTokens.wstETH));
        console.log("Withdrawal queue address", address(ctx.signallingTokens.withdrawalQueue));
        console.log("\n");
        console.log("===== DualGovernance. Sanity check params");
        console.log("Max min assets lock duration", ctx.sanityCheckParams.maxMinAssetsLockDuration.toSeconds());
        console.log("Max sealable withdrawal blockers count", ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount);
        console.log(
            "Min tiebreaker activation timeout", ctx.sanityCheckParams.minTiebreakerActivationTimeout.toSeconds()
        );
        console.log(
            "Max tiebreaker activation timeout", ctx.sanityCheckParams.maxTiebreakerActivationTimeout.toSeconds()
        );
        console.log("Min withdrawals batch size", ctx.sanityCheckParams.minWithdrawalsBatchSize);
        console.log("\n");
    }
}

library DGLaunchConfig {
    struct Context {
        uint256 chainId;
        TimelockedGovernance daoEmergencyGovernance;
        address dgLaunchVerifier;
        address rolesValidator;
        address timeConstraints;
        IVotingProvider omnibusContract;
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

        string memory $daoVoting = $.key("dg_launch");

        ctx.daoEmergencyGovernance = TimelockedGovernance(file.readAddress($daoVoting.key("dao_emergency_governance")));
        ctx.dgLaunchVerifier = file.readAddress($daoVoting.key("dg_launch_verifier"));
        ctx.rolesValidator = file.readAddress($daoVoting.key("roles_validator"));
        ctx.timeConstraints = file.readAddress($daoVoting.key("time_constraints"));
        ctx.omnibusContract = IVotingProvider(file.readAddress($daoVoting.key("omnibus_contract")));
    }
}

library DGSetupDeployConfig {
    using TimelockContractDeployConfig for TimelockContractDeployConfig.Context;
    using TiebreakerDeployConfig for TiebreakerDeployConfig.Context;
    using DualGovernanceContractDeployConfig for DualGovernanceContractDeployConfig.Context;
    using ImmutableDualGovernanceConfigProviderDeployConfig for DualGovernanceConfig.Context;

    struct Context {
        uint256 chainId;
        TimelockContractDeployConfig.Context timelock;
        TiebreakerDeployConfig.Context tiebreaker;
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
        ctx.tiebreaker = TiebreakerDeployConfig.load(configFilePath, $.key("tiebreaker"));
        ctx.tiebreaker.chainId = ctx.chainId;
        ctx.dualGovernance = DualGovernanceContractDeployConfig.load(configFilePath, $.key("dual_governance"));
        ctx.dualGovernanceConfigProvider = ImmutableDualGovernanceConfigProviderDeployConfig.load(
            configFilePath, $.key("dual_governance_config_provider")
        );
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

    function print(Context memory ctx) internal pure {
        console.log("Chain ID", ctx.chainId);

        ctx.timelock.print();
        ctx.dualGovernanceConfigProvider.print();
        ctx.dualGovernance.print();
        ctx.tiebreaker.print();
    }
}

library DGSetupDeployedContracts {
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
        console.log("DualGovernanceConfigProvider address", address(ctx.dualGovernanceConfigProvider));
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

        console.log("\n");
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
    using DGSetupDeployConfig for DGSetupDeployConfig.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;
    using DGLaunchConfig for DGLaunchConfig.Context;

    struct Context {
        DGSetupDeployConfig.Context deployConfig;
        DGSetupDeployedContracts.Context deployedContracts;
    }

    function load(string memory deployArtifactFileName) internal view returns (Context memory ctx) {
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(deployArtifactFileName);
        ctx.deployConfig = DGSetupDeployConfig.load(deployArtifactFilePath, "deploy_config");
        ctx.deployedContracts = DGSetupDeployedContracts.load(deployArtifactFilePath, "deployed_contracts");
    }

    function loadDGLaunchConfig(string memory deployArtifactFileName)
        internal
        view
        returns (DGLaunchConfig.Context memory)
    {
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(deployArtifactFileName);
        return DGLaunchConfig.load(deployArtifactFilePath);
    }

    function save(Context memory ctx, string memory fileName) internal {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(fileName);

        // forgefmt: disable-next-item
        configBuilder
            .set("deploy_config", ctx.deployConfig.toJSON())
            .set("deployed_contracts", ctx.deployedContracts.toJSON())
            .write(deployArtifactFilePath);

        console.log("\n");
        console.log("Deploy artifact saved to: %s", deployArtifactFilePath);
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

        ctx.chainId = file.readUint($.key("chain_id"));
        ctx.governance = file.readAddress($.key("timelocked_governance.governance"));
        ctx.timelock = EmergencyProtectedTimelock(file.readAddress($.key("timelocked_governance.timelock")));
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

        contracts.timelock = deployEmergencyProtectedTimelock(contracts.adminExecutor, config.timelock);

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

        contracts.timelock = deployEmergencyProtectedTimelock(contracts.adminExecutor, deployConfig.timelock);

        contracts.resealManager = deployResealManager(contracts.timelock);

        contracts.dualGovernanceConfigProvider =
            deployDualGovernanceConfigProvider(deployConfig.dualGovernanceConfigProvider);

        contracts.dualGovernance = deployDualGovernance(
            DualGovernance.DualGovernanceComponents({
                timelock: contracts.timelock,
                resealManager: contracts.resealManager,
                configProvider: contracts.dualGovernanceConfigProvider
            }),
            deployConfig.dualGovernance
        );

        deployConfig.tiebreaker.owner = address(contracts.adminExecutor);
        deployConfig.tiebreaker.dualGovernance = address(contracts.dualGovernance);

        contracts.escrowMasterCopy = Escrow(
            payable(address(ISignallingEscrow(contracts.dualGovernance.getVetoSignallingEscrow()).ESCROW_MASTER_COPY()))
        );

        TiebreakerDeployedContracts.Context memory tiebreakerDeployedContracts =
            deployTiebreaker(deployConfig.tiebreaker, deployer);

        contracts.tiebreakerCoreCommittee = tiebreakerDeployedContracts.tiebreakerCoreCommittee;
        contracts.tiebreakerSubCommittees = tiebreakerDeployedContracts.tiebreakerSubCommittees;

        configureTiebreakerCommittee(
            contracts.adminExecutor,
            contracts.dualGovernance,
            contracts.tiebreakerCoreCommittee,
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
        TimelockContractDeployConfig.Context memory config
    ) internal returns (EmergencyProtectedTimelock) {
        TimelockContractDeployConfig.validate(config);
        return new EmergencyProtectedTimelock(
            config.sanityCheckParams, address(adminExecutor), config.afterSubmitDelay, config.afterScheduleDelay
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
        DualGovernanceConfig.validate(dgConfig);
        return new ImmutableDualGovernanceConfigProvider(dgConfig);
    }

    function deployDualGovernance(
        DualGovernance.DualGovernanceComponents memory components,
        DualGovernanceContractDeployConfig.Context memory dgDeployConfig
    ) internal returns (DualGovernance) {
        DualGovernanceContractDeployConfig.validate(dgDeployConfig);

        return new DualGovernance(components, dgDeployConfig.signallingTokens, dgDeployConfig.sanityCheckParams);
    }

    function deployTiebreaker(
        TiebreakerDeployConfig.Context memory tiebreakerConfig,
        address deployer
    ) internal returns (TiebreakerDeployedContracts.Context memory deployedContracts) {
        TiebreakerDeployConfig.validate(tiebreakerConfig);

        deployedContracts.tiebreakerCoreCommittee = new TiebreakerCoreCommittee({
            owner: deployer,
            dualGovernance: tiebreakerConfig.dualGovernance,
            timelock: tiebreakerConfig.executionDelay
        });

        deployedContracts.tiebreakerSubCommittees = new TiebreakerSubCommittee[](tiebreakerConfig.committees.length);

        for (uint256 i = 0; i < tiebreakerConfig.committees.length; ++i) {
            deployedContracts.tiebreakerSubCommittees[i] = new TiebreakerSubCommittee({
                owner: tiebreakerConfig.owner,
                executionQuorum: tiebreakerConfig.committees[i].quorum,
                committeeMembers: tiebreakerConfig.committees[i].members,
                tiebreakerCoreCommittee: address(deployedContracts.tiebreakerCoreCommittee)
            });
        }

        address[] memory coreCommitteeMemberAddresses = new address[](deployedContracts.tiebreakerSubCommittees.length);

        for (uint256 i = 0; i < coreCommitteeMemberAddresses.length; ++i) {
            coreCommitteeMemberAddresses[i] = address(deployedContracts.tiebreakerSubCommittees[i]);
        }

        deployedContracts.tiebreakerCoreCommittee.addMembers(coreCommitteeMemberAddresses, tiebreakerConfig.quorum);

        deployedContracts.tiebreakerCoreCommittee.transferOwnership(tiebreakerConfig.owner);
    }

    function configureTiebreakerCommittee(
        Executor adminExecutor,
        DualGovernance dualGovernance,
        TiebreakerCoreCommittee tiebreakerCoreCommittee,
        DualGovernanceContractDeployConfig.Context memory dgDeployConfig
    ) internal {
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
