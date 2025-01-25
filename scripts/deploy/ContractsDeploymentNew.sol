// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/stdJson.sol";
import {stdToml} from "forge-std/StdToml.sol";
import {console} from "forge-std/console.sol";

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

// ---
// Contracts
// ---

import {PercentD16} from "contracts/types/PercentD16.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";

import {ResealManager} from "contracts/ResealManager.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {
    DualGovernanceConfig,
    IDualGovernanceConfigProvider,
    ImmutableDualGovernanceConfigProvider
} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IResealManager} from "contracts/interfaces/IResealManager.sol";

import {ConfigFileReader} from "./config/ConfigFileReader.sol";

Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

library Path {
    string constant DEPLOY_CONFIGS_DIR = "deploy-configs";
    string constant DEPLOY_ARTIFACTS_DIR = "deploy-artifacts";

    function resolveDeployConfig(string memory fileName) internal returns (string memory) {
        return string.concat(vm.projectRoot(), "/", DEPLOY_CONFIGS_DIR, "/", fileName);
    }

    function resolveDeployArtifact(string memory fileName) internal returns (string memory) {
        return string.concat(vm.projectRoot(), "/", DEPLOY_ARTIFACTS_DIR, "/", fileName);
    }
}

// solhint-disable-next-line const-name-snakecase
string constant DEPLOY_ARTIFACTS_DIR = "deploy-artifacts";

struct TiebreakerCommitteeDeployConfig {
    uint256 quorum;
    address[] members;
}

struct TiebreakerDeployConfig {
    uint256 quorum;
    uint256 committeesCount;
    Duration executionDelay;
    Duration activationTimeout;
    TiebreakerCommitteeDeployConfig[] committees;
}

struct DualGovernanceDeployConfig {
    address adminProposer;
    address resealCommittee;
    address proposalsCanceller;
    address[] sealableWithdrawalBlockers;
    DualGovernance.SignallingTokens signallingTokens;
    DualGovernance.SanityCheckParams sanityCheckParams;
    DualGovernanceConfig.Context dualGovernanceConfig;
}

struct TimelockDeployConfig {
    Duration afterSubmitDelay;
    Duration afterScheduleDelay;
    EmergencyProtectedTimelock.SanityCheckParams sanityCheckParams;
    Duration emergencyModeDuration;
    Timestamp emergencyProtectionEndDate;
    address emergencyGovernanceProposer;
    address emergencyActivationCommittee;
    address emergencyExecutionCommittee;
}

library TGDeployedContracts {
    struct Context {
        Executor adminExecutor;
        EmergencyProtectedTimelock timelock;
        TimelockedGovernance timelockedGovernance;
    }
}

library TGDeployConfig {
    struct Context {
        uint256 chainId;
        address governance;
        TimelockDeployConfig timelock;
    }
}

