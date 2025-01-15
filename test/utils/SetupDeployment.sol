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

    //

    // ---
    // Emergency Protected Timelock Contracts
    // ---
    Executor internal _adminExecutor;
    EmergencyProtectedTimelock internal _timelock;
    TimelockedGovernance internal _timelockedGovernance;
    address internal _emergencyActivationCommittee;
    address internal _emergencyExecutionCommittee;
    // ---
    // Timelocked Governance Contracts
    // ---
    TimelockedGovernance internal _emergencyGovernance;
    TimelockedGovernance internal _temporaryEmergencyGovernance;
    address internal _temporaryEmergencyGovernanceProposer;

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
        _temporaryEmergencyGovernanceProposer = makeAddr("TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER");

        _dgDeployConfig.MIN_EXECUTION_DELAY = _dgDeployConfig.AFTER_SUBMIT_DELAY = _AFTER_SUBMIT_DELAY;
        _dgDeployConfig.MAX_AFTER_SUBMIT_DELAY = _MAX_AFTER_SUBMIT_DELAY;
        _dgDeployConfig.AFTER_SCHEDULE_DELAY = _AFTER_SCHEDULE_DELAY;
        _dgDeployConfig.MAX_AFTER_SCHEDULE_DELAY = _MAX_AFTER_SCHEDULE_DELAY;
        _dgDeployConfig.EMERGENCY_MODE_DURATION = _EMERGENCY_MODE_DURATION;
        _dgDeployConfig.MAX_EMERGENCY_MODE_DURATION = _MAX_EMERGENCY_MODE_DURATION;
        _dgDeployConfig.EMERGENCY_PROTECTION_DURATION = _EMERGENCY_PROTECTION_DURATION;
        _dgDeployConfig.MAX_EMERGENCY_PROTECTION_DURATION = _MAX_EMERGENCY_PROTECTION_DURATION;

        _dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE = _emergencyActivationCommittee;
        _dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE = _emergencyExecutionCommittee;

        _dgDeployConfig.tiebreakerConfig.quorum = TIEBREAKER_CORE_QUORUM;
        _dgDeployConfig.tiebreakerConfig.executionDelay = TIEBREAKER_EXECUTION_DELAY;
        _dgDeployConfig.tiebreakerConfig.influencers.members =
            _generateRandomAddresses(TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT);
        _dgDeployConfig.tiebreakerConfig.influencers.quorum = TIEBREAKER_SUB_COMMITTEE_QUORUM;
        _dgDeployConfig.tiebreakerConfig.nodeOperators.members =
            _generateRandomAddresses(TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT);
        _dgDeployConfig.tiebreakerConfig.nodeOperators.quorum = TIEBREAKER_SUB_COMMITTEE_QUORUM;
        _dgDeployConfig.tiebreakerConfig.protocols.members =
            _generateRandomAddresses(TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT);
        _dgDeployConfig.tiebreakerConfig.protocols.quorum = TIEBREAKER_SUB_COMMITTEE_QUORUM;

        _dgDeployConfig.RESEAL_COMMITTEE = _resealCommittee;

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
        _dgDeployConfig.TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER = _temporaryEmergencyGovernanceProposer;

        _dgDeployConfig.TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER = _temporaryEmergencyGovernanceProposer;

        _lidoAddresses.stETH = _lido.stETH;
        _lidoAddresses.wstETH = _lido.wstETH;
        _lidoAddresses.withdrawalQueue = _lido.withdrawalQueue;
        _lidoAddresses.voting = address(_lido.voting);
    }

    // ---
    // Whole Setup Deployments
    // ---

    function _deployTimelockedGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        _deployEmergencyProtectedTimelockContracts(isEmergencyProtectionEnabled, false);
        _timelockedGovernance =
            DGContractsDeployment.deployTimelockedGovernance({governance: address(_lido.voting), timelock: _timelock});
        DGContractsDeployment.finalizeEmergencyProtectedTimelockDeploy(
            _adminExecutor, _timelock, address(_timelockedGovernance)
        );
    }

    function _deployDualGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        _deployDualGovernanceSetup(isEmergencyProtectionEnabled, false);
    }

    function _deployDualGovernanceSetup(
        bool isEmergencyProtectionEnabled,
        bool useTemporaryEmergencyGovernance
    ) internal {
        _deployEmergencyProtectedTimelockContracts(isEmergencyProtectionEnabled, useTemporaryEmergencyGovernance);
        _resealManager = _deployResealManager(_timelock);
        _contracts.resealManager = _resealManager;
        _dualGovernanceConfigProvider = _deployDualGovernanceConfigProvider();
        _dualGovernance = _deployDualGovernance({
            timelock: _timelock,
            resealManager: _resealManager,
            configProvider: _dualGovernanceConfigProvider
        });
        _contracts.dualGovernance = _dualGovernance;

        _tiebreakerCoreCommittee = DGContractsDeployment.deployEmptyTiebreakerCoreCommittee({
            owner: address(this), // temporary set owner to deployer, to add sub committees manually
            dualGovernance: address(_dualGovernance),
            executionDelay: TIEBREAKER_EXECUTION_DELAY
        });
        _contracts.tiebreakerCoreCommittee = _tiebreakerCoreCommittee;

        (TiebreakerSubCommittee influencers, TiebreakerSubCommittee nodeOperators, TiebreakerSubCommittee protocols) =
        DGContractsDeployment.deployTiebreakerSubCommittees(
            address(_adminExecutor), _tiebreakerCoreCommittee, _dgDeployConfig
        );
        _contracts.tiebreakerSubCommitteeInfluencers = influencers;
        _contracts.tiebreakerSubCommitteeNodeOperators = nodeOperators;
        _contracts.tiebreakerSubCommitteeProtocols = protocols;

        _tiebreakerSubCommittees = new TiebreakerSubCommittee[](3);
        _tiebreakerSubCommittees[0] = influencers;
        _tiebreakerSubCommittees[1] = nodeOperators;
        _tiebreakerSubCommittees[2] = protocols;

        _tiebreakerCoreCommittee.transferOwnership(address(_adminExecutor));

        // ---
        // Finalize Setup
        // ---

        DGContractsDeployment.configureDualGovernance(_dgDeployConfig, _lidoAddresses, _contracts);
        DGContractsDeployment.finalizeEmergencyProtectedTimelockDeploy(
            _adminExecutor, _timelock, address(_dualGovernance)
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

    function _deployEmergencyProtectedTimelockContracts(
        bool isEmergencyProtectionEnabled,
        bool useTemporaryEmergencyGovernance
    ) internal {
        DeployedContracts memory memContracts =
            DGContractsDeployment.deployAdminExecutorAndTimelock(_dgDeployConfig, address(this));
        _adminExecutor = memContracts.adminExecutor;
        _timelock = EmergencyProtectedTimelock(address(memContracts.timelock));

        if (useTemporaryEmergencyGovernance == false) {
            _dgDeployConfig.TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER = address(0);
        }

        if (isEmergencyProtectionEnabled) {
            (_emergencyGovernance, _temporaryEmergencyGovernance) = DGContractsDeployment
                .deployEmergencyProtectedTimelockContracts(_lidoAddresses, _dgDeployConfig, memContracts);
        }
        _contracts.timelock = _timelock;
        _contracts.adminExecutor = _adminExecutor;
        _contracts.emergencyGovernance = _emergencyGovernance;
        _contracts.temporaryEmergencyGovernance = _temporaryEmergencyGovernance;
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
