// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {PercentsD16} from "contracts/types/PercentD16.sol";
import {Timestamps, Timestamp} from "contracts/types/Duration.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";

import {IGovernance} from "contracts/interfaces/IGovernance.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";

import {IPotentiallyDangerousContract} from "./interfaces/IPotentiallyDangerousContract.sol";

import {Proposers} from "contracts/libraries/Proposers.sol";
import {Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {LidoUtils} from "./lido-utils.sol";
import {TargetMock} from "./target-mock.sol";
import {TestingAssertEqExtender} from "./testing-assert-eq-extender.sol";
import {ExternalCall, ExternalCallHelpers} from "../utils/executor-calls.sol";

import {
    Path,
    TGDeployConfig,
    TGDeployedContracts,
    DGDeployConfig,
    DGDeployArtifacts,
    DGDeployedContracts,
    ContractsDeployment,
    DualGovernanceDeployConfig,
    TiebreakerDeployConfig,
    DualGovernanceConfig,
    TiebreakerCommitteeDeployConfig,
    TimelockDeployConfig
} from "scripts/deploy/ContractsDeploymentNew.sol";

uint256 constant MAINNET_CHAIN_ID = 1;
uint256 constant HOLESKY_CHAIN_ID = 17000;

uint256 constant DEFAULT_HOLESKY_FORK_BLOCK_NUMBER = 3209735;
uint256 constant DEFAULT_MAINNET_FORK_BLOCK_NUMBER = 20218312;
uint256 constant LATEST_FORK_BLOCK_NUMBER = type(uint256).max;

abstract contract ForkTestSetup is Test {
    error UnsupportedChainId(uint256 chainId);

    TargetMock internal _targetMock;
    LidoUtils.Context internal _lido;

    function _setupFork(uint256 chainId, uint256 blockNumber) internal {
        if (chainId == MAINNET_CHAIN_ID) {
            vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
            _lido = LidoUtils.mainnet();
        } else if (chainId == HOLESKY_CHAIN_ID) {
            vm.createSelectFork(vm.envString("HOLESKY_RPC_URL"));
            _lido = LidoUtils.holesky();
        } else {
            revert UnsupportedChainId(chainId);
        }
        if (blockNumber != LATEST_FORK_BLOCK_NUMBER) {
            vm.rollFork(blockNumber);
        }
        _targetMock = new TargetMock();
    }

    function _getEnvForkBlockNumberOrDefault(uint256 defaultBlockNumber) internal returns (uint256) {
        return vm.envOr("FORK_BLOCK_NUMBER", defaultBlockNumber);
    }

    // ---
    // Assertions
    // ---

    function _assertTargetMockCalls(address caller, ExternalCall[] memory calls) internal {
        TargetMock.Call[] memory called = _targetMock.getCalls();
        assertEq(called.length, calls.length);

        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(called[i].sender, caller);
            assertEq(called[i].value, calls[i].value);
            assertEq(called[i].data, calls[i].payload);
            assertEq(called[i].blockNumber, block.number);
        }
        _targetMock.reset();
    }

    function _assertTargetMockCalls(address[] memory senders, ExternalCall[] memory calls) internal {
        TargetMock.Call[] memory called = _targetMock.getCalls();
        assertEq(called.length, calls.length);
        assertEq(called.length, senders.length);

        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(called[i].sender, senders[i], "Unexpected sender");
            assertEq(called[i].value, calls[i].value, "Unexpected value");
            assertEq(called[i].data, calls[i].payload, "Unexpected payload");
            assertEq(called[i].blockNumber, block.number);
        }
        _targetMock.reset();
    }

    function _assertNoTargetMockCalls() internal {
        assertEq(_targetMock.getCalls().length, 0, "Unexpected target calls count");
    }

    function _wait(Duration duration) internal {
        vm.warp(block.timestamp + Duration.unwrap(duration));
    }

    function _step(string memory text) internal {
        // solhint-disable-next-line
        console.log(string.concat(">>> ", text));
    }
}

