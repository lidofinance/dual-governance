// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

// ---
// Types
// ---

import {PercentsD16} from "contracts/types/PercentD16.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";

// ---
// Interfaces
// ---
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IResealManager} from "contracts/interfaces/IResealManager.sol";

// ---
// Contracts
// ---
import {TargetMock} from "./target-mock.sol";

import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";

import {ResealManager} from "contracts/ResealManager.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {
    IDualGovernanceConfigProvider,
    ImmutableDualGovernanceConfigProvider
} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
// ---
// Util Libraries
// ---

import {Random} from "./random.sol";
import {LidoUtils} from "./lido-utils.sol";
import {DeployConfig, LidoContracts, TiebreakerSubCommitteeDeployConfig} from "../../scripts/deploy/config/Config.sol";
import {DeployedContracts} from "../../scripts/deploy/DeployedContractsSet.sol";
import {DGContractsDeployment} from "../../scripts/deploy/ContractsDeployment.sol";

// ---
// Lido Addresses
// ---

abstract contract SetupDeployment is Test {
    using Random for Random.Context;
    // ---
    // Helpers
    // ---

    DeployConfig internal _dgDeployConfig;
    LidoContracts internal _lidoAddresses;
    DeployedContracts internal _contracts;

    Random.Context internal _random;
    LidoUtils.Context internal _lido;

    // ---
    // Emergency Protected Timelock Deployment Parameters
    // ---

    // TODO: consider to use non zero value for the more realistic setup in the tests
    Duration internal immutable _MIN_EXECUTION_DELAY = Durations.ZERO;
    Duration internal immutable _AFTER_SUBMIT_DELAY = Durations.from(3 days);
    Duration internal immutable _MAX_AFTER_SUBMIT_DELAY = Durations.from(45 days);

    Duration internal immutable _AFTER_SCHEDULE_DELAY = Durations.from(3 days);
    Duration internal immutable _MAX_AFTER_SCHEDULE_DELAY = Durations.from(45 days);

    Duration internal immutable _EMERGENCY_MODE_DURATION = Durations.from(180 days);
    Duration internal immutable _MAX_EMERGENCY_MODE_DURATION = Durations.from(365 days);

    Duration internal immutable _EMERGENCY_PROTECTION_DURATION = Durations.from(90 days);
    Duration internal immutable _MAX_EMERGENCY_PROTECTION_DURATION = Durations.from(365 days);

    uint256 internal immutable _EMERGENCY_ACTIVATION_COMMITTEE_QUORUM = 3;
    uint256 internal immutable _EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS_COUNT = 5;

    uint256 internal immutable _EMERGENCY_EXECUTION_COMMITTEE_QUORUM = 5;
    uint256 internal immutable _EMERGENCY_EXECUTION_COMMITTEE_MEMBERS_COUNT = 8;

    // ---
    // Dual Governance Deployment Parameters
    // ---
    uint256 internal immutable TIEBREAKER_CORE_QUORUM = 2;
    Duration internal immutable TIEBREAKER_EXECUTION_DELAY = Durations.from(30 days);

    uint256 internal immutable TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT = 5;
    uint256 internal immutable TIEBREAKER_SUB_COMMITTEE_QUORUM = 5;

    Duration internal immutable MIN_TIEBREAKER_ACTIVATION_TIMEOUT = Durations.from(90 days);
    Duration internal immutable TIEBREAKER_ACTIVATION_TIMEOUT = Durations.from(365 days);
    Duration internal immutable MAX_TIEBREAKER_ACTIVATION_TIMEOUT = Durations.from(730 days);
    uint256 internal immutable MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = 255;

    uint256 internal FORK_BLOCK_NUMBER = 20218312;
    uint256 internal FORK_BLOCK_TIMESTAMP = 1719917015;

    // ---
    // Dual Governance Contracts
    // ---
    ImmutableDualGovernanceConfigProvider internal _dualGovernanceConfigProvider;

    TargetMock internal _targetMock;

    // ---
    // Constructor
    // ---

    constructor(LidoUtils.Context memory lido, Random.Context memory random) {
        _lido = lido;
        _random = random;
        _targetMock = new TargetMock();

        _dgDeployConfig.ADMIN_PROPOSER = 0x2e59A20f205bB85a89C53f1936454680651E618e;
        _dgDeployConfig.EMERGENCY_GOVERNANCE_PROPOSER = 0x2e59A20f205bB85a89C53f1936454680651E618e;
        _dgDeployConfig.PROPOSAL_CANCELER = makeAddr("PROPOSAL_CANCELER");
        _dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE = makeAddr("EMERGENCY_ACTIVATION_COMMITTEE");
        _dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE = makeAddr("EMERGENCY_EXECUTION_COMMITTEE");
        _dgDeployConfig.RESEAL_COMMITTEE = makeAddr("RESEAL_COMMITTEE");

        _dgDeployConfig.MIN_EXECUTION_DELAY = _dgDeployConfig.AFTER_SUBMIT_DELAY = _AFTER_SUBMIT_DELAY;
        _dgDeployConfig.MAX_AFTER_SUBMIT_DELAY = _MAX_AFTER_SUBMIT_DELAY;
        _dgDeployConfig.AFTER_SCHEDULE_DELAY = _AFTER_SCHEDULE_DELAY;
        _dgDeployConfig.MAX_AFTER_SCHEDULE_DELAY = _MAX_AFTER_SCHEDULE_DELAY;
        _dgDeployConfig.EMERGENCY_MODE_DURATION = _EMERGENCY_MODE_DURATION;
        _dgDeployConfig.MAX_EMERGENCY_MODE_DURATION = _MAX_EMERGENCY_MODE_DURATION;
        _dgDeployConfig.EMERGENCY_PROTECTION_END_DATE =
            _EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.from(FORK_BLOCK_TIMESTAMP));
        _dgDeployConfig.MAX_EMERGENCY_PROTECTION_DURATION = _MAX_EMERGENCY_PROTECTION_DURATION;

        _dgDeployConfig.tiebreakerConfig.quorum = TIEBREAKER_CORE_QUORUM;
        _dgDeployConfig.tiebreakerConfig.executionDelay = TIEBREAKER_EXECUTION_DELAY;

        _dgDeployConfig.tiebreakerConfig.subCommitteeConfigs.push(
            TiebreakerSubCommitteeDeployConfig({
                members: _generateRandomAddresses(TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT),
                quorum: TIEBREAKER_SUB_COMMITTEE_QUORUM
            })
        );
        _dgDeployConfig.tiebreakerConfig.subCommitteeConfigs.push(
            TiebreakerSubCommitteeDeployConfig({
                members: _generateRandomAddresses(TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT),
                quorum: TIEBREAKER_SUB_COMMITTEE_QUORUM
            })
        );
        _dgDeployConfig.tiebreakerConfig.subCommitteeConfigs.push(
            TiebreakerSubCommitteeDeployConfig({
                members: _generateRandomAddresses(TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT),
                quorum: TIEBREAKER_SUB_COMMITTEE_QUORUM
            })
        );

        _dgDeployConfig.MIN_WITHDRAWALS_BATCH_SIZE = 4;
        _dgDeployConfig.tiebreakerConfig.minActivationTimeout = MIN_TIEBREAKER_ACTIVATION_TIMEOUT;
        _dgDeployConfig.tiebreakerConfig.activationTimeout = TIEBREAKER_ACTIVATION_TIMEOUT;
        _dgDeployConfig.tiebreakerConfig.maxActivationTimeout = MAX_TIEBREAKER_ACTIVATION_TIMEOUT;
        _dgDeployConfig.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT;
        _dgDeployConfig.FIRST_SEAL_RAGE_QUIT_SUPPORT = PercentsD16.fromBasisPoints(3_00); // 3%
        _dgDeployConfig.SECOND_SEAL_RAGE_QUIT_SUPPORT = PercentsD16.fromBasisPoints(15_00); // 15%
        _dgDeployConfig.MIN_ASSETS_LOCK_DURATION = Durations.from(5 hours);
        _dgDeployConfig.VETO_SIGNALLING_MIN_DURATION = Durations.from(3 days);
        _dgDeployConfig.VETO_SIGNALLING_MAX_DURATION = Durations.from(30 days);
        _dgDeployConfig.VETO_SIGNALLING_MIN_ACTIVE_DURATION = Durations.from(5 hours);
        _dgDeployConfig.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = Durations.from(5 days);
        _dgDeployConfig.VETO_COOLDOWN_DURATION = Durations.from(4 days);
        _dgDeployConfig.RAGE_QUIT_EXTENSION_PERIOD_DURATION = Durations.from(7 days);
        _dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY = Durations.from(30 days);
        _dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY = Durations.from(180 days);
        _dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH = Durations.from(15 days);

        _lidoAddresses.stETH = _lido.stETH;
        _lidoAddresses.wstETH = _lido.wstETH;
        _lidoAddresses.withdrawalQueue = _lido.withdrawalQueue;
    }

    // ---
    // Whole Setup Deployments
    // ---

    function _deployTimelockedGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        _deployEmergencyProtectedTimelockContracts(isEmergencyProtectionEnabled);
        _contracts.emergencyGovernance = DGContractsDeployment.deployTimelockedGovernance({
            governance: address(_dgDeployConfig.EMERGENCY_GOVERNANCE_PROPOSER),
            timelock: _contracts.timelock
        });
        DGContractsDeployment.finalizeEmergencyProtectedTimelockDeploy(
            _contracts.adminExecutor, _contracts.timelock, address(_contracts.emergencyGovernance)
        );
    }

    function _deployDualGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        _deployEmergencyProtectedTimelockContracts(isEmergencyProtectionEnabled);
        _contracts.resealManager = _deployResealManager(_contracts.timelock);
        _dualGovernanceConfigProvider = _deployDualGovernanceConfigProvider();
        _contracts.dualGovernance = _deployDualGovernance({
            timelock: _contracts.timelock,
            resealManager: _contracts.resealManager,
            configProvider: _dualGovernanceConfigProvider
        });

        _contracts.tiebreakerCoreCommittee = DGContractsDeployment.deployEmptyTiebreakerCoreCommittee({
            owner: address(this), // temporary set owner to deployer, to add sub committees manually
            dualGovernance: address(_contracts.dualGovernance),
            executionDelay: TIEBREAKER_EXECUTION_DELAY
        });
        _contracts.tiebreakerCoreCommittee = _contracts.tiebreakerCoreCommittee;

        _contracts.tiebreakerSubCommittees = DGContractsDeployment.setupTiebreakerSubCommittees(
            address(_contracts.adminExecutor), _contracts.tiebreakerCoreCommittee, _dgDeployConfig
        );

        _contracts.tiebreakerCoreCommittee.transferOwnership(address(_contracts.adminExecutor));

        // ---
        // Finalize Setup
        // ---

        DGContractsDeployment.configureDualGovernance(_dgDeployConfig, _contracts);
        DGContractsDeployment.finalizeEmergencyProtectedTimelockDeploy(
            _contracts.adminExecutor, _contracts.timelock, address(_contracts.dualGovernance)
        );

        // ---
        // Grant Reseal Manager Roles
        // ---
        vm.startPrank(address(_lido.agent));
        _lido.withdrawalQueue.grantRole(
            0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d, address(_contracts.resealManager)
        );
        _lido.withdrawalQueue.grantRole(
            0x2fc10cc8ae19568712f7a176fb4978616a610650813c9d05326c34abb62749c7, address(_contracts.resealManager)
        );
        vm.stopPrank();
    }

    // ---
    // Emergency Protected Timelock Deployment
    // ---

    function _deployEmergencyProtectedTimelockContracts(bool isEmergencyProtectionEnabled) internal {
        DeployedContracts memory memContracts =
            DGContractsDeployment.deployAdminExecutorAndTimelock(_dgDeployConfig, address(this));
        _contracts.adminExecutor = memContracts.adminExecutor;
        _contracts.timelock = EmergencyProtectedTimelock(address(memContracts.timelock));

        if (isEmergencyProtectionEnabled) {
            _contracts.emergencyGovernance =
                DGContractsDeployment.setupEmergencyGovernance(_dgDeployConfig, memContracts);
        }
    }

    function _deployEmergencyProtectedTimelock(Executor adminExecutor) internal returns (EmergencyProtectedTimelock) {
        return EmergencyProtectedTimelock(
            address(DGContractsDeployment.deployEmergencyProtectedTimelock(address(adminExecutor), _dgDeployConfig))
        );
    }

    // ---
    // Dual Governance Deployment
    // ---

    function _deployDualGovernanceConfigProvider() internal returns (ImmutableDualGovernanceConfigProvider) {
        return DGContractsDeployment.deployDualGovernanceConfigProvider(_dgDeployConfig);
    }

    function _deployTimelockedGovernance(
        address governance,
        ITimelock timelock
    ) internal returns (TimelockedGovernance) {
        return new TimelockedGovernance(governance, timelock);
    }

    // ---
    // Dual Governance Deployment
    // ---

    function _deployResealManager(ITimelock timelock) internal returns (ResealManager) {
        return DGContractsDeployment.deployResealManager(timelock);
    }

    function _deployDualGovernance(
        ITimelock timelock,
        IResealManager resealManager,
        IDualGovernanceConfigProvider configProvider
    ) internal returns (DualGovernance) {
        return DGContractsDeployment.deployDualGovernance(
            configProvider, timelock, resealManager, _dgDeployConfig, _lidoAddresses
        );
    }

    // ---
    // Helper methods
    // ---

    function _generateRandomAddresses(uint256 count) internal returns (address[] memory addresses) {
        addresses = new address[](count);
        for (uint256 i = 0; i < count; ++i) {
            addresses[i] = _random.nextAddress();
        }
    }
}