library DGDeployedContracts {
    using JsonKeys for string;
    using ConfigFileReader for ConfigFileReader.Context;
    using ConfigFileBuilder for ConfigFileBuilder.Context;

    struct Context {
        Executor adminExecutor;
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
    ) internal returns (Context memory ctx) {
        string memory $ = prefix.root();
        ConfigFileReader.Context memory deployedContract = ConfigFileReader.load(deployedContractsFilePath);

        ctx.adminExecutor = Executor(payable(deployedContract.readAddress($.key("admin_executor"))));
        ctx.timelock = EmergencyProtectedTimelock(deployedContract.readAddress($.key("timelock")));
        ctx.emergencyGovernance = TimelockedGovernance(deployedContract.readAddress($.key("emergency_governance")));
        ctx.resealManager = ResealManager(deployedContract.readAddress($.key("reseal_manager")));
        ctx.dualGovernance = DualGovernance(deployedContract.readAddress($.key("dual_governance")));
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
        configBuilder.set("dual_governance_config_provider", address(ctx.dualGovernanceConfigProvider));
        configBuilder.set("tiebreaker_core_committee", address(ctx.tiebreakerCoreCommittee));
        configBuilder.set("tiebreaker_sub_committees", _getTiebreakerSubCommitteeAddresses(ctx));

        return configBuilder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("DualGovernance address", address(ctx.dualGovernance));
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

library DGDeployArtifacts {
    using DGDeployConfig for DGDeployConfig.Context;
    using ConfigFileBuilder for ConfigFileBuilder.Context;
    using DGDeployedContracts for DGDeployedContracts.Context;

    struct Context {
        DGDeployConfig.Context deployConfig;
        DGDeployedContracts.Context deployedContracts;
    }

    function load(string memory deployArtifactFilePath) internal returns (Context memory ctx) {
        ctx.deployConfig = DGDeployConfig.load(deployArtifactFilePath, "deploy_config");
        ctx.deployedContracts = DGDeployedContracts.load(deployArtifactFilePath, "deployed_contracts");
    }

    function save(Context memory ctx, string memory deployArtifactsFilePath) internal {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();

        configBuilder.set("deploy_config", ctx.deployConfig.toJSON()).set(
            "deployed_contracts", ctx.deployedContracts.toJSON()
        ).write(deployArtifactsFilePath);
    }

    function create(
        DGDeployConfig.Context memory deployConfig,
        DGDeployedContracts.Context memory deployedContracts
    ) internal returns (Context memory ctx) {
        ctx.deployConfig = deployConfig;
        ctx.deployedContracts = deployedContracts;
    }
}

library JsonKeys {
    function root(string memory prefix) internal pure returns (string memory) {
        if (bytes(prefix).length == 0) {
            return "$";
        }
        if (bytes(prefix)[0] == bytes1("$") || bytes(prefix)[0] == bytes1(".")) {
            return prefix;
        }
        return string.concat("$", ".", prefix);
    }

    function key(string memory prefix, string memory key) internal pure returns (string memory) {
        return string.concat(prefix, ".", key);
    }

    function index(string memory prefix, string memory key, uint256 index) internal pure returns (string memory) {
        return string.concat(prefix, ".", key, "[", vm.toString(index), "]");
    }
}

library DGDeployConfig {
    using JsonKeys for string;
    using ConfigFileBuilder for ConfigFileBuilder.Context;
    using ConfigFileReader for ConfigFileReader.Context;

    struct Context {
        uint256 chainId;
        TiebreakerDeployConfig tiebreaker;
        DualGovernanceDeployConfig dualGovernance;
        TimelockDeployConfig timelock;
    }

    function load(string memory configFilePath) internal returns (Context memory ctx) {
        return load(configFilePath, "");
    }

    function load(string memory configFilePath, string memory prefix) internal returns (Context memory ctx) {
        string memory $ = prefix.root();
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        ctx.chainId = file.readUint($.key("chain_id"));
        ctx.timelock = _readTimelockDeployConfig(file, $.key("timelock"));
        ctx.tiebreaker = _readTiebreakerDeployConfig(file, $.key("tiebreaker"));
        ctx.dualGovernance = _readDualGovernanceDeployConfig(file, $.key("dual_governance"));
    }

    function _readTimelockDeployConfig(
        ConfigFileReader.Context memory file,
        string memory prefix
    ) internal returns (TimelockDeployConfig memory) {
        string memory $ = prefix.root();
        string memory $sanityCheckParams = $.key("sanity_check_params");
        string memory $emergencyProtection = $.key("emergency_protection");

        return TimelockDeployConfig({
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

    function _readDualGovernanceDeployConfig(
        ConfigFileReader.Context memory file,
        string memory prefix
    ) internal returns (DualGovernanceDeployConfig memory) {
        string memory $ = prefix.root();
        string memory $config = $.key("config");
        string memory $signalling_tokens = $.key("signalling_tokens");
        string memory $sanity_check = $.key("sanity_check_params");

        return DualGovernanceDeployConfig({
            adminProposer: file.readAddress($.key("admin_proposer")),
            resealCommittee: file.readAddress($.key("reseal_committee")),
            proposalsCanceller: file.readAddress($.key("proposals_canceller")),
            sealableWithdrawalBlockers: file.readAddressArray($.key("sealable_withdrawal_blockers")),
            //
            dualGovernanceConfig: DualGovernanceConfig.Context({
                firstSealRageQuitSupport: file.readPercentD16BP($config.key("first_seal_rage_quit_support")),
                secondSealRageQuitSupport: file.readPercentD16BP($config.key("second_seal_rage_quit_support")),
                //
                minAssetsLockDuration: file.readDuration($config.key("min_assets_lock_duration")),
                //
                vetoSignallingMinDuration: file.readDuration($config.key("veto_signalling_min_duration")),
                vetoSignallingMaxDuration: file.readDuration($config.key("veto_signalling_max_duration")),
                vetoSignallingMinActiveDuration: file.readDuration($config.key("veto_signalling_min_active_duration")),
                vetoSignallingDeactivationMaxDuration: file.readDuration($config.key("veto_signalling_max_duration")),
                vetoCooldownDuration: file.readDuration($config.key("veto_cooldown_duration")),
                //
                rageQuitExtensionPeriodDuration: file.readDuration($config.key("rage_quit_extension_period_duration")),
                rageQuitEthWithdrawalsMinDelay: file.readDuration($config.key("rage_quit_eth_withdrawals_min_delay")),
                rageQuitEthWithdrawalsMaxDelay: file.readDuration($config.key("rage_quit_eth_withdrawals_max_delay")),
                rageQuitEthWithdrawalsDelayGrowth: file.readDuration($config.key("rage_quit_eth_withdrawals_delay_growth"))
            }),
            signallingTokens: DualGovernance.SignallingTokens({
                stETH: IStETH(file.readAddress($signalling_tokens.key("st_eth"))),
                wstETH: IWstETH(file.readAddress($signalling_tokens.key("wst_eth"))),
                withdrawalQueue: IWithdrawalQueue(file.readAddress($signalling_tokens.key("withdrawal_queue")))
            }),
            sanityCheckParams: DualGovernance.SanityCheckParams({
                minWithdrawalsBatchSize: file.readUint($sanity_check.key("min_withdrawals_batch_size")),
                minTiebreakerActivationTimeout: file.readDuration($sanity_check.key("min_tiebreaker_activation_timeout")),
                maxTiebreakerActivationTimeout: file.readDuration($sanity_check.key("max_tiebreaker_activation_timeout")),
                maxSealableWithdrawalBlockersCount: file.readUint($sanity_check.key("max_sealable_withdrawal_blockers_count")),
                maxMinAssetsLockDuration: file.readDuration($sanity_check.key("max_min_assets_lock_duration"))
            })
        });
    }

    function _readTiebreakerDeployConfig(
        ConfigFileReader.Context memory file,
        string memory prefix
    ) internal returns (TiebreakerDeployConfig memory) {
        string memory $ = JsonKeys.root(prefix);

        uint256 tiebreakerCommitteesCount = file.readUint($.key("committees_count"));

        TiebreakerCommitteeDeployConfig[] memory tiebreakerCommitteeConfigs =
            new TiebreakerCommitteeDeployConfig[](tiebreakerCommitteesCount);

        for (uint256 i = 0; i < tiebreakerCommitteeConfigs.length; ++i) {
            string memory $committees = $.index("committees", i);
            tiebreakerCommitteeConfigs[i].quorum = file.readUint($committees.key("quorum"));
            tiebreakerCommitteeConfigs[i].members = file.readAddressArray($committees.key("members"));
        }

        return TiebreakerDeployConfig({
            quorum: file.readUint($.key("quorum")),
            committeesCount: tiebreakerCommitteesCount,
            executionDelay: file.readDuration($.key("execution_delay")),
            activationTimeout: file.readDuration($.key("activation_timeout")),
            committees: tiebreakerCommitteeConfigs
        });
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory timelockConfigBuilder = ConfigFileBuilder.create();
        // forgefmt: disable-next-item
        {
            ConfigFileBuilder.Context memory sanityCheckParamsBuilder = ConfigFileBuilder.create();

            sanityCheckParamsBuilder.set("min_execution_delay", ctx.timelock.sanityCheckParams.minExecutionDelay);
            sanityCheckParamsBuilder.set("max_after_submit_delay", ctx.timelock.sanityCheckParams.maxAfterSubmitDelay);
            sanityCheckParamsBuilder.set("max_after_schedule_delay", ctx.timelock.sanityCheckParams.maxAfterScheduleDelay);
            sanityCheckParamsBuilder.set("max_emergency_mode_duration", ctx.timelock.sanityCheckParams.maxEmergencyModeDuration);
            sanityCheckParamsBuilder.set("max_emergency_protection_duration", ctx.timelock.sanityCheckParams.maxEmergencyProtectionDuration);

            ConfigFileBuilder.Context memory emergencyProtectionBuilder = ConfigFileBuilder.create();

            emergencyProtectionBuilder.set("emergency_mode_duration", ctx.timelock.emergencyModeDuration);
            emergencyProtectionBuilder.set("emergency_protection_end_date", ctx.timelock.emergencyProtectionEndDate);
            emergencyProtectionBuilder.set("emergency_governance_proposer", ctx.timelock.emergencyGovernanceProposer);
            emergencyProtectionBuilder.set("emergency_activation_committee", ctx.timelock.emergencyActivationCommittee);
            emergencyProtectionBuilder.set("emergency_execution_committee", ctx.timelock.emergencyExecutionCommittee);

            timelockConfigBuilder.set("after_schedule_delay", ctx.timelock.afterScheduleDelay);
            timelockConfigBuilder.set("after_submit_delay", ctx.timelock.afterSubmitDelay);
            timelockConfigBuilder.set("sanity_check_params", sanityCheckParamsBuilder.content);
            timelockConfigBuilder.set("emergency_protection", emergencyProtectionBuilder.content);
        }

        string[] memory tiebreakerCommitteesContent = new string[](ctx.tiebreaker.committees.length);

        for (uint256 i = 0; i < tiebreakerCommitteesContent.length; ++i) {
            // forgefmt: disable-next-item
            tiebreakerCommitteesContent[i] = ConfigFileBuilder.create()
                .set("quorum", ctx.tiebreaker.committees[i].quorum)
                .set("members", ctx.tiebreaker.committees[i].members)
                .content;
        }

        ConfigFileBuilder.Context memory tiebreakerConfigBuilder = ConfigFileBuilder.create();
        // forgefmt: disable-next-item
        {
            tiebreakerConfigBuilder.set("quorum", ctx.tiebreaker.quorum);
            tiebreakerConfigBuilder.set("committees_count", ctx.tiebreaker.committeesCount);
            tiebreakerConfigBuilder.set("execution_delay", ctx.tiebreaker.executionDelay);
            tiebreakerConfigBuilder.set("activation_timeout", ctx.tiebreaker.activationTimeout);
            tiebreakerConfigBuilder.set("committees", tiebreakerCommitteesContent);
        }

        ConfigFileBuilder.Context memory dgConfigBuilder = ConfigFileBuilder.create();
        // forgefmt: disable-next-item
        {
             ConfigFileBuilder.Context memory sanityCheckParamsBuilder = ConfigFileBuilder.create();

            sanityCheckParamsBuilder.set("min_withdrawals_batch_size", ctx.dualGovernance.sanityCheckParams.minWithdrawalsBatchSize);
            sanityCheckParamsBuilder.set("min_tiebreaker_activation_timeout", ctx.dualGovernance.sanityCheckParams.minTiebreakerActivationTimeout);
            sanityCheckParamsBuilder.set("max_tiebreaker_activation_timeout", ctx.dualGovernance.sanityCheckParams.maxTiebreakerActivationTimeout);
            sanityCheckParamsBuilder.set("max_sealable_withdrawal_blockers_count", ctx.dualGovernance.sanityCheckParams.maxSealableWithdrawalBlockersCount);
            sanityCheckParamsBuilder.set("max_min_assets_lock_duration", ctx.dualGovernance.sanityCheckParams.maxMinAssetsLockDuration);

            ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();

            configBuilder.set("first_seal_rage_quit_support", ctx.dualGovernance.dualGovernanceConfig.firstSealRageQuitSupport);
            configBuilder.set("second_seal_rage_quit_support", ctx.dualGovernance.dualGovernanceConfig.secondSealRageQuitSupport);
            configBuilder.set("min_assets_lock_duration", ctx.dualGovernance.dualGovernanceConfig.minAssetsLockDuration);
            configBuilder.set("veto_signalling_min_duration", ctx.dualGovernance.dualGovernanceConfig.vetoSignallingMinDuration);
            configBuilder.set("veto_signalling_min_active_duration", ctx.dualGovernance.dualGovernanceConfig.vetoSignallingMinActiveDuration);
            configBuilder.set("veto_signalling_max_duration", ctx.dualGovernance.dualGovernanceConfig.vetoSignallingMaxDuration);
            configBuilder.set("veto_signalling_deactivation_max_duration", ctx.dualGovernance.dualGovernanceConfig.vetoSignallingDeactivationMaxDuration);
            configBuilder.set("veto_cooldown_duration", ctx.dualGovernance.dualGovernanceConfig.vetoCooldownDuration);
            configBuilder.set("rage_quit_eth_withdrawals_delay_growth", ctx.dualGovernance.dualGovernanceConfig.rageQuitEthWithdrawalsDelayGrowth);
            configBuilder.set("rage_quit_eth_withdrawals_max_delay", ctx.dualGovernance.dualGovernanceConfig.rageQuitEthWithdrawalsMaxDelay);
            configBuilder.set("rage_quit_eth_withdrawals_min_delay",ctx.dualGovernance.dualGovernanceConfig.rageQuitEthWithdrawalsMinDelay);
            configBuilder.set("rage_quit_extension_period_duration", ctx.dualGovernance.dualGovernanceConfig.rageQuitExtensionPeriodDuration);

            ConfigFileBuilder.Context memory signallingTokensBuilder = ConfigFileBuilder.create();

            signallingTokensBuilder.set("st_eth", address(ctx.dualGovernance.signallingTokens.stETH));
            signallingTokensBuilder.set("wst_eth", address(ctx.dualGovernance.signallingTokens.wstETH));
            signallingTokensBuilder.set("withdrawal_queue", address(ctx.dualGovernance.signallingTokens.withdrawalQueue));

            dgConfigBuilder.set("admin_proposer", ctx.dualGovernance.adminProposer);
            dgConfigBuilder.set("reseal_committee", ctx.dualGovernance.resealCommittee);
            dgConfigBuilder.set("proposals_canceller", ctx.dualGovernance.proposalsCanceller);
            dgConfigBuilder.set("config", configBuilder.content);
            dgConfigBuilder.set("signalling_tokens", signallingTokensBuilder.content);
            dgConfigBuilder.set("sanity_check_params", sanityCheckParamsBuilder.content);
            dgConfigBuilder.set("sealable_withdrawal_blockers", ctx.dualGovernance.sealableWithdrawalBlockers);

        }

        ConfigFileBuilder.Context memory deployConfigBuilder = ConfigFileBuilder.create();
        // forgefmt: disable-next-item
        {
            deployConfigBuilder.set("chain_id", ctx.chainId);
            deployConfigBuilder.set("dual_governance", dgConfigBuilder.content);
            deployConfigBuilder.set("tiebreaker", tiebreakerConfigBuilder.content);
            deployConfigBuilder.set("timelock", timelockConfigBuilder.content);
        }

        return deployConfigBuilder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("TODO: print all config params");
    }

    error InvalidQuorum(string committee, uint256 quorum);
    error InvalidParameter(string parameter);
    error InvalidChain(string chainName);

    function validate(Context memory ctx) internal pure {
        if (ctx.tiebreaker.quorum == 0) {
            revert InvalidQuorum("TIEBREAKER_CORE", ctx.tiebreaker.quorum);
        }

        for (uint256 i = 0; i < ctx.tiebreaker.committees.length; ++i) {
            _checkCommitteeQuorum(ctx.tiebreaker.committees[i], string.concat("tiebreaker[", vm.toString(i), "]"));
        }

        if (ctx.timelock.afterSubmitDelay > ctx.timelock.sanityCheckParams.maxAfterSubmitDelay) {
            revert InvalidParameter("after_submit_delay");
        }

        if (ctx.timelock.afterScheduleDelay > ctx.timelock.sanityCheckParams.maxAfterScheduleDelay) {
            revert InvalidParameter("after_schedule_delay");
        }

        if (ctx.timelock.emergencyModeDuration > ctx.timelock.sanityCheckParams.maxEmergencyModeDuration) {
            revert InvalidParameter("emergency_mode_duration");
        }

        if (
            ctx.dualGovernance.sanityCheckParams.minTiebreakerActivationTimeout
                > ctx.dualGovernance.sanityCheckParams.maxTiebreakerActivationTimeout
        ) {
            revert InvalidParameter("dual_governance.sanity_check_params.min_activation_timeout");
        }

        if (ctx.tiebreaker.activationTimeout > ctx.dualGovernance.sanityCheckParams.maxTiebreakerActivationTimeout) {
            revert InvalidParameter("dual_governance.tiebreaker.activation_timeout");
        }

        if (ctx.dualGovernance.sanityCheckParams.maxSealableWithdrawalBlockersCount == 0) {
            revert InvalidParameter("max_sealable_withdrawal_blockers_count");
        }

        if (
            ctx.dualGovernance.sealableWithdrawalBlockers.length
                > ctx.dualGovernance.sanityCheckParams.maxSealableWithdrawalBlockersCount
        ) {
            revert InvalidParameter("tiebreaker.SEALABLE_WITHDRAWAL_BLOCKERS");
        }

        if (
            ctx.dualGovernance.dualGovernanceConfig.vetoSignallingMinDuration
                > ctx.dualGovernance.dualGovernanceConfig.vetoSignallingMaxDuration
        ) {
            revert InvalidParameter("veto_signalling_min_duration");
        }
    }

    function _checkCommitteeQuorum(
        TiebreakerCommitteeDeployConfig memory committee,
        string memory message
    ) internal pure {
        if (committee.quorum == 0 || committee.quorum > committee.members.length) {
            revert InvalidQuorum(message, committee.quorum);
        }
    }
}

library ContractsDeployment {
    function deployTGSetup(
        address deployer,
        TGDeployConfig.Context memory config
    ) internal returns (TGDeployedContracts.Context memory contracts) {
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
        DGDeployConfig.Context memory deployConfig
    ) internal returns (DGDeployedContracts.Context memory contracts) {
        console.log("Deploy DG Setup");
        contracts.adminExecutor = deployExecutor({owner: deployer});

        contracts.timelock = deployEmergencyProtectedTimelock(
            contracts.adminExecutor,
            deployConfig.timelock.afterSubmitDelay,
            deployConfig.timelock.afterScheduleDelay,
            deployConfig.timelock.sanityCheckParams
        );

        contracts.resealManager = deployResealManager(contracts.timelock);

        contracts.dualGovernanceConfigProvider =
            deployDualGovernanceConfigProvider(deployConfig.dualGovernance.dualGovernanceConfig);

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

        configureDualGovernance(
            contracts.adminExecutor,
            contracts.dualGovernance,
            contracts.tiebreakerCoreCommittee,
            deployConfig.dualGovernance
        );

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
        TiebreakerDeployConfig memory tiebreakerConfig,
        DualGovernanceDeployConfig memory dgDeployConfig
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
            abi.encodeCall(dualGovernance.setTiebreakerActivationTimeout, tiebreakerConfig.activationTimeout)
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
        TiebreakerCoreCommittee tiebreakerCoreCommittee,
        DualGovernanceDeployConfig memory dgDeployConfig
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
        TimelockDeployConfig memory timelockConfig
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

library ConfigFileBuilder {
    error InvalidConfigFormat(uint256 format);

    enum ConfigFormat {
        JSON,
        TOML
    }

    struct Context {
        string id;
        string content;
    }

    function create() internal returns (Context memory ctx) {
        ctx.id = _nextId();
    }

    function write(Context memory ctx, string memory path) internal {
        ConfigFormat outputFileFormat = getFileFormatByPath(path);

        if (outputFileFormat == ConfigFormat.JSON) {
            stdJson.write(ctx.content, path);
        } else if (outputFileFormat == ConfigFormat.TOML) {
            stdToml.write(ctx.content, path);
        } else {
            revert InvalidConfigFormat(uint256(outputFileFormat));
        }
    }

    function set(Context memory ctx, string memory key, uint256 value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, Duration value) internal returns (Context memory) {
        return set(ctx, key, value.toSeconds());
    }

    function set(Context memory ctx, string memory key, Timestamp value) internal returns (Context memory) {
        return set(ctx, key, value.toSeconds());
    }

    function set(Context memory ctx, string memory key, PercentD16 value) internal returns (Context memory) {
        return set(ctx, key, value.toUint256());
    }

    function set(Context memory ctx, string memory key, address value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, address[] memory value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, string[] memory value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, string memory value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.id, key, value);
        return ctx;
    }

    function _nextId() private returns (string memory id) {
        bytes32 slot = keccak256("config-files.storage.counter");

        uint256 count = uint256(vm.load(address(this), slot)) + 1;
        vm.store(address(this), slot, bytes32(count));
        return string(abi.encodePacked(address(this), count));
    }

    function getFileFormatByPath(string memory path) internal pure returns (ConfigFormat) {
        // solhint-disable-next-line custom-errors
        require(bytes(path).length > 0, "empty file path");

        string[] memory pathSplit = vm.split(path, ".");

        string memory fileFormat = pathSplit[pathSplit.length - 1];
        bytes32 fileExtensionDigest = keccak256(bytes(vm.toLowercase(fileFormat)));

        if (fileExtensionDigest == keccak256(bytes("toml"))) {
            return ConfigFormat.TOML;
        } else if (fileExtensionDigest == keccak256(bytes("json"))) {
            return ConfigFormat.JSON;
        }
        // solhint-disable-next-line custom-errors
        revert(string.concat("Unsupported file format: ", fileFormat));
    }
}
