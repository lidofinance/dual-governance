// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ---
// Contracts
// ---
import {Duration} from "contracts/types/Duration.sol";

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
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";

import {DeployedContracts} from "./DeployedContractsSet.sol";
import {DeployConfig, LidoContracts} from "./config/Config.sol";

library DGContractsDeployment {
    function deployDualGovernanceSetup(
        DeployConfig memory dgDeployConfig,
        LidoContracts memory lidoAddresses,
        address deployer
    ) internal returns (DeployedContracts memory contracts) {
        // ---
        // Deploy Admin Executor and Timelock
        // ---
        contracts = deployAdminExecutorAndTimelock(dgDeployConfig, deployer);

        // ---
        // Deploy Emergency Governance
        // ---

        setupEmergencyGovernance(dgDeployConfig, contracts);
        contracts.resealManager = deployResealManager(contracts.timelock);

        // ---
        // Deploy Dual Governance
        // ---

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

        // ---
        // Tiebreaker
        // ---

        contracts.tiebreakerCoreCommittee = deployEmptyTiebreakerCoreCommittee({
            owner: deployer, // temporary set owner to deployer, to add sub committees manually
            dualGovernance: address(dualGovernance),
            executionDelay: dgDeployConfig.tiebreakerConfig.executionDelay
        });

        contracts.tiebreakerSubCommittees = setupTiebreakerSubCommittees(
            address(contracts.adminExecutor), contracts.tiebreakerCoreCommittee, dgDeployConfig
        );

        contracts.tiebreakerCoreCommittee.transferOwnership(address(contracts.adminExecutor));

        // ---
        // Finalize Setup
        // ---
        configureDualGovernance(dgDeployConfig, contracts);

        finalizeEmergencyProtectedTimelockDeploy(contracts.adminExecutor, contracts.timelock, address(dualGovernance));
    }

    function deployAdminExecutorAndTimelock(
        DeployConfig memory dgDeployConfig,
        address deployer
    ) internal returns (DeployedContracts memory contracts) {
        Executor adminExecutor = deployExecutor({owner: deployer});
        IEmergencyProtectedTimelock timelock = deployEmergencyProtectedTimelock(address(adminExecutor), dgDeployConfig);

        contracts.adminExecutor = adminExecutor;
        contracts.timelock = timelock;
    }

    function setupEmergencyGovernance(
        DeployConfig memory dgDeployConfig,
        DeployedContracts memory contracts
    ) internal returns (TimelockedGovernance) {
        Executor adminExecutor = contracts.adminExecutor;
        IEmergencyProtectedTimelock timelock = contracts.timelock;

        contracts.emergencyGovernance =
            deployTimelockedGovernance({governance: dgDeployConfig.EMERGENCY_GOVERNANCE_PROPOSER, timelock: timelock});

        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setEmergencyGovernance, (address(contracts.emergencyGovernance)))
        );

        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setEmergencyProtectionActivationCommittee, (dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE)
            )
        );
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setEmergencyProtectionExecutionCommittee, (dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE)
            )
        );
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setEmergencyProtectionEndDate, dgDeployConfig.EMERGENCY_PROTECTION_END_DATE)
        );
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setEmergencyModeDuration, (dgDeployConfig.EMERGENCY_MODE_DURATION))
        );

        return contracts.emergencyGovernance;
    }

    function deployExecutor(address owner) internal returns (Executor) {
        return new Executor(owner);
    }

    function deployEmergencyProtectedTimelock(
        address adminExecutor,
        DeployConfig memory dgDeployConfig
    ) internal returns (IEmergencyProtectedTimelock) {
        return IEmergencyProtectedTimelock(
            new EmergencyProtectedTimelock({
                adminExecutor: address(adminExecutor),
                sanityCheckParams: EmergencyProtectedTimelock.SanityCheckParams({
                    minExecutionDelay: dgDeployConfig.MIN_EXECUTION_DELAY,
                    maxAfterSubmitDelay: dgDeployConfig.MAX_AFTER_SUBMIT_DELAY,
                    maxAfterScheduleDelay: dgDeployConfig.MAX_AFTER_SCHEDULE_DELAY,
                    maxEmergencyModeDuration: dgDeployConfig.MAX_EMERGENCY_MODE_DURATION,
                    maxEmergencyProtectionDuration: dgDeployConfig.MAX_EMERGENCY_PROTECTION_DURATION
                }),
                afterSubmitDelay: dgDeployConfig.AFTER_SUBMIT_DELAY,
                afterScheduleDelay: dgDeployConfig.AFTER_SCHEDULE_DELAY
            })
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
        ITimelock timelock,
        IResealManager resealManager,
        DeployConfig memory dgDeployConfig,
        LidoContracts memory lidoAddresses
    ) internal returns (DualGovernance) {
        return new DualGovernance({
            components: DualGovernance.DualGovernanceComponents({
                timelock: timelock,
                resealManager: resealManager,
                configProvider: configProvider
            }),
            signallingTokens: DualGovernance.SignallingTokens({
                stETH: lidoAddresses.stETH,
                wstETH: lidoAddresses.wstETH,
                withdrawalQueue: lidoAddresses.withdrawalQueue
            }),
            sanityCheckParams: DualGovernance.SanityCheckParams({
                minWithdrawalsBatchSize: dgDeployConfig.MIN_WITHDRAWALS_BATCH_SIZE,
                minTiebreakerActivationTimeout: dgDeployConfig.tiebreakerConfig.minActivationTimeout,
                maxTiebreakerActivationTimeout: dgDeployConfig.tiebreakerConfig.maxActivationTimeout,
                maxSealableWithdrawalBlockersCount: dgDeployConfig.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT,
                maxMinAssetsLockDuration: dgDeployConfig.MAX_MIN_ASSETS_LOCK_DURATION
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

    function setupTiebreakerSubCommittees(
        address owner,
        TiebreakerCoreCommittee tiebreakerCoreCommittee,
        DeployConfig memory dgDeployConfig
    ) internal returns (TiebreakerSubCommittee[] memory tiebreakerSubCommittees) {
        tiebreakerSubCommittees =
            new TiebreakerSubCommittee[](dgDeployConfig.tiebreakerConfig.subCommitteeConfigs.length);

        for (uint256 i = 0; i < dgDeployConfig.tiebreakerConfig.subCommitteeConfigs.length; ++i) {
            TiebreakerSubCommittee tiebreakerSubCommittee = new TiebreakerSubCommittee({
                owner: owner,
                committeeMembers: dgDeployConfig.tiebreakerConfig.subCommitteeConfigs[i].members,
                executionQuorum: dgDeployConfig.tiebreakerConfig.subCommitteeConfigs[i].quorum,
                tiebreakerCoreCommittee: address(tiebreakerCoreCommittee)
            });
            tiebreakerSubCommittees[i] = tiebreakerSubCommittee;
        }

        address[] memory tiebreakerSubCommitteesAddresses = new address[](tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < tiebreakerSubCommittees.length; i++) {
            tiebreakerSubCommitteesAddresses[i] = address(tiebreakerSubCommittees[i]);
        }

        tiebreakerCoreCommittee.addMembers(tiebreakerSubCommitteesAddresses, dgDeployConfig.tiebreakerConfig.quorum);
    }

    function configureDualGovernance(DeployConfig memory dgDeployConfig, DeployedContracts memory contracts) internal {
        contracts.adminExecutor.execute(
            address(contracts.dualGovernance),
            0,
            abi.encodeCall(
                contracts.dualGovernance.registerProposer,
                (dgDeployConfig.ADMIN_PROPOSER, address(contracts.adminExecutor))
            )
        );
        contracts.adminExecutor.execute(
            address(contracts.dualGovernance),
            0,
            abi.encodeCall(contracts.dualGovernance.setProposalsCanceller, dgDeployConfig.PROPOSAL_CANCELER)
        );
        contracts.adminExecutor.execute(
            address(contracts.dualGovernance),
            0,
            abi.encodeCall(
                contracts.dualGovernance.setTiebreakerActivationTimeout,
                dgDeployConfig.tiebreakerConfig.activationTimeout
            )
        );
        contracts.adminExecutor.execute(
            address(contracts.dualGovernance),
            0,
            abi.encodeCall(contracts.dualGovernance.setTiebreakerCommittee, address(contracts.tiebreakerCoreCommittee))
        );

        for (uint256 i = 0; i < dgDeployConfig.tiebreakerConfig.sealableWithdrawalBlockers.length; ++i) {
            contracts.adminExecutor.execute(
                address(contracts.dualGovernance),
                0,
                abi.encodeCall(
                    contracts.dualGovernance.addTiebreakerSealableWithdrawalBlocker,
                    dgDeployConfig.tiebreakerConfig.sealableWithdrawalBlockers[i]
                )
            );
        }
        contracts.adminExecutor.execute(
            address(contracts.dualGovernance),
            0,
            abi.encodeCall(contracts.dualGovernance.setResealCommittee, dgDeployConfig.RESEAL_COMMITTEE)
        );
    }

    function finalizeEmergencyProtectedTimelockDeploy(
        Executor adminExecutor,
        IEmergencyProtectedTimelock timelock,
        address dualGovernance
    ) internal {
        adminExecutor.execute(address(timelock), 0, abi.encodeCall(timelock.setGovernance, (dualGovernance)));
        adminExecutor.transferOwnership(address(timelock));
    }
}
