// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// ---
// Contracts
// ---
import {Timestamps} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {EmergencyExecutionCommittee} from "contracts/committees/EmergencyExecutionCommittee.sol";
import {EmergencyActivationCommittee} from "contracts/committees/EmergencyActivationCommittee.sol";

import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";

import {ResealManager} from "contracts/ResealManager.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {
    DualGovernanceConfig,
    IDualGovernanceConfigProvider,
    ImmutableDualGovernanceConfigProvider
} from "contracts/DualGovernanceConfigProvider.sol";

import {ResealCommittee} from "contracts/committees/ResealCommittee.sol";
import {TiebreakerCore} from "contracts/committees/TiebreakerCore.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

import {DGDeployConfig, ConfigValues, LidoAddresses, getLidoAddresses} from "./Config.s.sol";
import {DeployValidation} from "./DeployValidation.sol";

struct DeployedContracts {
    Executor adminExecutor;
    EmergencyProtectedTimelock timelock;
    TimelockedGovernance emergencyGovernance;
    EmergencyActivationCommittee emergencyActivationCommittee;
    EmergencyExecutionCommittee emergencyExecutionCommittee;
    ResealManager resealManager;
    DualGovernance dualGovernance;
    ResealCommittee resealCommittee;
    TiebreakerCore tiebreakerCoreCommittee;
    address tiebreakerSubCommittee1;
    address tiebreakerSubCommittee2;
}

