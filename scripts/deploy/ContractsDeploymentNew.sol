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

struct TiebreakerCommitteeDeployConfig {
    uint256 quorum;
    address[] members;
}

struct TiebreakerDeployConfig {
    uint256 quorum;
    uint256 committeesCount;
    Duration executionDelay;
    Duration activationTimeout;
    Duration minActivationTimeout;
    Duration maxActivationTimeout;
    TiebreakerCommitteeDeployConfig[] committees;
}

struct DualGovernanceDeployConfig {
    DualGovernanceConfig.Context dualGovernanceConfig;
    DualGovernance.SignallingTokens signallingTokens;
    DualGovernance.SanityCheckParams sanityCheckParams;
    address adminProposer;
    address resealCommittee;
    address proposalsCanceller;
    address[] sealableWithdrawalBlockers;
}

struct EmergencyProtectedTimelockDeployConfig {
    Duration afterSubmitDelay;
    Duration afterScheduleDelay;
    EmergencyProtectedTimelock.SanityCheckParams sanityCheckParams;
    address emergencyGovernanceProposer;
    address emergencyActivationCommittee;
    address emergencyExecutionCommittee;
    Duration emergencyModeDuration;
    Timestamp emergencyProtectionEndDate;
}

struct DeployedDualGovernanceContracts {
    Executor adminExecutor;
    EmergencyProtectedTimelock timelock;
    TimelockedGovernance emergencyGovernance;
    ResealManager resealManager;
    DualGovernance dualGovernance;
    ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider;
    TiebreakerCoreCommittee tiebreakerCoreCommittee;
    TiebreakerSubCommittee[] tiebreakerSubCommittees;
}