contract GovernedTimelockSetup is ForkTestSetup, TestingAssertEqExtender {
    address internal immutable _DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE =
        makeAddr("DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE");
    address internal immutable _DEFAULT_EMERGENCY_EXECUTION_COMMITTEE =
        makeAddr("DEFAULT_EMERGENCY_EXECUTION_COMMITTEE");

    EmergencyProtectedTimelock internal _timelock;

    function _setTimelock(EmergencyProtectedTimelock timelock) internal {
        _timelock = timelock;
    }

    /// @dev When the emergencyGovernanceProposer is address(0) the emergency protection is considered
    ///     disabled
    function _getDefaultTimelockDeployConfig(address emergencyGovernanceProposer)
        internal
        view
        returns (TimelockDeployConfig memory)
    {
        address emergencyActivationCommittee =
            emergencyGovernanceProposer == address(0) ? address(0) : _DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE;
        address emergencyExecutionCommittee =
            emergencyGovernanceProposer == address(0) ? address(0) : _DEFAULT_EMERGENCY_EXECUTION_COMMITTEE;
        Duration emergencyModeDuration =
            emergencyGovernanceProposer == address(0) ? Durations.ZERO : Durations.from(180 days);
        Timestamp emergencyProtectionEndDate = emergencyGovernanceProposer == address(0)
            ? Timestamps.ZERO
            : Durations.from(90 days).addTo(Timestamps.now());

        return TimelockDeployConfig({
            afterSubmitDelay: Durations.from(3 days),
            afterScheduleDelay: Durations.from(3 days),
            sanityCheckParams: EmergencyProtectedTimelock.SanityCheckParams({
                minExecutionDelay: Durations.from(3 days),
                maxAfterSubmitDelay: Durations.from(45 days),
                maxAfterScheduleDelay: Durations.from(45 days),
                maxEmergencyModeDuration: Durations.from(365 days),
                maxEmergencyProtectionDuration: Durations.from(365 days)
            }),
            emergencyGovernanceProposer: emergencyGovernanceProposer,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyModeDuration: emergencyModeDuration,
            emergencyProtectionEndDate: emergencyProtectionEndDate
        });
    }

    function _getAdminExecutor() internal view returns (address) {
        return _timelock.getAdminExecutor();
    }

    function _getAfterSubmitDelay() internal view returns (Duration) {
        return _timelock.getAfterSubmitDelay();
    }

    function _getAfterScheduleDelay() internal view returns (Duration) {
        return _timelock.getAfterScheduleDelay();
    }

    function _getMockTargetRegularStaffCalls() internal view returns (ExternalCall[] memory) {
        return _getMockTargetRegularStaffCalls(1);
    }

    function _getMockTargetRegularStaffCalls(uint256 callsCount) internal view returns (ExternalCall[] memory calls) {
        calls = new ExternalCall[](callsCount);

        for (uint256 i = 0; i < calls.length; ++i) {
            calls[i].target = address(_targetMock);
            calls[i].payload = abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (i));
        }
    }

    function _executeProposal(uint256 proposalId) internal {
        _timelock.execute(proposalId);
    }

    function _submitProposal(address proposer, ExternalCall[] memory calls) internal returns (uint256 proposalId) {
        proposalId = _submitProposal(proposer, calls, string(""));
    }

    function _submitProposal(
        address proposer,
        ExternalCall[] memory calls,
        string memory metadata
    ) internal returns (uint256 proposalId) {
        uint256 proposalsCountBefore = _timelock.getProposalsCount();

        vm.startPrank(address(proposer));
        IGovernance(_timelock.getGovernance()).submitProposal(calls, metadata);
        vm.stopPrank();

        proposalId = _timelock.getProposalsCount();
        // new call is scheduled but is not executable yet
        assertEq(proposalId, proposalsCountBefore + 1);
    }

    function _scheduleProposal(uint256 proposalId) internal {
        IGovernance(_timelock.getGovernance()).scheduleProposal(proposalId);
    }

    function _activateEmergencyMode() internal {
        address emergencyActivationCommittee = _timelock.getEmergencyActivationCommittee();
        if (emergencyActivationCommittee == address(0)) {
            revert("Emergency activation committee not set");
        }
        vm.prank(emergencyActivationCommittee);
        _timelock.activateEmergencyMode();

        assertTrue(_timelock.isEmergencyModeActive());

        assertEq(
            _timelock.getEmergencyProtectionDetails().emergencyModeEndsAfter,
            _timelock.getEmergencyProtectionDetails().emergencyModeDuration.addTo(Timestamps.now())
        );
    }

    function _emergencyReset() internal {
        assertTrue(_timelock.isEmergencyModeActive());
        assertNotEq(_timelock.getEmergencyGovernance(), _timelock.getGovernance());

        vm.prank(_timelock.getEmergencyExecutionCommittee());
        _timelock.emergencyReset();

        // TODO: assert all emergency protection properties were reset

        assertFalse(_timelock.isEmergencyModeActive());
        assertEq(_timelock.getEmergencyGovernance(), _timelock.getGovernance());
    }

    // ---
    // Assertions
    // ---

    function _assertProposalSubmitted(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Submitted,
            "TimelockProposal not in 'Submitted' state"
        );
    }

    function _assertSubmittedProposalData(uint256 proposalId, ExternalCall[] memory calls) internal {
        _assertSubmittedProposalData(proposalId, _timelock.getAdminExecutor(), calls);
    }

    function _assertSubmittedProposalData(uint256 proposalId, address executor, ExternalCall[] memory calls) internal {
        (ITimelock.ProposalDetails memory proposal, ExternalCall[] memory calls) = _timelock.getProposal(proposalId);
        assertEq(proposal.id, proposalId, "unexpected proposal id");
        assertEq(proposal.status, ProposalStatus.Submitted, "unexpected status value");
        assertEq(proposal.executor, executor, "unexpected executor");
        assertEq(proposal.submittedAt, Timestamps.now(), "unexpected scheduledAt");
        assertEq(calls.length, calls.length, "unexpected calls length");

        for (uint256 i = 0; i < calls.length; ++i) {
            ExternalCall memory expected = calls[i];
            ExternalCall memory actual = calls[i];

            assertEq(actual.value, expected.value);
            assertEq(actual.target, expected.target);
            assertEq(actual.payload, expected.payload);
        }
    }

    function _assertCanSchedule(uint256 proposalId, bool canSchedule) internal {
        assertEq(
            IGovernance(_timelock.getGovernance()).canScheduleProposal(proposalId),
            canSchedule,
            "unexpected canSchedule() value"
        );
    }

    function _assertCanExecute(uint256 proposalId, bool canExecute) internal {
        assertEq(_timelock.canExecute(proposalId), canExecute, "unexpected canExecute() value");
    }

    function _assertProposalScheduled(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Scheduled,
            "TimelockProposal not in 'Scheduled' state"
        );
    }

    function _assertProposalExecuted(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Executed,
            "TimelockProposal not in 'Executed' state"
        );
    }
}

