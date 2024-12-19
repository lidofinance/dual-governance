// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

// ---
// Types
// ---

import {PercentsD16} from "contracts/types/PercentD16.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";

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
import {DeployConfig, LidoContracts} from "../../scripts/deploy/Config.sol";
import {DeployedContracts, DGContractsDeployment} from "../../scripts/deploy/ContractsDeployment.sol";

// ---
// Lido Addresses
// ---

abstract contract SetupDeployment is Test {
    using Random for Random.Context;
    // ---
    // Helpers
    // ---

    DeployConfig internal dgDeployConfig;
    LidoContracts internal lidoAddresses;
    DeployedContracts internal contracts;

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
    uint256 internal immutable TIEBREAKER_CORE_QUORUM = 1;
    Duration internal immutable TIEBREAKER_EXECUTION_DELAY = Durations.from(30 days);

    uint256 internal immutable TIEBREAKER_SUB_COMMITTEES_COUNT = 2;
    uint256 internal immutable TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT = 5;
    uint256 internal immutable TIEBREAKER_SUB_COMMITTEE_QUORUM = 5;

    Duration internal immutable MIN_TIEBREAKER_ACTIVATION_TIMEOUT = Durations.from(90 days);
    Duration internal immutable TIEBREAKER_ACTIVATION_TIMEOUT = Durations.from(365 days);
    Duration internal immutable MAX_TIEBREAKER_ACTIVATION_TIMEOUT = Durations.from(730 days);
    uint256 internal immutable MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = 255;

    //

    // ---
    // Emergency Protected Timelock Contracts
    // ---
    Executor internal _adminExecutor;
    EmergencyProtectedTimelock internal _timelock;
    TimelockedGovernance internal _emergencyGovernance;
    address internal _emergencyActivationCommittee;
    address internal _emergencyExecutionCommittee;

    // ---
    // Dual Governance Contracts
    // ---
    ResealManager internal _resealManager;
    DualGovernance internal _dualGovernance;
    ImmutableDualGovernanceConfigProvider internal _dualGovernanceConfigProvider;

    address internal _resealCommittee;
    TiebreakerCoreCommittee internal _tiebreakerCoreCommittee;
    TiebreakerSubCommittee[] internal _tiebreakerSubCommittees;

    // ---
    // Timelocked Governance Contracts
    // ---
    TimelockedGovernance internal _timelockedGovernance;

    // ---
    // Target Mock Helper Contract
    // ---

    TargetMock internal _targetMock;

    // ---
    // Constructor
    // ---

    constructor(LidoUtils.Context memory lido, Random.Context memory random) {
        _lido = lido;
        _random = random;
        _targetMock = new TargetMock();

        _emergencyActivationCommittee = makeAddr("EMERGENCY_ACTIVATION_COMMITTEE");
        _emergencyExecutionCommittee = makeAddr("EMERGENCY_EXECUTION_COMMITTEE");
        _resealCommittee = makeAddr("RESEAL_COMMITTEE");

        dgDeployConfig.MIN_EXECUTION_DELAY = dgDeployConfig.AFTER_SUBMIT_DELAY = _AFTER_SUBMIT_DELAY;
        dgDeployConfig.MAX_AFTER_SUBMIT_DELAY = _MAX_AFTER_SUBMIT_DELAY;
        dgDeployConfig.AFTER_SCHEDULE_DELAY = _AFTER_SCHEDULE_DELAY;
        dgDeployConfig.MAX_AFTER_SCHEDULE_DELAY = _MAX_AFTER_SCHEDULE_DELAY;
        dgDeployConfig.EMERGENCY_MODE_DURATION = _EMERGENCY_MODE_DURATION;
        dgDeployConfig.MAX_EMERGENCY_MODE_DURATION = _MAX_EMERGENCY_MODE_DURATION;
        dgDeployConfig.EMERGENCY_PROTECTION_DURATION = _EMERGENCY_PROTECTION_DURATION;
        dgDeployConfig.MAX_EMERGENCY_PROTECTION_DURATION = _MAX_EMERGENCY_PROTECTION_DURATION;

        dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE = _emergencyActivationCommittee;
        dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE = _emergencyExecutionCommittee;

        dgDeployConfig.TIEBREAKER_CORE_QUORUM = TIEBREAKER_SUB_COMMITTEES_COUNT;
        dgDeployConfig.TIEBREAKER_EXECUTION_DELAY = TIEBREAKER_EXECUTION_DELAY;
        dgDeployConfig.TIEBREAKER_SUB_COMMITTEES_COUNT = TIEBREAKER_SUB_COMMITTEES_COUNT;
        dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS =
            _generateRandomAddresses(TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT);
        dgDeployConfig.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS =
            _generateRandomAddresses(TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT);
        dgDeployConfig.TIEBREAKER_SUB_COMMITTEES_QUORUMS =
            [TIEBREAKER_SUB_COMMITTEE_QUORUM, TIEBREAKER_SUB_COMMITTEE_QUORUM];

        dgDeployConfig.RESEAL_COMMITTEE = _resealCommittee;

        dgDeployConfig.MIN_WITHDRAWALS_BATCH_SIZE = 4;
        dgDeployConfig.MIN_TIEBREAKER_ACTIVATION_TIMEOUT = MIN_TIEBREAKER_ACTIVATION_TIMEOUT;
        dgDeployConfig.TIEBREAKER_ACTIVATION_TIMEOUT = TIEBREAKER_ACTIVATION_TIMEOUT;
        dgDeployConfig.MAX_TIEBREAKER_ACTIVATION_TIMEOUT = MAX_TIEBREAKER_ACTIVATION_TIMEOUT;
        dgDeployConfig.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT;
        dgDeployConfig.FIRST_SEAL_RAGE_QUIT_SUPPORT = PercentsD16.fromBasisPoints(3_00); // 3%
        dgDeployConfig.SECOND_SEAL_RAGE_QUIT_SUPPORT = PercentsD16.fromBasisPoints(15_00); // 15%
        dgDeployConfig.MIN_ASSETS_LOCK_DURATION = Durations.from(5 hours);
        dgDeployConfig.VETO_SIGNALLING_MIN_DURATION = Durations.from(3 days);
        dgDeployConfig.VETO_SIGNALLING_MAX_DURATION = Durations.from(30 days);
        dgDeployConfig.VETO_SIGNALLING_MIN_ACTIVE_DURATION = Durations.from(5 hours);
        dgDeployConfig.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = Durations.from(5 days);
        dgDeployConfig.VETO_COOLDOWN_DURATION = Durations.from(4 days);
        dgDeployConfig.RAGE_QUIT_EXTENSION_PERIOD_DURATION = Durations.from(7 days);
        dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY = Durations.from(30 days);
        dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY = Durations.from(180 days);
        dgDeployConfig.RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH = Durations.from(15 days);
        dgDeployConfig.TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER = address(_lido.voting);

        lidoAddresses.stETH = _lido.stETH;
        lidoAddresses.wstETH = _lido.wstETH;
        lidoAddresses.withdrawalQueue = _lido.withdrawalQueue;
        lidoAddresses.voting = address(_lido.voting);
    }

    // ---
    // Whole Setup Deployments
    // ---

    function _deployTimelockedGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        _deployEmergencyProtectedTimelockContracts(isEmergencyProtectionEnabled);
        _timelockedGovernance =
            DGContractsDeployment.deployTimelockedGovernance({governance: address(_lido.voting), timelock: _timelock});
        DGContractsDeployment.finalizeEmergencyProtectedTimelockDeploy(
            _adminExecutor, _timelock, address(_timelockedGovernance), dgDeployConfig
        );
    }

    function _deployDualGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        _deployEmergencyProtectedTimelockContracts(isEmergencyProtectionEnabled);
        _resealManager = _deployResealManager(_timelock);
        _dualGovernanceConfigProvider = _deployDualGovernanceConfigProvider();
        _dualGovernance = _deployDualGovernance({
            timelock: _timelock,
            resealManager: _resealManager,
            configProvider: _dualGovernanceConfigProvider
        });
        contracts.dualGovernance = _dualGovernance;

        _tiebreakerCoreCommittee = DGContractsDeployment.deployEmptyTiebreakerCoreCommittee({
            owner: address(this), // temporary set owner to deployer, to add sub committees manually
            dualGovernance: address(_dualGovernance),
            executionDelay: TIEBREAKER_EXECUTION_DELAY
        });
        contracts.tiebreakerCoreCommittee = _tiebreakerCoreCommittee;

        _tiebreakerSubCommittees = DGContractsDeployment.deployTiebreakerSubCommittees(
            address(_adminExecutor), _tiebreakerCoreCommittee, dgDeployConfig
        );

        _tiebreakerCoreCommittee.transferOwnership(address(_adminExecutor));

        // ---
        // Finalize Setup
        // ---

        DGContractsDeployment.configureDualGovernance(dgDeployConfig, lidoAddresses, contracts);
        DGContractsDeployment.finalizeEmergencyProtectedTimelockDeploy(
            _adminExecutor, _timelock, address(_dualGovernance), dgDeployConfig
        );

        // ---
        // Grant Reseal Manager Roles
        // ---
        vm.startPrank(address(_lido.agent));
        _lido.withdrawalQueue.grantRole(
            0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d, address(_resealManager)
        );
        _lido.withdrawalQueue.grantRole(
            0x2fc10cc8ae19568712f7a176fb4978616a610650813c9d05326c34abb62749c7, address(_resealManager)
        );
        vm.stopPrank();
    }

    // ---
    // Emergency Protected Timelock Deployment
    // ---

    function _deployEmergencyProtectedTimelockContracts(bool isEmergencyProtectionEnabled) internal {
        contracts = DGContractsDeployment.deployAdminExecutorAndTimelock(dgDeployConfig, address(this));
        _adminExecutor = contracts.adminExecutor;
        _timelock = contracts.timelock;

        if (isEmergencyProtectionEnabled) {
            DGContractsDeployment.deployEmergencyProtectedTimelockContracts(lidoAddresses, dgDeployConfig, contracts);
        }
    }

    function _deployEmergencyProtectedTimelock(Executor adminExecutor) internal returns (EmergencyProtectedTimelock) {
        return DGContractsDeployment.deployEmergencyProtectedTimelock(address(adminExecutor), dgDeployConfig);
    }

    // ---
    // Dual Governance Deployment
    // ---

    function _deployDualGovernanceConfigProvider() internal returns (ImmutableDualGovernanceConfigProvider) {
        return DGContractsDeployment.deployDualGovernanceConfigProvider(dgDeployConfig);
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
            configProvider, timelock, resealManager, dgDeployConfig, lidoAddresses
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
