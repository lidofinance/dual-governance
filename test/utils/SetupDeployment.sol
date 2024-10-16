// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

// ---
// Types
// ---

import {PercentsD16} from "contracts/types/PercentD16.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";

// ---
// Interfaces
// ---
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IGovernance} from "contracts/interfaces/IGovernance.sol";
import {IResealManager} from "contracts/interfaces/IResealManager.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";

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
    DualGovernanceConfig,
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

// ---
// Lido Addresses
// ---

abstract contract SetupDeployment is Test {
    using Random for Random.Context;
    // ---
    // Helpers
    // ---

    Random.Context internal _random;
    LidoUtils.Context internal _lido;

    // ---
    // Emergency Protected Timelock Deployment Parameters
    // ---

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
    address internal _emergencyActivationCommittee = makeAddr("EMERGENCY_ACTIVATION_COMMITTEE");
    address internal _emergencyExecutionCommittee = makeAddr("EMERGENCY_EXECUTION_COMMITTEE");

    // ---
    // Dual Governance Contracts
    // ---
    ResealManager internal _resealManager;
    DualGovernance internal _dualGovernance;
    ImmutableDualGovernanceConfigProvider internal _dualGovernanceConfigProvider;

    address internal _resealCommittee = makeAddr("RESEAL_COMMITTEE");
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
    }

    // ---
    // Whole Setup Deployments
    // ---

    function _deployTimelockedGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        _deployEmergencyProtectedTimelockContracts(isEmergencyProtectionEnabled);
        _timelockedGovernance = _deployTimelockedGovernance({governance: address(_lido.voting), timelock: _timelock});
        _finalizeEmergencyProtectedTimelockDeploy(_timelockedGovernance);
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

        _tiebreakerCoreCommittee = _deployEmptyTiebreakerCoreCommittee({
            owner: address(this), // temporary set owner to deployer, to add sub committees manually
            dualGovernance: _dualGovernance,
            timelock: TIEBREAKER_EXECUTION_DELAY
        });
        address[] memory coreCommitteeMembers = new address[](TIEBREAKER_SUB_COMMITTEES_COUNT);

        for (uint256 i = 0; i < TIEBREAKER_SUB_COMMITTEES_COUNT; ++i) {
            address[] memory members = _generateRandomAddresses(TIEBREAKER_SUB_COMMITTEE_MEMBERS_COUNT);
            _tiebreakerSubCommittees.push(
                _deployTiebreakerSubCommittee({
                    owner: address(_adminExecutor),
                    quorum: TIEBREAKER_SUB_COMMITTEE_QUORUM,
                    members: members,
                    tiebreakerCore: _tiebreakerCoreCommittee
                })
            );
            coreCommitteeMembers[i] = address(_tiebreakerSubCommittees[i]);
        }

        _tiebreakerCoreCommittee.addMembers(coreCommitteeMembers, coreCommitteeMembers.length);

        _tiebreakerCoreCommittee.transferOwnership(address(_adminExecutor));

        // ---
        // Finalize Setup
        // ---
        _adminExecutor.execute(
            address(_dualGovernance),
            0,
            abi.encodeCall(_dualGovernance.registerProposer, (address(_lido.voting), address(_adminExecutor)))
        );
        _adminExecutor.execute(
            address(_dualGovernance),
            0,
            abi.encodeCall(_dualGovernance.setTiebreakerActivationTimeout, TIEBREAKER_ACTIVATION_TIMEOUT)
        );
        _adminExecutor.execute(
            address(_dualGovernance),
            0,
            abi.encodeCall(_dualGovernance.setTiebreakerCommittee, address(_tiebreakerCoreCommittee))
        );
        _adminExecutor.execute(
            address(_dualGovernance),
            0,
            abi.encodeCall(_dualGovernance.addTiebreakerSealableWithdrawalBlocker, address(_lido.withdrawalQueue))
        );
        _adminExecutor.execute(
            address(_dualGovernance), 0, abi.encodeCall(_dualGovernance.setResealCommittee, address(_resealCommittee))
        );

        _finalizeEmergencyProtectedTimelockDeploy(_dualGovernance);

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
        _adminExecutor = _deployExecutor(address(this));
        _timelock = _deployEmergencyProtectedTimelock(_adminExecutor);

        if (isEmergencyProtectionEnabled) {
            _emergencyGovernance = _deployTimelockedGovernance({governance: address(_lido.voting), timelock: _timelock});

            _adminExecutor.execute(
                address(_timelock),
                0,
                abi.encodeCall(
                    _timelock.setEmergencyProtectionActivationCommittee, (address(_emergencyActivationCommittee))
                )
            );
            _adminExecutor.execute(
                address(_timelock),
                0,
                abi.encodeCall(
                    _timelock.setEmergencyProtectionExecutionCommittee, (address(_emergencyExecutionCommittee))
                )
            );
            _adminExecutor.execute(
                address(_timelock),
                0,
                abi.encodeCall(
                    _timelock.setEmergencyProtectionEndDate, (_EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()))
                )
            );
            _adminExecutor.execute(
                address(_timelock), 0, abi.encodeCall(_timelock.setEmergencyModeDuration, (_EMERGENCY_MODE_DURATION))
            );

            _adminExecutor.execute(
                address(_timelock), 0, abi.encodeCall(_timelock.setEmergencyGovernance, (address(_emergencyGovernance)))
            );
        }
    }

    function _finalizeEmergencyProtectedTimelockDeploy(IGovernance governance) internal {
        _adminExecutor.execute(
            address(_timelock), 0, abi.encodeCall(_timelock.setupDelays, (_AFTER_SUBMIT_DELAY, _AFTER_SCHEDULE_DELAY))
        );
        _adminExecutor.execute(address(_timelock), 0, abi.encodeCall(_timelock.setGovernance, (address(governance))));
        _adminExecutor.transferOwnership(address(_timelock));
    }

    function _deployExecutor(address owner) internal returns (Executor) {
        return new Executor(owner);
    }

    function _deployEmergencyProtectedTimelock(Executor adminExecutor) internal returns (EmergencyProtectedTimelock) {
        return new EmergencyProtectedTimelock({
            adminExecutor: address(adminExecutor),
            sanityCheckParams: EmergencyProtectedTimelock.SanityCheckParams({
                maxAfterSubmitDelay: _MAX_AFTER_SUBMIT_DELAY,
                maxAfterScheduleDelay: _MAX_AFTER_SCHEDULE_DELAY,
                maxEmergencyModeDuration: _MAX_EMERGENCY_MODE_DURATION,
                maxEmergencyProtectionDuration: _MAX_EMERGENCY_PROTECTION_DURATION
            })
        });
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

    function _deployDualGovernanceConfigProvider() internal returns (ImmutableDualGovernanceConfigProvider) {
        return new ImmutableDualGovernanceConfigProvider(
            DualGovernanceConfig.Context({
                firstSealRageQuitSupport: PercentsD16.fromBasisPoints(3_00), // 3%
                secondSealRageQuitSupport: PercentsD16.fromBasisPoints(15_00), // 15%
                //
                minAssetsLockDuration: Durations.from(5 hours),
                //
                vetoSignallingMinDuration: Durations.from(3 days),
                vetoSignallingMaxDuration: Durations.from(30 days),
                vetoSignallingMinActiveDuration: Durations.from(5 hours),
                vetoSignallingDeactivationMaxDuration: Durations.from(5 days),
                vetoCooldownDuration: Durations.from(4 days),
                //
                rageQuitExtensionPeriodDuration: Durations.from(7 days),
                rageQuitEthWithdrawalsMinDelay: Durations.from(30 days),
                rageQuitEthWithdrawalsMaxDelay: Durations.from(180 days),
                rageQuitEthWithdrawalsDelayGrowth: Durations.from(15 days)
            })
        );
    }

    function _deployResealManager(ITimelock timelock) internal returns (ResealManager) {
        return new ResealManager(timelock);
    }

    function _deployDualGovernance(
        ITimelock timelock,
        IResealManager resealManager,
        IDualGovernanceConfigProvider configProvider
    ) internal returns (DualGovernance) {
        return new DualGovernance({
            dependencies: DualGovernance.ExternalDependencies({
                stETH: _lido.stETH,
                wstETH: _lido.wstETH,
                withdrawalQueue: _lido.withdrawalQueue,
                timelock: timelock,
                resealManager: resealManager,
                configProvider: configProvider
            }),
            sanityCheckParams: DualGovernance.SanityCheckParams({
                minWithdrawalsBatchSize: 4,
                minTiebreakerActivationTimeout: MIN_TIEBREAKER_ACTIVATION_TIMEOUT,
                maxTiebreakerActivationTimeout: MAX_TIEBREAKER_ACTIVATION_TIMEOUT,
                maxSealableWithdrawalBlockersCount: MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT
            })
        });
    }

    function _deployEmptyTiebreakerCoreCommittee(
        address owner,
        IDualGovernance dualGovernance,
        Duration timelock
    ) internal returns (TiebreakerCoreCommittee) {
        return new TiebreakerCoreCommittee({owner: owner, dualGovernance: address(dualGovernance), timelock: timelock});
    }

    function _deployTiebreakerSubCommittee(
        address owner,
        uint256 quorum,
        address[] memory members,
        TiebreakerCoreCommittee tiebreakerCore
    ) internal returns (TiebreakerSubCommittee) {
        return new TiebreakerSubCommittee({
            owner: owner,
            executionQuorum: quorum,
            committeeMembers: members,
            tiebreakerCoreCommittee: address(tiebreakerCore)
        });
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