contract DGScenarioTestSetup is GovernedTimelockSetup {
    using LidoUtils for LidoUtils.Context;

    address internal immutable _DEFAULT_RESEAL_COMMITTEE = makeAddr("DEFAULT_RESEAL_COMMITTEE");

    DGDeployConfig.Context internal _dgDeployConfig;
    DGDeployedContracts.Context internal _dgDeployedContracts;

    function _getDefaultDGDeployConfig(address emergencyGovernanceProposer)
        internal
        returns (DGDeployConfig.Context memory config)
    {
        uint256 tiebreakerCommitteesCount = 2;
        uint256 tiebreakerCommitteeMembersCount = 5;

        TiebreakerCommitteeDeployConfig[] memory tiebreakerCommitteeConfigs =
            new TiebreakerCommitteeDeployConfig[](tiebreakerCommitteesCount);

        for (uint256 i = 0; i < tiebreakerCommitteesCount; ++i) {
            tiebreakerCommitteeConfigs[i].quorum = tiebreakerCommitteeMembersCount;
            tiebreakerCommitteeConfigs[i].members = new address[](tiebreakerCommitteeMembersCount);
            for (uint256 j = 0; j < tiebreakerCommitteeMembersCount; ++j) {
                tiebreakerCommitteeConfigs[i].members[j] = vm.randomAddress();
            }
        }

        address[] memory sealableWithdrawalBlockers = new address[](1);
        sealableWithdrawalBlockers[0] = address(_lido.withdrawalQueue);

        config = DGDeployConfig.Context({
            chainId: 1,
            tiebreaker: TiebreakerDeployConfig({
                quorum: tiebreakerCommitteesCount,
                committeesCount: tiebreakerCommitteesCount,
                executionDelay: Durations.from(30 days),
                activationTimeout: Durations.from(365 days),
                committees: tiebreakerCommitteeConfigs
            }),
            dualGovernance: DualGovernanceDeployConfig({
                dualGovernanceConfig: DualGovernanceConfig.Context({
                    firstSealRageQuitSupport: PercentsD16.fromBasisPoints(3_00),
                    secondSealRageQuitSupport: PercentsD16.fromBasisPoints(15_00),
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
                }),
                signallingTokens: DualGovernance.SignallingTokens({
                    stETH: _lido.stETH,
                    wstETH: _lido.wstETH,
                    withdrawalQueue: _lido.withdrawalQueue
                }),
                sanityCheckParams: DualGovernance.SanityCheckParams({
                    minWithdrawalsBatchSize: 4,
                    minTiebreakerActivationTimeout: Durations.from(90 days),
                    maxTiebreakerActivationTimeout: Durations.from(730 days),
                    maxSealableWithdrawalBlockersCount: 255,
                    maxMinAssetsLockDuration: Durations.from(7 days)
                }),
                adminProposer: address(_lido.voting),
                resealCommittee: _DEFAULT_RESEAL_COMMITTEE,
                proposalsCanceller: address(_lido.voting),
                sealableWithdrawalBlockers: sealableWithdrawalBlockers
            }),
            timelock: _getDefaultTimelockDeployConfig(emergencyGovernanceProposer)
        });
    }

    function _deployDGSetup(bool isEmergencyProtectionEnabled) internal {
        _setupFork(MAINNET_CHAIN_ID, _getEnvForkBlockNumberOrDefault(DEFAULT_MAINNET_FORK_BLOCK_NUMBER));
        _setDGDeployConfig(_getDefaultDGDeployConfig(isEmergencyProtectionEnabled ? address(_lido.voting) : address(0)));
        _dgDeployedContracts = ContractsDeployment.deployDGSetup(address(this), _dgDeployConfig);

        _setTimelock(_dgDeployedContracts.timelock);
    }

    function _deployDGSetup(address emergencyGovernanceProposer) internal {
        _setupFork(MAINNET_CHAIN_ID, _getEnvForkBlockNumberOrDefault(DEFAULT_MAINNET_FORK_BLOCK_NUMBER));
        _setDGDeployConfig(_getDefaultDGDeployConfig(emergencyGovernanceProposer));
        _dgDeployedContracts = ContractsDeployment.deployDGSetup(address(this), _dgDeployConfig);

        _setTimelock(_dgDeployedContracts.timelock);
    }

    function _adoptProposalByAdminProposer(
        ExternalCall[] memory calls,
        string memory metadata
    ) internal returns (uint256 proposalId) {
        proposalId = _adoptProposal(_getFirstAdminProposer(), calls, metadata);
    }

    function _adoptProposal(
        address proposer,
        ExternalCall[] memory calls,
        string memory metadata
    ) internal returns (uint256 proposalId) {
        proposalId = _submitProposal(proposer, calls, metadata);

        _assertProposalSubmitted(proposalId);
        _wait(_getAfterSubmitDelay());

        _scheduleProposal(proposalId);
        _assertProposalScheduled(proposalId);

        _wait(_getAfterScheduleDelay());
        _executeProposal(proposalId);
        _assertProposalExecuted(proposalId);
    }

    function _submitProposalByAdminProposer(ExternalCall[] memory calls) internal returns (uint256 proposalId) {
        proposalId = _submitProposalByAdminProposer(calls, string(""));
    }

    function _submitProposalByAdminProposer(
        ExternalCall[] memory calls,
        string memory metadata
    ) internal returns (uint256 proposalId) {
        proposalId = _submitProposal(_getFirstAdminProposer(), calls, metadata);
    }

    function _getProposers() internal view returns (Proposers.Proposer[] memory) {
        return _dgDeployedContracts.dualGovernance.getProposers();
    }

    function _getFirstAdminProposer() internal view returns (address) {
        Proposers.Proposer[] memory proposers = _getProposers();

        if (proposers.length == 0) {
            revert("No available proposers");
        }

        for (uint256 i = 0; i < proposers.length; ++i) {
            if (_dgDeployedContracts.dualGovernance.isExecutor(proposers[i].executor)) {
                return proposers[i].account;
            }
        }
    }

    function _setDGDeployConfig(DGDeployConfig.Context memory config) internal {
        _dgDeployConfig.chainId = config.chainId;
        _dgDeployConfig.timelock = config.timelock;
        _dgDeployConfig.dualGovernance = config.dualGovernance;

        _dgDeployConfig.tiebreaker.quorum = config.tiebreaker.quorum;
        _dgDeployConfig.tiebreaker.executionDelay = config.tiebreaker.executionDelay;
        _dgDeployConfig.tiebreaker.committeesCount = config.tiebreaker.committeesCount;
        _dgDeployConfig.tiebreaker.activationTimeout = config.tiebreaker.activationTimeout;

        // remove previously set committees
        for (uint256 i = 0; i < _dgDeployConfig.tiebreaker.committees.length; ++i) {
            _dgDeployConfig.tiebreaker.committees.pop();
        }

        for (uint256 i = 0; i < config.tiebreaker.committees.length; ++i) {
            _dgDeployConfig.tiebreaker.committees.push(config.tiebreaker.committees[i]);
        }
    }

    function _grantAragonAgentExecuteRole(address grantee) internal {
        if (!_lido.hasPermission(grantee, address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())) {
            _lido.grantPermission(address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE(), grantee);
        }

        if (!_lido.hasPermission(grantee, address(_lido.agent), _lido.agent.EXECUTE_ROLE())) {
            _lido.grantPermission(address(_lido.agent), _lido.agent.EXECUTE_ROLE(), grantee);
        }
    }
}

