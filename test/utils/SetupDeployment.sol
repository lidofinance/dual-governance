// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

// ---
// Types
// ---

import {PercentsD16} from "contracts/types/PercentD16.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps} from "contracts/types/Duration.sol";

// ---
// Interfaces
// ---
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IResealManager} from "contracts/interfaces/IResealManager.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";

import {IAragonACL} from "./interfaces/IAragonACL.sol";
import {IAragonAgent} from "./interfaces/IAragonAgent.sol";
import {IAragonVoting} from "./interfaces/IAragonVoting.sol";
import {IAragonForwarder} from "./interfaces/IAragonForwarder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

import {
    DeployConfig,
    DeployArtifacts,
    DeployedContracts,
    DGContractsDeployment,
    DualGovernanceDeployConfig,
    TiebreakerDeployConfig,
    TiebreakerCommitteeDeployConfig,
    EmergencyProtectedTimelockDeployConfig
} from "scripts/deploy/ContractsDeploymentNew.sol";

string constant CONFIG_FILES_DIR = "deploy-config";

abstract contract SetupDeployment is Test {
    using Random for Random.Context;

    // ---
    // Helpers
    // ---

    Random.Context internal _random;
    LidoUtils.Context internal _lido;

    // ---
    // Deploy Config
    // ---

    DeployConfig.Context internal _deployConfig;

    // ---
    // Emergency Protected Timelock Contracts
    // ---
    Executor internal _adminExecutor;
    EmergencyProtectedTimelock internal _timelock;
    TimelockedGovernance internal _timelockedGovernance;

    // ---
    // Timelocked Governance Contracts
    // ---
    TimelockedGovernance internal _emergencyGovernance;

    // ---
    // Dual Governance Contracts
    // ---
    ResealManager internal _resealManager;
    DualGovernance internal _dualGovernance;
    ImmutableDualGovernanceConfigProvider internal _dualGovernanceConfigProvider;

    TiebreakerCoreCommittee internal _tiebreakerCoreCommittee;
    TiebreakerSubCommittee[] internal _tiebreakerSubCommittees;

    // ---
    // Target Mock Helper Contract
    // ---

    TargetMock internal _targetMock;
    bool internal _isContractsLoaded;

    constructor(LidoUtils.Context memory lido, Random.Context memory random) {
        _lido = lido;
        _random = random;
        _targetMock = new TargetMock();

        // ---
        // Chain ID
        // ---

        _deployConfig.chainId = 1;

        // ---
        // Dual Governance
        // ---

        _deployConfig.dualGovernance.dualGovernanceConfig.firstSealRageQuitSupport = PercentsD16.fromBasisPoints(3_00);
        _deployConfig.dualGovernance.dualGovernanceConfig.secondSealRageQuitSupport = PercentsD16.fromBasisPoints(15_00);
        //
        _deployConfig.dualGovernance.dualGovernanceConfig.minAssetsLockDuration = Durations.from(5 hours);
        //
        _deployConfig.dualGovernance.dualGovernanceConfig.vetoSignallingMinDuration = Durations.from(3 days);
        _deployConfig.dualGovernance.dualGovernanceConfig.vetoSignallingMaxDuration = Durations.from(30 days);
        _deployConfig.dualGovernance.dualGovernanceConfig.vetoSignallingMinActiveDuration = Durations.from(5 hours);
        _deployConfig.dualGovernance.dualGovernanceConfig.vetoSignallingDeactivationMaxDuration = Durations.from(5 days);
        _deployConfig.dualGovernance.dualGovernanceConfig.vetoCooldownDuration = Durations.from(4 days);
        //
        _deployConfig.dualGovernance.dualGovernanceConfig.rageQuitExtensionPeriodDuration = Durations.from(7 days);
        _deployConfig.dualGovernance.dualGovernanceConfig.rageQuitEthWithdrawalsMinDelay = Durations.from(30 days);
        _deployConfig.dualGovernance.dualGovernanceConfig.rageQuitEthWithdrawalsMaxDelay = Durations.from(180 days);
        _deployConfig.dualGovernance.dualGovernanceConfig.rageQuitEthWithdrawalsDelayGrowth = Durations.from(15 days);

        _deployConfig.dualGovernance.signallingTokens.stETH = _lido.stETH;
        _deployConfig.dualGovernance.signallingTokens.wstETH = _lido.wstETH;
        _deployConfig.dualGovernance.signallingTokens.withdrawalQueue = _lido.withdrawalQueue;

        _deployConfig.dualGovernance.sanityCheckParams.minWithdrawalsBatchSize = 4;
        _deployConfig.dualGovernance.sanityCheckParams.minTiebreakerActivationTimeout = Durations.from(90 days);
        _deployConfig.dualGovernance.sanityCheckParams.maxTiebreakerActivationTimeout = Durations.from(730 days);
        _deployConfig.dualGovernance.sanityCheckParams.maxSealableWithdrawalBlockersCount = 255;
        _deployConfig.dualGovernance.sanityCheckParams.maxMinAssetsLockDuration = Durations.from(7 days);

        _deployConfig.dualGovernance.adminProposer = address(_lido.voting);
        _deployConfig.dualGovernance.resealCommittee = makeAddr("RESEAL_COMMITTEE");
        _deployConfig.dualGovernance.proposalsCanceller = address(_lido.voting);
        _deployConfig.dualGovernance.sealableWithdrawalBlockers = new address[](1);
        _deployConfig.dualGovernance.sealableWithdrawalBlockers[0] = address(_lido.withdrawalQueue);

        // ---
        // Emergency Protected Timelock
        // ---

        _deployConfig.timelock.afterSubmitDelay = Durations.from(3 days);
        _deployConfig.timelock.afterScheduleDelay = Durations.from(3 days);
        _deployConfig.timelock.sanityCheckParams.minExecutionDelay = Durations.from(3 days);
        _deployConfig.timelock.sanityCheckParams.maxAfterSubmitDelay = Durations.from(45 days);
        _deployConfig.timelock.sanityCheckParams.maxAfterScheduleDelay = Durations.from(45 days);
        _deployConfig.timelock.sanityCheckParams.maxEmergencyModeDuration = Durations.from(365 days);
        _deployConfig.timelock.sanityCheckParams.maxEmergencyProtectionDuration = Durations.from(365 days);
        _deployConfig.timelock.emergencyGovernanceProposer = address(_lido.voting);
        _deployConfig.timelock.emergencyActivationCommittee = makeAddr("EMERGENCY_ACTIVATION_COMMITTEE");
        _deployConfig.timelock.emergencyExecutionCommittee = makeAddr("EMERGENCY_EXECUTION_COMMITTEE");
        _deployConfig.timelock.emergencyModeDuration = Durations.from(180 days);
        _deployConfig.timelock.emergencyProtectionEndDate = Durations.from(90).addTo(Timestamps.now());

        // ---
        // Tiebreaker
        // ---

        _deployConfig.tiebreaker.quorum = 2;
        _deployConfig.tiebreaker.committeesCount = 2;
        _deployConfig.tiebreaker.executionDelay = Durations.from(30 days);
        _deployConfig.tiebreaker.activationTimeout = Durations.from(365 days);
        _deployConfig.tiebreaker.minActivationTimeout = Durations.from(90 days);
        _deployConfig.tiebreaker.maxActivationTimeout = Durations.from(365 days);

        uint256 tiebreakerCommitteesCount = 2;
        uint256 tiebreakerCommitteeMembersCount = 5;

        for (uint256 i = 0; i < tiebreakerCommitteesCount; ++i) {
            _deployConfig.tiebreaker.committees.push();
            _deployConfig.tiebreaker.committees[i].quorum = tiebreakerCommitteeMembersCount;
            _deployConfig.tiebreaker.committees[i].members = new address[](tiebreakerCommitteeMembersCount);
            for (uint256 j = 0; j < tiebreakerCommitteeMembersCount; ++j) {
                _deployConfig.tiebreaker.committees[i].members[j] = _random.nextAddress();
            }
        }
    }

    function _loadDeployArtifact(string memory deployArtifactFileName) internal {
        string memory root = vm.projectRoot();
        string memory deployArtifactFilePath = string.concat(root, "/", CONFIG_FILES_DIR, "/", deployArtifactFileName);

        DeployArtifacts.Context memory deployArtifacts = DeployArtifacts.load(deployArtifactFilePath);

        _targetMock = new TargetMock();

        _deployConfig.chainId = deployArtifacts.deployConfig.chainId;
        _deployConfig.timelock = deployArtifacts.deployConfig.timelock;
        _deployConfig.dualGovernance = deployArtifacts.deployConfig.dualGovernance;

        _deployConfig.tiebreaker.quorum = deployArtifacts.deployConfig.tiebreaker.quorum;
        _deployConfig.tiebreaker.executionDelay = deployArtifacts.deployConfig.tiebreaker.executionDelay;
        _deployConfig.tiebreaker.committeesCount = deployArtifacts.deployConfig.tiebreaker.committeesCount;
        _deployConfig.tiebreaker.activationTimeout = deployArtifacts.deployConfig.tiebreaker.activationTimeout;
        _deployConfig.tiebreaker.maxActivationTimeout = deployArtifacts.deployConfig.tiebreaker.maxActivationTimeout;
        _deployConfig.tiebreaker.minActivationTimeout = deployArtifacts.deployConfig.tiebreaker.minActivationTimeout;

        _setDeployedContracts(deployArtifacts.deployedContracts);

        if (_deployConfig.chainId == 1) {
            _lido = LidoUtils.mainnet();
        } else if (_deployConfig.chainId == 17000) {
            _lido = LidoUtils.holesky();
        } else {
            revert(string.concat("Unsupported chain ID: ", vm.toString(_deployConfig.chainId)));
        }
        _isContractsLoaded = true;
    }

    // ---
    // Whole Setup Deployments
    // ---

    function _deployTimelockedGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        // _deployEmergencyProtectedTimelockContracts(isEmergencyProtectionEnabled, false);
        // _timelockedGovernance =
        //     DGContractsDeployment.deployTimelockedGovernance({governance: address(_lido.voting), timelock: _timelock});
        // DGContractsDeployment.finalizeEmergencyProtectedTimelockDeploy(
        //     _adminExecutor, _timelock, address(_timelockedGovernance)
        // );
    }

    function _deployDualGovernanceSetup(bool isEmergencyProtectionEnabled) internal {
        if (_isContractsLoaded) {
            // TODO: setup emergency protection here
            return;
        }
        if (!isEmergencyProtectionEnabled) {
            _deployConfig.timelock.emergencyGovernanceProposer = address(0);
            _deployConfig.timelock.emergencyActivationCommittee = address(0);
            _deployConfig.timelock.emergencyExecutionCommittee = address(0);
            _deployConfig.timelock.emergencyModeDuration = Durations.ZERO;
            _deployConfig.timelock.emergencyProtectionEndDate = Timestamps.ZERO;
        }
        _setDeployedContracts(DGContractsDeployment.deployDualGovernanceSetup(address(this), _deployConfig));
    }

    function _setDeployedContracts(DeployedContracts.Context memory _contracts) private {
        _adminExecutor = _contracts.adminExecutor;
        _timelock = _contracts.timelock;
        _emergencyGovernance = _contracts.emergencyGovernance;
        _resealManager = _contracts.resealManager;
        _dualGovernance = _contracts.dualGovernance;
        _dualGovernanceConfigProvider = _contracts.dualGovernanceConfigProvider;
        _tiebreakerCoreCommittee = _contracts.tiebreakerCoreCommittee;
        _tiebreakerSubCommittees = _contracts.tiebreakerSubCommittees;
    }
}