library DeployedContracts {
    using ConfigKeys for ConfigKeys.Context;
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

    function load(string memory configFilePath, string memory configPrefix) internal returns (Context memory ctx) {
        ConfigFileReader.Context memory configFile = ConfigFileReader.load(configFilePath);
        ConfigKeys.Context memory keys = ConfigKeys.create(configPrefix);

        ctx.adminExecutor = Executor(payable(configFile.readAddress(keys.key("ADMIN_EXECUTOR"))));
        ctx.timelock = EmergencyProtectedTimelock(configFile.readAddress(keys.key("TIMELOCK")));
        ctx.emergencyGovernance = TimelockedGovernance(configFile.readAddress(keys.key("EMERGENCY_GOVERNANCE")));
        ctx.resealManager = ResealManager(configFile.readAddress(keys.key("RESEAL_MANAGER")));
        ctx.dualGovernance = DualGovernance(configFile.readAddress(keys.key("DUAL_GOVERNANCE")));
        ctx.dualGovernanceConfigProvider =
            ImmutableDualGovernanceConfigProvider(configFile.readAddress(keys.key("DUAL_GOVERNANCE_CONFIG_PROVIDER")));
        ctx.tiebreakerCoreCommittee =
            TiebreakerCoreCommittee(configFile.readAddress(keys.key("TIEBREAKER_CORE_COMMITTEE")));

        address[] memory tiebreakerSubCommittees = configFile.readAddressArray(keys.key("TIEBREAKER_SUB_COMMITTEES"));
        ctx.tiebreakerSubCommittees = new TiebreakerSubCommittee[](tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            ctx.tiebreakerSubCommittees[i] = TiebreakerSubCommittee(tiebreakerSubCommittees[i]);
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();

        address[] memory tiebreakerSubCommittees = new address[](ctx.tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            tiebreakerSubCommittees[i] = address(ctx.tiebreakerSubCommittees[i]);
        }

        // forgefmt: disable-next-item
        return configBuilder
            .set("ADMIN_EXECUTOR", address(ctx.adminExecutor))
            .set("TIMELOCK", address(ctx.timelock))
            .set("EMERGENCY_GOVERNANCE", address(ctx.emergencyGovernance))
            .set("RESEAL_MANAGER", address(ctx.emergencyGovernance))
            .set("DUAL_GOVERNANCE", address(ctx.emergencyGovernance))
            .set("DUAL_GOVERNANCE_CONFIG_PROVIDER", address(ctx.emergencyGovernance))
            .set("TIEBREAKER_CORE_COMMITTEE", address(ctx.emergencyGovernance))
            .set("TIEBREAKER_SUB_COMMITTEES", tiebreakerSubCommittees)
            .content;
    }
}

library DeployArtifacts {
    using DeployConfig for DeployConfig.Context;
    using DeployConfigKeys for ConfigKeys.Context;
    using ConfigFileBuilder for ConfigFileBuilder.Context;
    using DeployedContracts for DeployedContracts.Context;

    struct Context {
        DeployConfig.Context deployConfig;
        DeployedContracts.Context deployedContracts;
    }

    function load(string memory deployArtifactsFilePath) internal returns (Context memory ctx) {
        ctx.deployConfig = DeployConfig.load(deployArtifactsFilePath, "DEPLOY_CONFIG");
        ctx.deployedContracts = DeployedContracts.load(deployArtifactsFilePath, "DEPLOYED_CONTRACTS");
    }

    function save(Context memory ctx, string memory deployArtifactsFilePath) internal {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();

        configBuilder.set("DEPLOY_CONFIG", ctx.deployConfig.toJSON()).set(
            "DEPLOYED_CONTRACTS", ctx.deployedContracts.toJSON()
        ).write(deployArtifactsFilePath);
    }

    function create(
        DeployConfig.Context memory deployConfig,
        DeployedContracts.Context memory deployedContracts
    ) internal {}
}

library ConfigKeys {
    struct Context {
        string prefix;
    }

    function create(string memory prefix) internal pure returns (Context memory ctx) {
        ctx.prefix = prefix;
    }

    function root(Context memory ctx) internal pure returns (string memory) {
        return bytes(ctx.prefix).length == 0 ? "$" : string.concat("$", ".", ctx.prefix);
    }

    function key(Context memory ctx, string memory key) internal pure returns (string memory) {
        return string.concat(root(ctx), ".", key);
    }
}

library DeployConfigKeys {
    using ConfigKeys for ConfigKeys.Context;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function dg(ConfigKeys.Context memory ctx, string memory key) internal pure returns (string memory) {
        return string.concat(ctx.root(), ".", "DUAL_GOVERNANCE", ".", key);
    }

    function tiebreaker(ConfigKeys.Context memory ctx, string memory key) internal pure returns (string memory) {
        return string.concat(ctx.root(), ".", "TIEBREAKER", ".", key);
    }

    function timelock(ConfigKeys.Context memory ctx, string memory key) internal pure returns (string memory) {
        return string.concat(ctx.root(), ".", "EMERGENCY_PROTECTED_TIMELOCK", ".", key);
    }

    function tiebreakerCommittee(
        ConfigKeys.Context memory ctx,
        uint256 index,
        string memory key
    ) internal pure returns (string memory) {
        return tiebreaker(ctx, string.concat("COMMITTEES[", vm.toString(index), "]", ".", key));
    }
}

library DeployConfig {
    using ConfigFileBuilder for ConfigFileBuilder.Context;
    using ConfigFileReader for ConfigFileReader.Context;
    using ConfigKeys for ConfigKeys.Context;
    using DeployConfigKeys for ConfigKeys.Context;

    struct Context {
        uint256 chainId;
        TiebreakerDeployConfig tiebreaker;
        DualGovernanceDeployConfig dualGovernance;
        EmergencyProtectedTimelockDeployConfig timelock;
    }

    // solhint-disable-next-line const-name-snakecase
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function load(string memory configFilePath, string memory configPrefix) internal returns (Context memory ctx) {
        ConfigFileReader.Context memory configFile = ConfigFileReader.load(configFilePath);
        ConfigKeys.Context memory keys = ConfigKeys.create(configPrefix);

        // ---
        // Chain ID
        // ---

        ctx.chainId = configFile.readUint(keys.key("CHAIN_ID"));

        // ---
        // Tiebreaker
        // ---

        TiebreakerCommitteeDeployConfig[] memory tiebreakerCommitteeConfigs =
            new TiebreakerCommitteeDeployConfig[](ctx.tiebreaker.committeesCount);

        for (uint256 i = 0; i < tiebreakerCommitteeConfigs.length; ++i) {
            tiebreakerCommitteeConfigs[i].quorum = configFile.readUint(keys.tiebreakerCommittee(i, "QUORUM"));
            tiebreakerCommitteeConfigs[i].members = configFile.readAddressArray(keys.tiebreakerCommittee(i, "MEMBERS"));
        }

        ctx.tiebreaker = TiebreakerDeployConfig({
            quorum: configFile.readUint(keys.tiebreaker("QUORUM")),
            committeesCount: configFile.readUint(keys.tiebreaker("COMMITTEES_COUNT")),
            executionDelay: configFile.readDuration(keys.tiebreaker("EXECUTION_DELAY")),
            activationTimeout: configFile.readDuration(keys.tiebreaker("ACTIVATION_TIMEOUT")),
            minActivationTimeout: configFile.readDuration(keys.tiebreaker("MIN_ACTIVATION_TIMEOUT")),
            maxActivationTimeout: configFile.readDuration(keys.tiebreaker("MIN_ACTIVATION_TIMEOUT")),
            committees: tiebreakerCommitteeConfigs
        });

        // ---
        // Emergency Protected Timelock
        // ---

        ctx.timelock = EmergencyProtectedTimelockDeployConfig({
            afterSubmitDelay: configFile.readDuration(keys.timelock("AFTER_SUBMIT_DELAY")),
            afterScheduleDelay: configFile.readDuration(keys.timelock("AFTER_SCHEDULE_DELAY")),
            sanityCheckParams: EmergencyProtectedTimelock.SanityCheckParams({
                minExecutionDelay: configFile.readDuration(keys.timelock("MIN_EXECUTION_DELAY")),
                maxAfterSubmitDelay: configFile.readDuration(keys.timelock("MAX_AFTER_SUBMIT_DELAY")),
                maxAfterScheduleDelay: configFile.readDuration(keys.timelock("MAX_AFTER_SCHEDULE_DELAY")),
                maxEmergencyModeDuration: configFile.readDuration(keys.timelock("MAX_EMERGENCY_MODE_DURATION")),
                maxEmergencyProtectionDuration: configFile.readDuration(keys.timelock("MAX_EMERGENCY_PROTECTION_DURATION"))
            }),
            emergencyGovernanceProposer: configFile.readAddress(keys.timelock("EMERGENCY_GOVERNANCE_PROPOSER")),
            emergencyActivationCommittee: configFile.readAddress(keys.timelock("EMERGENCY_ACTIVATION_COMMITTEE")),
            emergencyExecutionCommittee: configFile.readAddress(keys.timelock("EMERGENCY_EXECUTION_COMMITTEE")),
            emergencyModeDuration: configFile.readDuration(keys.timelock("EMERGENCY_MODE_DURATION")),
            emergencyProtectionEndDate: configFile.readTimestamp(keys.timelock("EMERGENCY_PROTECTION_END_DATE"))
        });

        // ---
        // Dual Governance
        // ---

        ctx.dualGovernance = DualGovernanceDeployConfig({
            dualGovernanceConfig: DualGovernanceConfig.Context({
                firstSealRageQuitSupport: configFile.readPercentD16BP(keys.dg("FIRST_SEAL_RAGE_QUIT_SUPPORT")),
                secondSealRageQuitSupport: configFile.readPercentD16BP(keys.dg("SECOND_SEAL_RAGE_QUIT_SUPPORT")),
                //
                minAssetsLockDuration: configFile.readDuration(keys.dg("MIN_ASSETS_LOCK_DURATION")),
                //
                vetoSignallingMinDuration: configFile.readDuration(keys.dg("VETO_SIGNALLING_MIN_DURATION")),
                vetoSignallingMaxDuration: configFile.readDuration(keys.dg("VETO_SIGNALLING_MAX_DURATION")),
                vetoSignallingMinActiveDuration: configFile.readDuration(keys.dg("VETO_SIGNALLING_MIN_ACTIVE_DURATION")),
                vetoSignallingDeactivationMaxDuration: configFile.readDuration(keys.dg("VETO_SIGNALLING_MAX_DURATION")),
                vetoCooldownDuration: configFile.readDuration(keys.dg("VETO_COOLDOWN_DURATION")),
                //
                rageQuitExtensionPeriodDuration: configFile.readDuration(keys.dg("RAGE_QUIT_EXTENSION_PERIOD_DURATION")),
                rageQuitEthWithdrawalsMinDelay: configFile.readDuration(keys.dg("RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY")),
                rageQuitEthWithdrawalsMaxDelay: configFile.readDuration(keys.dg("RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY")),
                rageQuitEthWithdrawalsDelayGrowth: configFile.readDuration(keys.dg("RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH"))
            }),
            signallingTokens: DualGovernance.SignallingTokens({
                stETH: IStETH(configFile.readAddress(keys.dg("ST_ETH"))),
                wstETH: IWstETH(configFile.readAddress(keys.dg("WST_ETH"))),
                withdrawalQueue: IWithdrawalQueue(configFile.readAddress(keys.dg("UNST_ETH")))
            }),
            sanityCheckParams: DualGovernance.SanityCheckParams({
                minWithdrawalsBatchSize: configFile.readUint(keys.dg("MIN_WITHDRAWALS_BATCH_SIZE")),
                minTiebreakerActivationTimeout: configFile.readDuration(keys.tiebreaker("MIN_ACTIVATION_TIMEOUT")),
                maxTiebreakerActivationTimeout: configFile.readDuration(keys.tiebreaker("MAX_ACTIVATION_TIMEOUT")),
                maxSealableWithdrawalBlockersCount: configFile.readUint(keys.dg("MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT")),
                maxMinAssetsLockDuration: configFile.readDuration(keys.dg("MAX_MIN_ASSETS_LOCK_DURATION"))
            }),
            adminProposer: configFile.readAddress(keys.dg("ADMIN_PROPOESER")),
            resealCommittee: configFile.readAddress(keys.dg("RESEAL_COMMITTEE")),
            proposalsCanceller: configFile.readAddress(keys.dg("PROPOSALS_CANCELLER")),
            sealableWithdrawalBlockers: configFile.readAddressArray(keys.dg("SEALABLE_WITHDRAWAL_BLOCKERS"))
        });
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory tiebreakerCommitteesConfigBuilder = ConfigFileBuilder.create();

        for (uint256 i = 0; i < ctx.tiebreaker.committees.length; ++i) {
            string memory arrayKey = string.concat("[", vm.toString(i), "]");
            // forgefmt: disable-next-item
            tiebreakerCommitteesConfigBuilder
                .set(string.concat(arrayKey, ".", "QUORUM"), ctx.tiebreaker.committees[i].quorum)
                .set(string.concat(arrayKey, ".", "MEMBERS"), ctx.tiebreaker.committees[i].members);
        }

        // forgefmt: disable-next-item
        return ConfigFileBuilder.create()
            .set("CHAIN_ID", ctx.chainId)
            .set("DUAL_GOVERNANCE", ConfigFileBuilder.create()
                .set("ST_ETH", address(ctx.dualGovernance.signallingTokens.stETH))
                .set("WST_ETH", address(ctx.dualGovernance.signallingTokens.wstETH))
                .set("UNST_ETH", address(ctx.dualGovernance.signallingTokens.withdrawalQueue))

                .set("ADMIN_PROPOESER", ctx.dualGovernance.adminProposer)
                .set("RESEAL_COMMITTEE", ctx.dualGovernance.resealCommittee)
                .set("PROPOSALS_CANCELLER", ctx.dualGovernance.proposalsCanceller)

                .set("FIRST_SEAL_RAGE_QUIT_SUPPORT", ctx.dualGovernance.dualGovernanceConfig.firstSealRageQuitSupport)
                .set("SECOND_SEAL_RAGE_QUIT_SUPPORT", ctx.dualGovernance.dualGovernanceConfig.secondSealRageQuitSupport)
                .set("MIN_ASSETS_LOCK_DURATION", ctx.dualGovernance.dualGovernanceConfig.minAssetsLockDuration)
                .set("RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH", ctx.dualGovernance.dualGovernanceConfig.rageQuitEthWithdrawalsDelayGrowth)
                .set("RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY", ctx.dualGovernance.dualGovernanceConfig.rageQuitEthWithdrawalsMaxDelay)
                .set("RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY",ctx.dualGovernance.dualGovernanceConfig.rageQuitEthWithdrawalsMinDelay)
                .set("RAGE_QUIT_EXTENSION_PERIOD_DURATION", ctx.dualGovernance.dualGovernanceConfig.rageQuitExtensionPeriodDuration)
                .set("VETO_COOLDOWN_DURATION", ctx.dualGovernance.dualGovernanceConfig.vetoCooldownDuration)
                .set("MAX_MIN_ASSETS_LOCK_DURATION", ctx.dualGovernance.sanityCheckParams.maxMinAssetsLockDuration)
                .set("MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT", ctx.dualGovernance.sanityCheckParams.maxSealableWithdrawalBlockersCount)
                .set("VETO_SIGNALLING_DEACTIVATION_MAX_DURATION", ctx.dualGovernance.dualGovernanceConfig.vetoSignallingDeactivationMaxDuration)
                .set("VETO_SIGNALLING_MAX_DURATION", ctx.dualGovernance.dualGovernanceConfig.vetoSignallingMaxDuration)
                .set("VETO_SIGNALLING_MIN_ACTIVE_DURATION", ctx.dualGovernance.dualGovernanceConfig.vetoSignallingMinActiveDuration)
                .set("VETO_SIGNALLING_MIN_DURATION", ctx.dualGovernance.dualGovernanceConfig.vetoSignallingMinDuration)
                .set("SEALABLE_WITHDRAWAL_BLOCKERS", ctx.dualGovernance.sealableWithdrawalBlockers)
                .content
            ).set("EMERGENCY_PROTECTED_TIMELOCK", ConfigFileBuilder.create()
                .set("AFTER_SCHEDULE_DELAY", ctx.timelock.afterScheduleDelay)
                .set("AFTER_SUBMIT_DELAY", ctx.timelock.afterSubmitDelay)
                .set("EMERGENCY_MODE_DURATION", ctx.timelock.emergencyModeDuration)
                .set("EMERGENCY_PROTECTION_END_DATE", ctx.timelock.emergencyProtectionEndDate)
                .set("MAX_AFTER_SCHEDULE_DELAY", ctx.timelock.sanityCheckParams.maxAfterScheduleDelay)
                .set("MAX_AFTER_SUBMIT_DELAY", ctx.timelock.sanityCheckParams.maxAfterSubmitDelay)
                .set("MAX_EMERGENCY_MODE_DURATION", ctx.timelock.sanityCheckParams.maxEmergencyModeDuration)
                .set("MAX_EMERGENCY_PROTECTION_DURATION", ctx.timelock.sanityCheckParams.maxEmergencyProtectionDuration)
                .set("MIN_EXECUTION_DELAY", ctx.timelock.sanityCheckParams.minExecutionDelay)
                .set("EMERGENCY_GOVERNANCE_PROPOSER", ctx.timelock.emergencyGovernanceProposer)
                .set("EMERGENCY_ACTIVATION_COMMITTEE", ctx.timelock.emergencyActivationCommittee)
                .set("EMERGENCY_EXECUTION_COMMITTEE", ctx.timelock.emergencyExecutionCommittee)
                .content
            )
            .set("TIEBREAKER", ConfigFileBuilder.create()
                .set("QUORUM", ctx.tiebreaker.quorum)
                .set("ACTIVATION_TIMEOUT", ctx.tiebreaker.activationTimeout)
                .set("EXECUTION_DELAY", ctx.tiebreaker.executionDelay)
                .set("MAX_ACTIVATION_TIMEOUT", ctx.tiebreaker.maxActivationTimeout)
                .set("MIN_ACTIVATION_TIMEOUT", ctx.tiebreaker.minActivationTimeout)
                .set("COMMITTEES_COUNT", ctx.tiebreaker.committeesCount)
                .set("COMMITTEES", tiebreakerCommitteesConfigBuilder.content)
                .content
            ).content;
    }
}

library DGContractsDeployment {
    function deployDualGovernanceSetup(
        address deployer,
        DeployConfig.Context memory deployConfig
    ) internal returns (DeployedContracts.Context memory contracts) {
        contracts.adminExecutor = deployExecutor({owner: deployer});

        contracts.timelock = deployEmergencyProtectedTimelock(
            address(contracts.adminExecutor),
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

        configureEmergencyProtectedTimelock(contracts.adminExecutor, contracts.timelock, deployConfig.timelock);

        finalizeEmergencyProtectedTimelockDeploy(
            contracts.adminExecutor, contracts.timelock, address(contracts.dualGovernance)
        );
    }

    function deployExecutor(address owner) internal returns (Executor) {
        return new Executor(owner);
    }

    function deployEmergencyProtectedTimelock(
        address adminExecutor,
        Duration afterSubmitDelay,
        Duration afterScheduleDelay,
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams
    ) internal returns (EmergencyProtectedTimelock) {
        return new EmergencyProtectedTimelock(sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay);
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
        EmergencyProtectedTimelockDeployConfig memory timelockConfig
    ) internal {
        if (timelockConfig.emergencyGovernanceProposer != address(0)) {
            TimelockedGovernance emergencyGovernance =
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
                    timelock.setEmergencyProtectionActivationCommittee, (timelockConfig.emergencyExecutionCommittee)
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
        address dualGovernance
    ) internal {
        adminExecutor.execute(address(timelock), 0, abi.encodeCall(timelock.setGovernance, (dualGovernance)));
        adminExecutor.transferOwnership(address(timelock));
    }
}

library ConfigFileBuilder {
    error InvalidConfigFormat(uint256 format);

    // solhint-disable-next-line const-name-snakecase
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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
        ctx.content = stdJson.serialize(ctx.content, key, value);
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
        ctx.content = stdJson.serialize(ctx.content, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, address[] memory value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.content, key, value);
        return ctx;
    }

    function set(Context memory ctx, string memory key, string memory value) internal returns (Context memory) {
        ctx.content = stdJson.serialize(ctx.content, key, value);
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