contract DGRegressionTestSetup is DGScenarioTestSetup {
    function _loadOrDeployDGSetup() internal returns (bool isSetupLoaded) {
        string memory deployArtifactFileName = vm.envOr("DEPLOY_ARTIFACT_FILE_NAME", string(""));

        console.log("File Name:", deployArtifactFileName);

        if (bytes(deployArtifactFileName).length > 0) {
            _loadDGSetup(deployArtifactFileName);
            console.log("Running on the loaded setup from file '%s'", deployArtifactFileName);
            return true;
        }
        _deployDGSetup({isEmergencyProtectionEnabled: false});
        console.log("Running on the deployed setup");
        return false;
    }

    function _loadDGSetup(string memory deployArtifactFileName) internal {
        string memory deployArtifactFilePath = Path.resolveDeployArtifact(deployArtifactFileName);
        DGDeployArtifacts.Context memory deployArtifacts = DGDeployArtifacts.load(deployArtifactFilePath);

        console.log("CHAIN ID:", deployArtifacts.deployConfig.chainId);
        _setupFork(deployArtifacts.deployConfig.chainId, _getEnvForkBlockNumberOrDefault(LATEST_FORK_BLOCK_NUMBER));

        _setDGDeployConfig(deployArtifacts.deployConfig);
        _dgDeployedContracts = deployArtifacts.deployedContracts;

        _setTimelock(_dgDeployedContracts.timelock);
    }
}

