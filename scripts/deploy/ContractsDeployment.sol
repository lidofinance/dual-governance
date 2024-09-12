// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {ResealCommittee} from "contracts/committees/ResealCommittee.sol";
import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

import {DeployConfig, LidoContracts, getSubCommitteeData} from "./Config.sol";

struct DeployedContracts {
    Executor adminExecutor;
    EmergencyProtectedTimelock timelock;
    TimelockedGovernance emergencyGovernance;
    EmergencyActivationCommittee emergencyActivationCommittee;
    EmergencyExecutionCommittee emergencyExecutionCommittee;
    ResealManager resealManager;
    DualGovernance dualGovernance;
    ResealCommittee resealCommittee;
    TiebreakerCoreCommittee tiebreakerCoreCommittee;
    address[] tiebreakerSubCommittees;
}

library DGContractsDeployment {
    function deployDualGovernanceSetup(
        DeployConfig memory dgDeployConfig,
        LidoContracts memory lidoAddresses,
        address deployer
    ) internal returns (DeployedContracts memory contracts) {
        contracts = deployEmergencyProtectedTimelockContracts(lidoAddresses, dgDeployConfig, contracts, deployer);
        contracts.resealManager = deployResealManager(contracts.timelock);
        ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider =
            deployDualGovernanceConfigProvider(dgDeployConfig);
        DualGovernance dualGovernance = deployDualGovernance({
            configProvider: dualGovernanceConfigProvider,
            timelock: contracts.timelock,
            resealManager: contracts.resealManager,
            dgDeployConfig: dgDeployConfig,
            lidoAddresses: lidoAddresses
        });
        contracts.dualGovernance = dualGovernance;

        contracts.tiebreakerCoreCommittee = deployEmptyTiebreakerCoreCommittee({
            owner: deployer, // temporary set owner to deployer, to add sub committees manually
            dualGovernance: address(dualGovernance),
            executionDelay: dgDeployConfig.TIEBREAKER_EXECUTION_DELAY
        });

        contracts.tiebreakerSubCommittees = deployTiebreakerSubCommittees(
            address(contracts.adminExecutor), contracts.tiebreakerCoreCommittee, dgDeployConfig
        );

        contracts.tiebreakerCoreCommittee.transferOwnership(address(contracts.adminExecutor));

        contracts.resealCommittee =
            deployResealCommittee(address(contracts.adminExecutor), address(dualGovernance), dgDeployConfig);

        // ---
        // Finalize Setup
        // ---
        contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(
                dualGovernance.registerProposer, (address(lidoAddresses.voting), address(contracts.adminExecutor))
            )
        );
        contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerActivationTimeout, dgDeployConfig.TIEBREAKER_ACTIVATION_TIMEOUT)
        );
        contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerCommittee, address(contracts.tiebreakerCoreCommittee))
        );
        contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(
                dualGovernance.addTiebreakerSealableWithdrawalBlocker, address(lidoAddresses.withdrawalQueue)
            )
        );
        contracts.adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setResealCommittee, address(contracts.resealCommittee))
        );

        finalizeEmergencyProtectedTimelockDeploy(
            contracts.adminExecutor, contracts.timelock, address(dualGovernance), dgDeployConfig
        );

        // ---
        // TODO: Use this in voting script
        // Grant Reseal Manager Roles
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
        LidoContracts memory lidoAddresses,
        DeployConfig memory dgDeployConfig,
        DeployedContracts memory contracts,
        address deployer
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
        DeployConfig memory dgDeployConfig
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

    function deployDualGovernanceConfigProvider(DeployConfig memory dgDeployConfig)
        internal
        returns (ImmutableDualGovernanceConfigProvider)
    {
        return new ImmutableDualGovernanceConfigProvider(
            DualGovernanceConfig.Context({
                firstSealRageQuitSupport: dgDeployConfig.FIRST_SEAL_RAGE_QUIT_SUPPORT,
                secondSealRageQuitSupport: dgDeployConfig.SECOND_SEAL_RAGE_QUIT_SUPPORT,
                //
                minAssetsLockDuration: dgDeployConfig.MIN_ASSETS_LOCK_DURATION,
                vetoSignallingMinDuration: dgDeployConfig.VETO_SIGNALLING_MIN_DURATION,
                vetoSignallingMaxDuration: dgDeployConfig.VETO_SIGNALLING_MAX_DURATION,
                //
                vetoSignallingMinActiveDuration: dgDeployConfig.VETO_SIGNALLING_MIN_ACTIVE_DURATION,
                vetoSignallingDeactivationMaxDuration: dgDeployConfig.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION,
                vetoCooldownDuration: dgDeployConfig.VETO_COOLDOWN_DURATION,
                //
                rageQuitExtensionPeriodDuration: dgDeployConfig.RAGE_QUIT_EXTENSION_PERIOD_DURATION,
                rageQuitEthWithdrawalsMinDelay: dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY,
                rageQuitEthWithdrawalsMaxDelay: dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY,
                rageQuitEthWithdrawalsDelayGrowth: dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH
            })
        );
    }

    function deployDualGovernance(
        IDualGovernanceConfigProvider configProvider,
        EmergencyProtectedTimelock timelock,
        ResealManager resealManager,
        DeployConfig memory dgDeployConfig,
        LidoContracts memory lidoAddresses
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
    ) internal returns (TiebreakerCoreCommittee) {
        return new TiebreakerCoreCommittee({owner: owner, dualGovernance: dualGovernance, timelock: executionDelay});
    }

    function deployTiebreakerSubCommittees(
        address owner,
        TiebreakerCoreCommittee tiebreakerCoreCommittee,
        DeployConfig memory dgDeployConfig
    ) internal returns (address[] memory) {
        address[] memory coreCommitteeMembers = new address[](dgDeployConfig.TIEBREAKER_SUB_COMMITTEES_COUNT);

        for (uint256 i = 0; i < dgDeployConfig.TIEBREAKER_SUB_COMMITTEES_COUNT; ++i) {
            (uint256 quorum, address[] memory members) = getSubCommitteeData(i, dgDeployConfig);

            coreCommitteeMembers[i] = address(
                deployTiebreakerSubCommittee({
                    owner: owner,
                    quorum: quorum,
                    members: members,
                    tiebreakerCoreCommittee: address(tiebreakerCoreCommittee)
                })
            );
        }

        tiebreakerCoreCommittee.addMembers(coreCommitteeMembers, dgDeployConfig.TIEBREAKER_CORE_QUORUM);

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
            tiebreakerCoreCommittee: tiebreakerCoreCommittee
        });
    }

    function deployResealCommittee(
        address adminExecutor,
        address dualGovernance,
        DeployConfig memory dgDeployConfig
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
        DeployConfig memory dgDeployConfig
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
}