contract DeployDG is Script {
    using DeployValidation for DeployValidation.DeployResult;

    DeployedContracts private _contracts;

    address internal deployer;

    function run() external {
        DGDeployConfig configProvider = new DGDeployConfig();
        ConfigValues memory _dgDeployConfig = configProvider.loadAndValidate();

        // TODO: check chain id?

        deployer = vm.addr(_dgDeployConfig.DEPLOYER_PRIVATE_KEY);
        vm.startBroadcast(_dgDeployConfig.DEPLOYER_PRIVATE_KEY);

        deployDualGovernanceSetup(_dgDeployConfig);

        vm.stopBroadcast();

        DeployValidation.DeployResult memory res = getDeployedAddresses(_contracts);

        console.log("DG deployed successfully");
        console.log("DualGovernance address", res.dualGovernance);
        console.log("ResealManager address", res.resealManager);
        console.log("TiebreakerCoreCommittee address", res.tiebreakerCoreCommittee);
        console.log("TiebreakerSubCommittee #1 address", _contracts.tiebreakerSubCommittee1);
        console.log("TiebreakerSubCommittee #2 address", _contracts.tiebreakerSubCommittee2);
        console.log("AdminExecutor address", res.adminExecutor);
        console.log("EmergencyProtectedTimelock address", res.timelock);
        console.log("EmergencyGovernance address", res.emergencyGovernance);
        console.log("EmergencyActivationCommittee address", res.emergencyActivationCommittee);
        console.log("EmergencyExecutionCommittee address", res.emergencyExecutionCommittee);
        console.log("ResealCommittee address", res.resealCommittee);

        console.log("Verifying deploy");

        res.check();

        console.log(unicode"Verified ✅");
    }

    function deployDualGovernanceSetup(ConfigValues memory dgDeployConfig) internal {
        LidoAddresses memory lidoAddresses = getLidoAddresses(dgDeployConfig);
        _contracts = deployEmergencyProtectedTimelockContracts(lidoAddresses, dgDeployConfig, _contracts);
        _contracts.resealManager = deployResealManager(_contracts.timelock);
        ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider =
            deployDualGovernanceConfigProvider(dgDeployConfig);
        DualGovernance dualGovernance = deployDualGovernance({
            configProvider: dualGovernanceConfigProvider,
            timelock: _contracts.timelock,
            resealManager: _contracts.resealManager,
            dgDeployConfig: dgDeployConfig,
            lidoAddresses: lidoAddresses
        });
        _contracts.dualGovernance = dualGovernance;

        _contracts.tiebreakerCoreCommittee = deployEmptyTiebreakerCoreCommittee({
            owner: deployer, // temporary set owner to deployer, to add sub committees manually
            dualGovernance: address(dualGovernance),
            executionDelay: dgDeployConfig.TIEBREAKER_EXECUTION_DELAY
        });

        address[] memory tiebreakerSubCommittees = deployTiebreakerSubCommittees(
            address(_contracts.adminExecutor), _contracts.tiebreakerCoreCommittee, dgDeployConfig
        );
        _contracts.tiebreakerSubCommittee1 = tiebreakerSubCommittees[0];
        _contracts.tiebreakerSubCommittee2 = tiebreakerSubCommittees[1];

        _contracts.tiebreakerCoreCommittee.transferOwnership(address(_contracts.adminExecutor));

        _contracts.resealCommittee =
            deployResealCommittee(address(_contracts.adminExecutor), address(dualGovernance), dgDeployConfig);

        // ---
        // Finalize Setup
        // ---
        _contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(
                dualGovernance.registerProposer, (address(lidoAddresses.voting), address(_contracts.adminExecutor))
            )
        );
        _contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerActivationTimeout, dgDeployConfig.TIEBREAKER_ACTIVATION_TIMEOUT)
        );
        _contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerCommittee, address(_contracts.tiebreakerCoreCommittee))
        );
        _contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(
                dualGovernance.addTiebreakerSealableWithdrawalBlocker, address(lidoAddresses.withdrawalQueue)
            )
        );
        _contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setResealCommittee, address(_contracts.resealCommittee))
        );

        finalizeEmergencyProtectedTimelockDeploy(
            _contracts.adminExecutor, _contracts.timelock, address(dualGovernance), dgDeployConfig
        );

        // ---
        // TODO: Grant Reseal Manager Roles
        // ---
        /* vm.startPrank(address(_lido.agent));
        _lido.withdrawalQueue.grantRole(
            0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d, address(resealManager)
        );
        _lido.withdrawalQueue.grantRole(
            0x2fc10cc8ae19568712f7a176fb4978616a610650813c9d05326c34abb62749c7, address(resealManager)
        );
        vm.stopPrank(); */
    }

    function deployEmergencyProtectedTimelockContracts(
        LidoAddresses memory lidoAddresses,
        ConfigValues memory dgDeployConfig,
        DeployedContracts memory contracts
    ) internal returns (DeployedContracts memory) {
        Executor adminExecutor = deployExecutor(deployer);
        EmergencyProtectedTimelock timelock = deployEmergencyProtectedTimelock(address(adminExecutor), dgDeployConfig);

        contracts.adminExecutor = adminExecutor;
        contracts.timelock = timelock;
        contracts.emergencyActivationCommittee = deployEmergencyActivationCommittee({
            quorum: dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM,
            members: dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS,
            owner: address(adminExecutor),
            timelock: address(timelock)
        });

        contracts.emergencyExecutionCommittee = deployEmergencyExecutionCommittee({
            quorum: dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_QUORUM,
            members: dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS,
            owner: address(adminExecutor),
            timelock: address(timelock)
        });
        contracts.emergencyGovernance =
            deployTimelockedGovernance({governance: address(lidoAddresses.voting), timelock: timelock});

        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setEmergencyProtectionActivationCommittee, (address(contracts.emergencyActivationCommittee))
            )
        );
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setEmergencyProtectionExecutionCommittee, (address(contracts.emergencyExecutionCommittee))
            )
        );

        // TODO: Do we really need to set it?
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setEmergencyProtectionEndDate,
                (dgDeployConfig.EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()))
            )
        );
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setEmergencyModeDuration, (dgDeployConfig.EMERGENCY_MODE_DURATION))
        );

        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setEmergencyGovernance, (address(contracts.emergencyGovernance)))
        );

        return contracts;
    }

    function deployExecutor(address owner) internal returns (Executor) {
        return new Executor(owner);
    }

    function deployEmergencyProtectedTimelock(
        address adminExecutor,
        ConfigValues memory dgDeployConfig
    ) internal returns (EmergencyProtectedTimelock) {
        return new EmergencyProtectedTimelock({
            adminExecutor: address(adminExecutor),
            sanityCheckParams: EmergencyProtectedTimelock.SanityCheckParams({
                maxAfterSubmitDelay: dgDeployConfig.MAX_AFTER_SUBMIT_DELAY,
                maxAfterScheduleDelay: dgDeployConfig.MAX_AFTER_SCHEDULE_DELAY,
                maxEmergencyModeDuration: dgDeployConfig.MAX_EMERGENCY_MODE_DURATION,
                maxEmergencyProtectionDuration: dgDeployConfig.MAX_EMERGENCY_PROTECTION_DURATION
            })
        });
    }

    function deployEmergencyActivationCommittee(
        address owner,
        uint256 quorum,
        address[] memory members,
        address timelock
    ) internal returns (EmergencyActivationCommittee) {
        return new EmergencyActivationCommittee(owner, members, quorum, address(timelock));
    }

    function deployEmergencyExecutionCommittee(
        address owner,
        uint256 quorum,
        address[] memory members,
        address timelock
    ) internal returns (EmergencyExecutionCommittee) {
        return new EmergencyExecutionCommittee(owner, members, quorum, address(timelock));
    }

    function deployTimelockedGovernance(
        address governance,
        EmergencyProtectedTimelock timelock
    ) internal returns (TimelockedGovernance) {
        return new TimelockedGovernance(governance, timelock);
    }

    function deployResealManager(EmergencyProtectedTimelock timelock) internal returns (ResealManager) {
        return new ResealManager(timelock);
    }

    function deployDualGovernanceConfigProvider(ConfigValues memory dgDeployConfig)
        internal
        returns (ImmutableDualGovernanceConfigProvider)
    {
        return new ImmutableDualGovernanceConfigProvider(
            DualGovernanceConfig.Context({
                firstSealRageQuitSupport: dgDeployConfig.FIRST_SEAL_RAGE_QUIT_SUPPORT,
                secondSealRageQuitSupport: dgDeployConfig.SECOND_SEAL_RAGE_QUIT_SUPPORT,
                //
                minAssetsLockDuration: dgDeployConfig.MIN_ASSETS_LOCK_DURATION,
                dynamicTimelockMinDuration: dgDeployConfig.DYNAMIC_TIMELOCK_MIN_DURATION,
                dynamicTimelockMaxDuration: dgDeployConfig.DYNAMIC_TIMELOCK_MAX_DURATION,
                //
                vetoSignallingMinActiveDuration: dgDeployConfig.VETO_SIGNALLING_MIN_ACTIVE_DURATION,
                vetoSignallingDeactivationMaxDuration: dgDeployConfig.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION,
                vetoCooldownDuration: dgDeployConfig.VETO_COOLDOWN_DURATION,
                //
                rageQuitExtensionDelay: dgDeployConfig.RAGE_QUIT_EXTENSION_DELAY,
                rageQuitEthWithdrawalsMinTimelock: dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK,
                rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber: dgDeployConfig
                    .RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER,
                rageQuitEthWithdrawalsTimelockGrowthCoeffs: dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS
            })
        );
    }

    function deployDualGovernance(
        IDualGovernanceConfigProvider configProvider,
        EmergencyProtectedTimelock timelock,
        ResealManager resealManager,
        ConfigValues memory dgDeployConfig,
        LidoAddresses memory lidoAddresses
    ) internal returns (DualGovernance) {
        return new DualGovernance({
            dependencies: DualGovernance.ExternalDependencies({
                stETH: lidoAddresses.stETH,
                wstETH: lidoAddresses.wstETH,
                withdrawalQueue: lidoAddresses.withdrawalQueue,
                timelock: timelock,
                resealManager: resealManager,
                configProvider: configProvider
            }),
            sanityCheckParams: DualGovernance.SanityCheckParams({
                minWithdrawalsBatchSize: dgDeployConfig.MIN_WITHDRAWALS_BATCH_SIZE,
                minTiebreakerActivationTimeout: dgDeployConfig.MIN_TIEBREAKER_ACTIVATION_TIMEOUT,
                maxTiebreakerActivationTimeout: dgDeployConfig.MAX_TIEBREAKER_ACTIVATION_TIMEOUT,
                maxSealableWithdrawalBlockersCount: dgDeployConfig.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT
            })
        });
    }

    function deployEmptyTiebreakerCoreCommittee(
        address owner,
        address dualGovernance,
        Duration executionDelay
    ) internal returns (TiebreakerCore) {
        return new TiebreakerCore({owner: owner, dualGovernance: dualGovernance, timelock: executionDelay});
    }

    function deployTiebreakerSubCommittees(
        address owner,
        TiebreakerCore tiebreakerCoreCommittee,
        ConfigValues memory dgDeployConfig
    ) internal returns (address[] memory) {
        address[] memory coreCommitteeMembers = new address[](dgDeployConfig.TIEBREAKER_SUB_COMMITTEES_COUNT);

        for (uint256 i = 0; i < dgDeployConfig.TIEBREAKER_SUB_COMMITTEES_COUNT; ++i) {
            address[] memory members;
            uint256 quorum;

            if (i == 0) {
                quorum = dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_1_QUORUM;
                members = dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS;
            } else {
                quorum = dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_2_QUORUM;
                members = dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS;
            }
            coreCommitteeMembers[i] = address(
                deployTiebreakerSubCommittee({
                    owner: owner,
                    quorum: quorum,
                    members: members,
                    tiebreakerCoreCommittee: address(tiebreakerCoreCommittee)
                })
            );
        }

        // TODO: configurable quorum?
        tiebreakerCoreCommittee.addMembers(coreCommitteeMembers, coreCommitteeMembers.length);

        return coreCommitteeMembers;
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
            tiebreakerCore: tiebreakerCoreCommittee
        });
    }

    function deployResealCommittee(
        address adminExecutor,
        address dualGovernance,
        ConfigValues memory dgDeployConfig
    ) internal returns (ResealCommittee) {
        uint256 quorum = dgDeployConfig.RESEAL_COMMITTEE_QUORUM;
        address[] memory committeeMembers = dgDeployConfig.RESEAL_COMMITTEE_MEMBERS;

        // TODO: Don't we need to use non-zero timelock here?
        return new ResealCommittee(adminExecutor, committeeMembers, quorum, dualGovernance, Durations.from(0));
    }

    function finalizeEmergencyProtectedTimelockDeploy(
        Executor adminExecutor,
        EmergencyProtectedTimelock timelock,
        address dualGovernance,
        ConfigValues memory dgDeployConfig
    ) internal {
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setupDelays, (dgDeployConfig.AFTER_SUBMIT_DELAY, dgDeployConfig.AFTER_SCHEDULE_DELAY)
            )
        );
        adminExecutor.execute(address(timelock), 0, abi.encodeCall(timelock.setGovernance, (dualGovernance)));
        adminExecutor.transferOwnership(address(timelock));
    }

    function getDeployedAddresses(DeployedContracts memory contracts)
        internal
        pure
        returns (DeployValidation.DeployResult memory)
    {
        return DeployValidation.DeployResult({
            adminExecutor: payable(address(contracts.adminExecutor)),
            timelock: address(contracts.timelock),
            emergencyGovernance: address(contracts.emergencyGovernance),
            emergencyActivationCommittee: address(contracts.emergencyActivationCommittee),
            emergencyExecutionCommittee: address(contracts.emergencyExecutionCommittee),
            resealManager: address(contracts.resealManager),
            dualGovernance: address(contracts.dualGovernance),
            resealCommittee: address(contracts.resealCommittee),
            tiebreakerCoreCommittee: address(contracts.tiebreakerCoreCommittee),
            tiebreakerSubCommittee1: contracts.tiebreakerSubCommittee1,
            tiebreakerSubCommittee2: contracts.tiebreakerSubCommittee2
        });
    }
}
