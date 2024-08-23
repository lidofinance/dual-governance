// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// ---
// Contracts
// ---
import {Timestamps} from "contracts/types/Timestamp.sol";

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

import {DGDeployConfig, ConfigValues, LidoAddresses} from "./Config.s.sol";

contract DeployDG is Script {
    LidoAddresses internal lidoAddresses;
    ConfigValues private dgDeployConfig;

    // Emergency Protected Timelock Contracts
    // ---
    Executor internal adminExecutor;
    EmergencyProtectedTimelock internal timelock;
    TimelockedGovernance internal emergencyGovernance;
    EmergencyActivationCommittee internal emergencyActivationCommittee;
    EmergencyExecutionCommittee internal emergencyExecutionCommittee;

    // ---
    // Dual Governance Contracts
    // ---
    ResealManager internal resealManager;
    DualGovernance internal dualGovernance;
    ImmutableDualGovernanceConfigProvider internal dualGovernanceConfigProvider;

    ResealCommittee internal resealCommittee;
    TiebreakerCore internal tiebreakerCoreCommittee;
    TiebreakerSubCommittee[] internal tiebreakerSubCommittees;

    address internal deployer;

    function run() external {
        DGDeployConfig configProvider = new DGDeployConfig();
        dgDeployConfig = configProvider.loadAndValidate();

        // TODO: check chain id?

        lidoAddresses = configProvider.lidoAddresses(dgDeployConfig);
        deployer = vm.addr(dgDeployConfig.DEPLOYER_PRIVATE_KEY);
        vm.startBroadcast(dgDeployConfig.DEPLOYER_PRIVATE_KEY);

        deployDualGovernanceSetup();

        vm.stopBroadcast();

        console.log("DG deployed successfully");
        console.log("DualGovernance address", address(dualGovernance));
        console.log("ResealManager address", address(resealManager));
        console.log("TiebreakerCoreCommittee address", address(tiebreakerCoreCommittee));
        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            console.log("TiebreakerSubCommittee #", i, "address", address(tiebreakerSubCommittees[i]));
        }
        console.log("AdminExecutor address", address(adminExecutor));
        console.log("EmergencyProtectedTimelock address", address(timelock));
        console.log("EmergencyGovernance address", address(emergencyGovernance));
        console.log("EmergencyActivationCommittee address", address(emergencyActivationCommittee));
        console.log("EmergencyExecutionCommittee address", address(emergencyExecutionCommittee));
        console.log("ResealCommittee address", address(resealCommittee));
    }

    function deployDualGovernanceSetup() internal {
        deployEmergencyProtectedTimelockContracts();
        resealManager = deployResealManager();
        dualGovernanceConfigProvider = deployDualGovernanceConfigProvider();
        dualGovernance = deployDualGovernance({configProvider: dualGovernanceConfigProvider});

        tiebreakerCoreCommittee = deployEmptyTiebreakerCoreCommittee({
            owner: deployer, // temporary set owner to deployer, to add sub committees manually
            timelockSeconds: dgDeployConfig.TIEBREAKER_EXECUTION_DELAY.toSeconds()
        });

        deployTiebreakerSubCommittees();

        tiebreakerCoreCommittee.transferOwnership(address(adminExecutor));

        resealCommittee = deployResealCommittee();

        // ---
        // Finalize Setup
        // ---
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.registerProposer, (address(lidoAddresses.voting), address(adminExecutor)))
        );
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerActivationTimeout, dgDeployConfig.TIEBREAKER_ACTIVATION_TIMEOUT)
        );
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerCommittee, address(tiebreakerCoreCommittee))
        );
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(
                dualGovernance.addTiebreakerSealableWithdrawalBlocker, address(lidoAddresses.withdrawalQueue)
            )
        );
        adminExecutor.execute(
            address(dualGovernance), 0, abi.encodeCall(dualGovernance.setResealCommittee, address(resealCommittee))
        );

        finalizeEmergencyProtectedTimelockDeploy();

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

    function deployEmergencyProtectedTimelockContracts() internal {
        adminExecutor = deployExecutor(deployer);
        timelock = deployEmergencyProtectedTimelock();

        emergencyActivationCommittee = deployEmergencyActivationCommittee({
            quorum: dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM,
            members: dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS,
            owner: address(adminExecutor)
        });

        emergencyExecutionCommittee = deployEmergencyExecutionCommittee({
            quorum: dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_QUORUM,
            members: dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS,
            owner: address(adminExecutor)
        });
        emergencyGovernance = deployTimelockedGovernance({governance: address(lidoAddresses.voting)});

        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setEmergencyProtectionActivationCommittee, (address(emergencyActivationCommittee)))
        );
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setEmergencyProtectionExecutionCommittee, (address(emergencyExecutionCommittee)))
        );
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
            address(timelock), 0, abi.encodeCall(timelock.setEmergencyGovernance, (address(emergencyGovernance)))
        );
    }

    function deployExecutor(address owner) internal returns (Executor) {
        return new Executor(owner);
    }

    function deployEmergencyProtectedTimelock() internal returns (EmergencyProtectedTimelock) {
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
        address[] memory members
    ) internal returns (EmergencyActivationCommittee) {
        return new EmergencyActivationCommittee(owner, members, quorum, address(timelock));
    }

    function deployEmergencyExecutionCommittee(
        address owner,
        uint256 quorum,
        address[] memory members
    ) internal returns (EmergencyExecutionCommittee) {
        return new EmergencyExecutionCommittee(owner, members, quorum, address(timelock));
    }

    function deployTimelockedGovernance(address governance) internal returns (TimelockedGovernance) {
        return new TimelockedGovernance(governance, timelock);
    }

    function deployResealManager() internal returns (ResealManager) {
        return new ResealManager(timelock);
    }

    function deployDualGovernanceConfigProvider() internal returns (ImmutableDualGovernanceConfigProvider) {
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

    function deployDualGovernance(IDualGovernanceConfigProvider configProvider) internal returns (DualGovernance) {
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
        uint256 timelockSeconds
    ) internal returns (TiebreakerCore) {
        return new TiebreakerCore({owner: owner, dualGovernance: address(dualGovernance), timelock: timelockSeconds});
    }

    function deployTiebreakerSubCommittees() internal {
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

            tiebreakerSubCommittees.push(
                deployTiebreakerSubCommittee({owner: address(adminExecutor), quorum: quorum, members: members})
            );
            coreCommitteeMembers[i] = address(tiebreakerSubCommittees[i]);
        }

        tiebreakerCoreCommittee.addMembers(coreCommitteeMembers, coreCommitteeMembers.length);
    }

    function deployTiebreakerSubCommittee(
        address owner,
        uint256 quorum,
        address[] memory members
    ) internal returns (TiebreakerSubCommittee) {
        return new TiebreakerSubCommittee({
            owner: owner,
            executionQuorum: quorum,
            committeeMembers: members,
            tiebreakerCore: address(tiebreakerCoreCommittee)
        });
    }

    function deployResealCommittee() internal returns (ResealCommittee) {
        uint256 quorum = dgDeployConfig.RESEAL_COMMITTEE_QUORUM;
        address[] memory committeeMembers = dgDeployConfig.RESEAL_COMMITTEE_MEMBERS;

        // TODO: Do we need to use timelock here?
        return new ResealCommittee(address(adminExecutor), committeeMembers, quorum, address(dualGovernance), 0);
    }

    function finalizeEmergencyProtectedTimelockDeploy() internal {
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setupDelays, (dgDeployConfig.AFTER_SUBMIT_DELAY, dgDeployConfig.AFTER_SCHEDULE_DELAY)
            )
        );
        adminExecutor.execute(address(timelock), 0, abi.encodeCall(timelock.setGovernance, (address(dualGovernance))));
        adminExecutor.transferOwnership(address(timelock));
    }
}