contract TimelockedGovernanceTestSetup is GovernedTimelockSetup {
    TGDeployConfig.Context internal _tgDeployConfig;
    TGDeployedContracts.Context internal _tgDeployedContracts;

    function _getDefaultTGDeployConfig(bool isEmergencyProtectionEnabled)
        internal
        returns (TGDeployConfig.Context memory)
    {
        return TGDeployConfig.Context({
            chainId: block.chainid,
            governance: address(_lido.voting),
            timelock: _getDefaultTimelockDeployConfig(isEmergencyProtectionEnabled ? address(_lido.voting) : address(0))
        });
    }

    function _setTGDeployConfig(TGDeployConfig.Context memory deployConfig) internal {
        _tgDeployConfig = deployConfig;
    }

    function _deployTGSetup(bool isEmergencyProtectionEnabled) internal {
        _setupFork(MAINNET_CHAIN_ID, DEFAULT_MAINNET_FORK_BLOCK_NUMBER);
        _setTGDeployConfig(_getDefaultTGDeployConfig(isEmergencyProtectionEnabled));
        _tgDeployedContracts = ContractsDeployment.deployTGSetup(address(this), _tgDeployConfig);

        _setTimelock(_tgDeployedContracts.timelock);
    }

    function _submitProposal(ExternalCall[] memory calls) internal returns (uint256 proposalId) {
        proposalId = _submitProposal(calls, string(""));
    }

    function _submitProposal(
        ExternalCall[] memory calls,
        string memory metadata
    ) internal returns (uint256 proposalId) {
        proposalId = _submitProposal(address(_tgDeployedContracts.timelockedGovernance.GOVERNANCE()), calls, metadata);
    }
}
