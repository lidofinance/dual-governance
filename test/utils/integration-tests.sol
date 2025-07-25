// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console,reason-string,custom-errors */

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {SharesValues} from "contracts/types/SharesValue.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Duration.sol";
import {PercentsD16, PercentD16} from "contracts/types/PercentD16.sol";

import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IGovernance} from "contracts/interfaces/IGovernance.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";

import {IPotentiallyDangerousContract} from "./interfaces/IPotentiallyDangerousContract.sol";

import {Proposers} from "contracts/libraries/Proposers.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";

import {ISignallingEscrow, IRageQuitEscrow} from "contracts/Escrow.sol";
import {DualGovernance, State as DGState} from "contracts/DualGovernance.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {LidoUtils, IStETH, IWstETH, IWithdrawalQueue} from "./lido-utils.sol";
import {TargetMock} from "./target-mock.sol";
import {TestingAssertEqExtender} from "./testing-assert-eq-extender.sol";

import {ISealable} from "test/utils/interfaces/ISealable.sol";

import {UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";

import {
    ContractsDeployment,
    TGSetupDeployConfig,
    DualGovernanceConfig,
    TGSetupDeployedContracts,
    DGSetupDeployConfig,
    DGSetupDeployArtifacts,
    DGSetupDeployedContracts,
    DualGovernanceContractDeployConfig,
    TimelockContractDeployConfig
} from "scripts/utils/contracts-deployment.sol";
import {TiebreakerDeployConfig, TiebreakerSubCommitteeDeployConfig} from "scripts/utils/deployment/Tiebreaker.sol";

uint256 constant ACCURACY = 2 wei;
uint256 constant MAINNET_CHAIN_ID = 1;
uint256 constant HOLESKY_CHAIN_ID = 17000;
uint256 constant HOODI_CHAIN_ID = 560048;

uint256 constant LATEST_FORK_BLOCK_NUMBER = type(uint256).max;

// By default tests will be launched on the latest block for each network.
// To streamline developing experience may be helpful pin block number in the .env file.
uint256 constant DEFAULT_MAINNET_FORK_BLOCK_NUMBER = LATEST_FORK_BLOCK_NUMBER;
uint256 constant DEFAULT_HOLESKY_FORK_BLOCK_NUMBER = LATEST_FORK_BLOCK_NUMBER;
uint256 constant DEFAULT_HOODI_FORK_BLOCK_NUMBER = LATEST_FORK_BLOCK_NUMBER;

abstract contract ForkTestSetup is Test {
    error UnsupportedChainId(uint256 chainId);

    TargetMock internal _targetMock;
    LidoUtils.Context internal _lido;

    constructor() {
        vm.setNonce(address(this), 1000);
    }

    function _setupFork(uint256 chainId, uint256 blockNumber) internal {
        if (chainId == MAINNET_CHAIN_ID) {
            vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
            _lido = LidoUtils.mainnet();
        } else if (chainId == HOLESKY_CHAIN_ID) {
            vm.createSelectFork(vm.envString("HOLESKY_RPC_URL"));
            _lido = LidoUtils.holesky();
        } else if (chainId == HOODI_CHAIN_ID) {
            vm.createSelectFork(vm.envString("HOODI_RPC_URL"));
            _lido = LidoUtils.hoodi();
        } else {
            revert UnsupportedChainId(chainId);
        }
        if (blockNumber != LATEST_FORK_BLOCK_NUMBER) {
            vm.rollFork(blockNumber);
        }
        _targetMock = new TargetMock();
    }

    function _getEnvForkBlockNumberOrDefault(uint256 chainId) internal view returns (uint256) {
        if (chainId == MAINNET_CHAIN_ID) {
            return _readBlockNumberFromEnvOrDefault("MAINNET_FORK_BLOCK_NUMBER", DEFAULT_MAINNET_FORK_BLOCK_NUMBER);
        } else if (chainId == HOLESKY_CHAIN_ID) {
            return _readBlockNumberFromEnvOrDefault("HOLESKY_FORK_BLOCK_NUMBER", DEFAULT_HOLESKY_FORK_BLOCK_NUMBER);
        } else if (chainId == HOODI_CHAIN_ID) {
            return _readBlockNumberFromEnvOrDefault("HOODI_FORK_BLOCK_NUMBER", DEFAULT_HOODI_FORK_BLOCK_NUMBER);
        }
        revert UnsupportedChainId(chainId);
    }

    function _readBlockNumberFromEnvOrDefault(
        string memory envVariable,
        uint256 defaultBlockNumber
    ) private view returns (uint256 blockNumber) {
        string memory blockNumberAsString = vm.envOr(envVariable, string(""));
        if (keccak256(bytes(blockNumberAsString)) == keccak256("latest")) {
            return LATEST_FORK_BLOCK_NUMBER;
        }
        return vm.envOr(envVariable, defaultBlockNumber);
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

    function _assertNoTargetMockCalls() internal view {
        assertEq(_targetMock.getCalls().length, 0, "Unexpected target calls count");
    }

    function _wait(Duration duration) internal {
        vm.warp(block.timestamp + Duration.unwrap(duration));
    }

    function _step(string memory text) internal pure {
        // solhint-disable-next-line
        console.log(string.concat(">>> ", text));
    }
}

contract GovernedTimelockSetup is ForkTestSetup, TestingAssertEqExtender {
    Duration internal immutable _DEFAULT_EMERGENCY_MODE_DURATION = Durations.from(30 days);
    Duration internal immutable _DEFAULT_EMERGENCY_PROTECTION_DURATION = Durations.from(365 days);
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
        returns (TimelockContractDeployConfig.Context memory)
    {
        bool emProposerIsNotSet = emergencyGovernanceProposer == address(0);
        address emergencyActivationCommittee = emProposerIsNotSet ? address(0) : _DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE;
        address emergencyExecutionCommittee = emProposerIsNotSet ? address(0) : _DEFAULT_EMERGENCY_EXECUTION_COMMITTEE;
        Duration emergencyModeDuration = emProposerIsNotSet ? Durations.ZERO : _DEFAULT_EMERGENCY_MODE_DURATION;
        Timestamp emergencyProtectionEndDate =
            emProposerIsNotSet ? Timestamps.ZERO : _DEFAULT_EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now());

        return TimelockContractDeployConfig.Context({
            afterSubmitDelay: Durations.from(3 days),
            afterScheduleDelay: Durations.from(1 days),
            sanityCheckParams: EmergencyProtectedTimelock.SanityCheckParams({
                minExecutionDelay: Durations.from(3 days),
                maxAfterSubmitDelay: Durations.from(30 days),
                maxAfterScheduleDelay: Durations.from(10 days),
                maxEmergencyModeDuration: Durations.from(365 days),
                maxEmergencyProtectionDuration: Durations.from(3 * 365 days)
            }),
            emergencyGovernanceProposer: emergencyGovernanceProposer,
            emergencyActivationCommittee: emergencyActivationCommittee,
            emergencyExecutionCommittee: emergencyExecutionCommittee,
            emergencyModeDuration: emergencyModeDuration,
            emergencyProtectionEndDate: emergencyProtectionEndDate
        });
    }

    function _isEmergencyModeActive() internal view returns (bool) {
        return _timelock.isEmergencyModeActive();
    }

    function _isEmergencyProtectionEnabled() internal view returns (bool) {
        return _timelock.isEmergencyProtectionEnabled();
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

    function _getMaliciousCalls() internal view returns (ExternalCall[] memory calls) {
        calls = new ExternalCall[](1);
        calls[0] = ExternalCall({
            target: address(_targetMock),
            value: 0,
            payload: abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ())
        });
    }

    function _getEmergencyModeDuration() internal view returns (Duration) {
        return _timelock.getEmergencyProtectionDetails().emergencyModeDuration;
    }

    function _getEmergencyProtectionDuration() internal view returns (Duration) {
        Timestamp emergencyProtectionEndsAfter = _getEmergencyProtectionEndsAfter();
        return emergencyProtectionEndsAfter > Timestamps.now()
            ? Durations.from(emergencyProtectionEndsAfter.toSeconds() - Timestamps.now().toSeconds())
            : Durations.ZERO;
    }

    function _getEmergencyProtectionEndsAfter() internal view returns (Timestamp) {
        return _timelock.getEmergencyProtectionDetails().emergencyProtectionEndsAfter;
    }

    function _getEmergencyModeEndsAfter() internal view returns (Timestamp) {
        return _timelock.getEmergencyProtectionDetails().emergencyModeEndsAfter;
    }

    function _getLastProposalId() internal view returns (uint256) {
        return _timelock.getProposalsCount();
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

        assertEq(_getEmergencyModeEndsAfter(), _getEmergencyModeDuration().addTo(Timestamps.now()));
    }

    function _deactivateEmergencyMode() internal {
        _timelock.deactivateEmergencyMode();
        assertFalse(_timelock.isEmergencyModeActive());
    }

    function _emergencyReset() internal {
        assertTrue(_timelock.isEmergencyModeActive());
        assertNotEq(_timelock.getEmergencyGovernance(), _timelock.getGovernance());

        vm.prank(_timelock.getEmergencyExecutionCommittee());
        _timelock.emergencyReset();

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
            _timelock.getEmergencyProtectionDetails();

        assertEq(details.emergencyModeDuration, Durations.ZERO);
        assertEq(details.emergencyModeEndsAfter, Timestamps.ZERO);
        assertEq(details.emergencyProtectionEndsAfter, Timestamps.ZERO);

        assertFalse(_timelock.isEmergencyModeActive());
        assertFalse(_timelock.isEmergencyProtectionEnabled());

        assertEq(_timelock.getEmergencyActivationCommittee(), address(0));
        assertEq(_timelock.getEmergencyExecutionCommittee(), address(0));
        assertEq(_timelock.getEmergencyGovernance(), _timelock.getGovernance());
    }

    function _emergencyExecute(uint256 proposalId) internal {
        assertTrue(_timelock.isEmergencyModeActive());

        vm.prank(_timelock.getEmergencyExecutionCommittee());
        _timelock.emergencyExecute(proposalId);

        _assertProposalExecuted(proposalId);
    }

    // ---
    // Assertions
    // ---

    function _assertProposalSubmitted(uint256 proposalId) internal view {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Submitted,
            "TimelockProposal not in 'Submitted' state"
        );
    }

    function _assertSubmittedProposalData(uint256 proposalId, ExternalCall[] memory calls) internal view {
        _assertSubmittedProposalData(proposalId, _timelock.getAdminExecutor(), calls);
    }

    function _assertSubmittedProposalData(
        uint256 proposalId,
        address executor,
        ExternalCall[] memory expectedCalls
    ) internal view {
        (ITimelock.ProposalDetails memory proposal, ExternalCall[] memory calls) = _timelock.getProposal(proposalId);
        assertEq(proposal.id, proposalId, "unexpected proposal id");
        assertEq(proposal.status, ProposalStatus.Submitted, "unexpected status value");
        assertEq(proposal.executor, executor, "unexpected executor");
        assertEq(proposal.submittedAt, Timestamps.now(), "unexpected scheduledAt");
        assertEq(expectedCalls.length, calls.length, "unexpected calls length");

        for (uint256 i = 0; i < calls.length; ++i) {
            ExternalCall memory expected = expectedCalls[i];
            ExternalCall memory actual = calls[i];

            assertEq(actual.value, expected.value);
            assertEq(actual.target, expected.target);
            assertEq(actual.payload, expected.payload);
        }
    }

    function _assertCanSchedule(uint256 proposalId, bool canSchedule) internal view {
        assertEq(
            IGovernance(_timelock.getGovernance()).canScheduleProposal(proposalId),
            canSchedule,
            "unexpected canSchedule() value"
        );
    }

    function _assertCanExecute(uint256 proposalId, bool canExecute) internal view {
        assertEq(_timelock.canExecute(proposalId), canExecute, "unexpected canExecute() value");
    }

    function _assertProposalScheduled(uint256 proposalId) internal view {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Scheduled,
            "TimelockProposal not in 'Scheduled' state"
        );
    }

    function _assertProposalExecuted(uint256 proposalId) internal view {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Executed,
            "TimelockProposal not in 'Executed' state"
        );
    }

    function _assertProposalCancelled(uint256 proposalId) internal view {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Cancelled,
            "Proposal not in 'Cancelled' state"
        );
    }

    function external__activateEmergencyMode() external {
        _activateEmergencyMode();
    }

    function external__emergencyExecute(uint256 proposalId) external {
        _emergencyExecute(proposalId);
    }
}

contract DGScenarioTestSetup is GovernedTimelockSetup {
    using LidoUtils for LidoUtils.Context;

    address internal immutable _DEFAULT_RESEAL_COMMITTEE = makeAddr("DEFAULT_RESEAL_COMMITTEE");

    DGSetupDeployConfig.Context internal _dgDeployConfig;
    DGSetupDeployedContracts.Context internal _dgDeployedContracts;

    function _getDefaultDGDeployConfig(address emergencyGovernanceProposer)
        internal
        returns (DGSetupDeployConfig.Context memory config)
    {
        TiebreakerDeployConfig.Context memory tiebreakerDeployConfig;
        tiebreakerDeployConfig.quorum = 3;
        tiebreakerDeployConfig.executionDelay = Durations.from(30 days);
        tiebreakerDeployConfig.committees = new TiebreakerSubCommitteeDeployConfig[](3);

        for (uint256 i = 0; i < tiebreakerDeployConfig.committees.length; ++i) {
            tiebreakerDeployConfig.committees[i].quorum = 3;
            tiebreakerDeployConfig.committees[i].members = new address[](5);
            for (uint256 j = 0; j < tiebreakerDeployConfig.committees[i].members.length; ++j) {
                tiebreakerDeployConfig.committees[i].members[j] = vm.randomAddress();
            }
        }

        address[] memory sealableWithdrawalBlockers = new address[](1);
        sealableWithdrawalBlockers[0] = address(_lido.withdrawalQueue);

        config = DGSetupDeployConfig.Context({
            chainId: 1,
            tiebreaker: tiebreakerDeployConfig,
            dualGovernanceConfigProvider: DualGovernanceConfig.Context({
                firstSealRageQuitSupport: PercentsD16.fromBasisPoints(1_00),
                secondSealRageQuitSupport: PercentsD16.fromBasisPoints(10_00),
                //
                minAssetsLockDuration: Durations.from(5 hours),
                //
                vetoSignallingMinDuration: Durations.from(5 days),
                vetoSignallingMaxDuration: Durations.from(45 days),
                vetoSignallingMinActiveDuration: Durations.from(5 hours),
                vetoSignallingDeactivationMaxDuration: Durations.from(3 days),
                vetoCooldownDuration: Durations.from(5 hours),
                //
                rageQuitExtensionPeriodDuration: Durations.from(7 days),
                rageQuitEthWithdrawalsMinDelay: Durations.from(60 days),
                rageQuitEthWithdrawalsMaxDelay: Durations.from(180 days),
                rageQuitEthWithdrawalsDelayGrowth: Durations.from(15 days)
            }),
            dualGovernance: DualGovernanceContractDeployConfig.Context({
                signallingTokens: DualGovernance.SignallingTokens({
                    stETH: _lido.stETH,
                    wstETH: _lido.wstETH,
                    withdrawalQueue: _lido.withdrawalQueue
                }),
                sanityCheckParams: DualGovernance.SanityCheckParams({
                    minWithdrawalsBatchSize: 4,
                    minTiebreakerActivationTimeout: Durations.from(6 * 30 days),
                    maxTiebreakerActivationTimeout: Durations.from(730 days),
                    maxSealableWithdrawalBlockersCount: 255,
                    maxMinAssetsLockDuration: Durations.from(48 days)
                }),
                adminProposer: address(_lido.voting),
                resealCommittee: _DEFAULT_RESEAL_COMMITTEE,
                proposalsCanceller: address(_lido.voting),
                tiebreakerActivationTimeout: Durations.from(365 days),
                sealableWithdrawalBlockers: sealableWithdrawalBlockers
            }),
            timelock: _getDefaultTimelockDeployConfig(emergencyGovernanceProposer)
        });
    }

    function _deployDGSetup(bool isEmergencyProtectionEnabled) internal {
        _setupFork(MAINNET_CHAIN_ID, _getEnvForkBlockNumberOrDefault(MAINNET_CHAIN_ID));
        _deployDGSetup(isEmergencyProtectionEnabled ? address(_lido.voting) : address(0), MAINNET_CHAIN_ID);
    }

    function _deployDGSetup(bool isEmergencyProtectionEnabled, uint256 chainId) internal {
        _setupFork(chainId, _getEnvForkBlockNumberOrDefault(chainId));
        _deployDGSetup(isEmergencyProtectionEnabled ? address(_lido.voting) : address(0), chainId);
    }

    function _deployDGSetup(address emergencyGovernanceProposer) internal {
        _deployDGSetup(emergencyGovernanceProposer, MAINNET_CHAIN_ID);
    }

    function _deployDGSetup(address emergencyGovernanceProposer, uint256 chainId) internal {
        if (address(_lido.voting) == address(0)) {
            _setupFork(chainId, _getEnvForkBlockNumberOrDefault(chainId));
        }
        _setDGDeployConfig(_getDefaultDGDeployConfig(emergencyGovernanceProposer));
        _dgDeployedContracts = ContractsDeployment.deployDGSetup(address(this), _dgDeployConfig);

        _setTimelock(_dgDeployedContracts.timelock);
        _lido.removeStakingLimit();
    }

    function _adoptProposalByAdminProposer(
        ExternalCall[] memory calls,
        string memory metadata
    ) internal returns (uint256 proposalId) {
        proposalId = _adoptProposal(_getFirstAdminProposer(), calls, metadata);
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

    function _cancelAllPendingProposalsByProposalsCanceller() internal returns (bool) {
        vm.prank(_getProposalsCanceller());
        return _dgDeployedContracts.dualGovernance.cancelAllPendingProposals();
    }

    function _getProposalsCanceller() internal view returns (address) {
        return _dgDeployedContracts.dualGovernance.getProposalsCanceller();
    }

    function _getProposers() internal view returns (Proposers.Proposer[] memory) {
        return _dgDeployedContracts.dualGovernance.getProposers();
    }

    function _getGovernance() internal view returns (address governance) {
        return _timelock.getGovernance();
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

        revert("No available proposers");
    }

    function _getSealableWithdrawalBlockers() internal view returns (address[] memory) {
        return _dgDeployedContracts.dualGovernance.getTiebreakerDetails().sealableWithdrawalBlockers;
    }

    function _getResealCommittee() internal view returns (address) {
        return _dgDeployedContracts.dualGovernance.getResealCommittee();
    }

    function _getMinAssetsLockDuration() internal view returns (Duration) {
        return _getVetoSignallingEscrow().getMinAssetsLockDuration();
    }

    function _getVetoSignallingEscrow() internal view returns (ISignallingEscrow) {
        return ISignallingEscrow(payable(address(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow())));
    }

    function _getRageQuitEscrow() internal view returns (IRageQuitEscrow) {
        return IRageQuitEscrow(payable(address(_dgDeployedContracts.dualGovernance.getRageQuitEscrow())));
    }

    function _getSecondSealRageQuitSupport() internal view returns (PercentD16) {
        return _dgDeployedContracts.dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT();
    }

    function _getFirstSealRageQuitSupport() internal view returns (PercentD16) {
        return _dgDeployedContracts.dualGovernanceConfigProvider.FIRST_SEAL_RAGE_QUIT_SUPPORT();
    }

    function _getVetoSignallingMaxDuration() internal view returns (Duration) {
        return _dgDeployedContracts.dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION();
    }

    function _getVetoSignallingMinDuration() internal view returns (Duration) {
        return _dgDeployedContracts.dualGovernanceConfigProvider.VETO_SIGNALLING_MIN_DURATION();
    }

    function _getVetoSignallingMinActiveDuration() internal view returns (Duration) {
        return _dgDeployedContracts.dualGovernanceConfigProvider.VETO_SIGNALLING_MIN_ACTIVE_DURATION();
    }

    function _getVetoSignallingDeactivationMaxDuration() internal view returns (Duration) {
        return _dgDeployedContracts.dualGovernanceConfigProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION();
    }

    function _getVetoCooldownDuration() internal view returns (Duration) {
        return _dgDeployedContracts.dualGovernanceConfigProvider.VETO_COOLDOWN_DURATION();
    }

    function _getRageQuitExtensionPeriodDuration() internal view returns (Duration) {
        return _dgDeployedContracts.dualGovernanceConfigProvider.RAGE_QUIT_EXTENSION_PERIOD_DURATION();
    }

    function _getRageQuitEthWithdrawalsDelay() internal view returns (Duration) {
        return _getRageQuitEscrow().getRageQuitEscrowDetails().rageQuitEthWithdrawalsDelay;
    }

    function _getVetoSignallingDuration() internal view returns (Duration) {
        return _dgDeployedContracts.dualGovernance.getStateDetails().vetoSignallingDuration;
    }

    function _getVetoSignallingActivatedAt() internal view returns (Timestamp) {
        return _dgDeployedContracts.dualGovernance.getStateDetails().vetoSignallingActivatedAt;
    }

    function _assertCanSubmitProposal(bool canSubmit) internal view {
        assertEq(
            _dgDeployedContracts.dualGovernance.canSubmitProposal(), canSubmit, "unexpected canSubmitProposal() value"
        );
    }

    function _assertRageQuitFinalized(bool finalized) internal view {
        assertEq(_getRageQuitEscrow().isRageQuitFinalized(), finalized, "unexpected isRageQuitFinalized() value");
    }

    function _setDGDeployConfig(DGSetupDeployConfig.Context memory config) internal {
        _dgDeployConfig.chainId = config.chainId;
        _dgDeployConfig.timelock = config.timelock;
        _dgDeployConfig.dualGovernance = config.dualGovernance;
        _dgDeployConfig.dualGovernanceConfigProvider = config.dualGovernanceConfigProvider;

        _dgDeployConfig.tiebreaker.chainId = config.chainId;
        _dgDeployConfig.tiebreaker.quorum = config.tiebreaker.quorum;
        _dgDeployConfig.tiebreaker.executionDelay = config.tiebreaker.executionDelay;

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

    function _activateNextState() internal {
        _dgDeployedContracts.dualGovernance.activateNextState();
    }

    // ---
    // Balances Manipulation
    // ---

    function _setupStETHBalance(address account, uint256 amount) internal {
        _lido.submitStETH(account, amount);
    }

    function _setupStETHBalance(address account, PercentD16 tvlPercentage) internal {
        _lido.submitStETH(account, _lido.calcAmountToDepositFromPercentageOfTVL(tvlPercentage));
    }

    function _setupWstETHBalance(address account, uint256 amount) internal {
        _lido.submitWstETH(account, amount);
    }

    function _setupWstETHBalance(address account, PercentD16 tvlPercentage) internal {
        _lido.submitWstETH(account, _lido.calcSharesToDepositFromPercentageOfTVL(tvlPercentage));
    }

    // ---
    // Withdrawal Queue Operations
    // ---
    function _finalizeWithdrawalQueue() internal {
        _lido.finalizeWithdrawalQueue();
    }

    function _finalizeWithdrawalQueue(uint256 id) internal {
        _lido.finalizeWithdrawalQueue(id);
    }

    function _simulateRebase(PercentD16 rebaseFactor) internal {
        _lido.simulateRebase(rebaseFactor);
    }

    function _resealSealable(address sealable) internal {
        vm.prank(_getResealCommittee());
        _dgDeployedContracts.dualGovernance.resealSealable(sealable);
    }

    // ---
    // Escrow Manipulation
    // ---
    function _getCurrentRageQuitSupport() internal view returns (PercentD16) {
        return _getVetoSignallingEscrow().getRageQuitSupport();
    }

    function _lockStETHUpTo(address vetoer, PercentD16 targetPercentage) internal {
        ISignallingEscrow escrow = _getVetoSignallingEscrow();
        PercentD16 currentRageQuitSupport = escrow.getRageQuitSupport();
        assertTrue(currentRageQuitSupport < targetPercentage, "Current rage quit support must be less than target");

        uint256 amountToLock = _lido.calcAmountFromPercentageOfTVL(targetPercentage - currentRageQuitSupport);

        _lockStETH(vetoer, amountToLock);
    }

    function _lockStETH(address vetoer, PercentD16 tvlPercentage) internal returns (uint256) {
        return _lockStETH(vetoer, _lido.calcAmountFromPercentageOfTVL(tvlPercentage));
    }

    function _lockStETH(address vetoer, uint256 amount) internal returns (uint256 lockedStETHShares) {
        ISignallingEscrow escrow = _getVetoSignallingEscrow();

        uint256 vetoerStETHBalanceBefore = _lido.stETH.balanceOf(vetoer);
        uint256 escrowStETHBalanceBefore = _lido.stETH.balanceOf(address(escrow));
        ISignallingEscrow.VetoerDetails memory vetoerDetailsBefore = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory escrowDetailsBefore = escrow.getSignallingEscrowDetails();

        vm.startPrank(vetoer);
        {
            if (_lido.stETH.allowance(vetoer, address(escrow)) < amount) {
                _lido.stETH.approve(address(escrow), amount);
            }
            lockedStETHShares = escrow.lockStETH(amount);
        }
        vm.stopPrank();

        uint256 vetoerStETHBalanceAfter = _lido.stETH.balanceOf(vetoer);
        uint256 escrowStETHBalanceAfter = _lido.stETH.balanceOf(address(escrow));
        ISignallingEscrow.VetoerDetails memory vetoerDetailsAfter = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory escrowDetailsAfter = escrow.getSignallingEscrowDetails();

        // validate lock operation was done correctly
        assertApproxEqAbs(lockedStETHShares, _lido.stETH.getSharesByPooledEth(amount), ACCURACY);
        assertApproxEqAbs(vetoerStETHBalanceAfter, vetoerStETHBalanceBefore - amount, ACCURACY);
        assertApproxEqAbs(escrowStETHBalanceAfter, escrowStETHBalanceBefore + amount, ACCURACY);
        assertEq(
            vetoerDetailsAfter.stETHLockedShares,
            vetoerDetailsBefore.stETHLockedShares + SharesValues.from(lockedStETHShares)
        );
        assertEq(
            escrowDetailsAfter.totalStETHLockedShares,
            escrowDetailsBefore.totalStETHLockedShares + SharesValues.from(lockedStETHShares)
        );
    }

    function _unlockStETH(address vetoer) internal returns (uint256 unlockedStETHShares) {
        ISignallingEscrow escrow = _getVetoSignallingEscrow();

        uint256 vetoerStETHBalanceBefore = _lido.stETH.balanceOf(vetoer);
        uint256 escrowStETHBalanceBefore = _lido.stETH.balanceOf(address(escrow));
        ISignallingEscrow.VetoerDetails memory vetoerDetailsBefore = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory escrowDetailsBefore = escrow.getSignallingEscrowDetails();

        vm.startPrank(vetoer);
        {
            unlockedStETHShares = escrow.unlockStETH();
        }
        vm.stopPrank();

        ISignallingEscrow.VetoerDetails memory vetoerDetailsAfter = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory escrowDetailsAfter = escrow.getSignallingEscrowDetails();

        // validate unlock operation was done correctly
        uint256 vetoerSharesLockedBefore = vetoerDetailsBefore.stETHLockedShares.toUint256();
        uint256 expectedStETHAmountUnlocked = _lido.stETH.getPooledEthByShares(vetoerSharesLockedBefore);

        assertEq(unlockedStETHShares, vetoerSharesLockedBefore);
        assertApproxEqAbs(
            _lido.stETH.balanceOf(vetoer), vetoerStETHBalanceBefore + expectedStETHAmountUnlocked, ACCURACY
        );
        assertApproxEqAbs(
            _lido.stETH.balanceOf(address(escrow)), escrowStETHBalanceBefore - expectedStETHAmountUnlocked, ACCURACY
        );

        assertEq(vetoerDetailsAfter.stETHLockedShares, SharesValues.ZERO);
        assertEq(
            escrowDetailsAfter.totalStETHLockedShares,
            escrowDetailsBefore.totalStETHLockedShares - SharesValues.from(unlockedStETHShares)
        );
    }

    function _lockWstETH(address vetoer, PercentD16 tvlPercentage) internal returns (uint256) {
        return _lockWstETH(vetoer, _lido.calcSharesFromPercentageOfTVL(tvlPercentage));
    }

    function _lockWstETH(address vetoer, uint256 amount) internal returns (uint256 lockedStETHShares) {
        ISignallingEscrow escrow = _getVetoSignallingEscrow();

        uint256 vetoerWstETHBalanceBefore = _lido.wstETH.balanceOf(vetoer);
        uint256 escrowStETHBalanceBefore = _lido.stETH.balanceOf(address(escrow));
        ISignallingEscrow.VetoerDetails memory vetoerDetailsBefore = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory escrowDetailsBefore = escrow.getSignallingEscrowDetails();

        vm.startPrank(vetoer);
        {
            if (_lido.wstETH.allowance(vetoer, address(escrow)) < amount) {
                _lido.wstETH.approve(address(escrow), amount);
            }
            lockedStETHShares = escrow.lockWstETH(amount);
        }
        vm.stopPrank();

        uint256 vetoerWstETHBalanceAfter = _lido.wstETH.balanceOf(vetoer);
        uint256 escrowStETHBalanceAfter = _lido.stETH.balanceOf(address(escrow));
        ISignallingEscrow.VetoerDetails memory vetoerDetailsAfter = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory escrowDetailsAfter = escrow.getSignallingEscrowDetails();

        // validate lock operation was done correctly
        uint256 expectedStETHAmountLocked = _lido.stETH.getPooledEthByShares(amount);

        assertApproxEqAbs(lockedStETHShares, amount, ACCURACY);
        assertEq(vetoerWstETHBalanceAfter, vetoerWstETHBalanceBefore - amount);
        assertApproxEqAbs(escrowStETHBalanceAfter, escrowStETHBalanceBefore + expectedStETHAmountLocked, ACCURACY);
        assertEq(
            vetoerDetailsAfter.stETHLockedShares,
            vetoerDetailsBefore.stETHLockedShares + SharesValues.from(lockedStETHShares)
        );
        assertEq(
            escrowDetailsAfter.totalStETHLockedShares,
            escrowDetailsBefore.totalStETHLockedShares + SharesValues.from(lockedStETHShares)
        );
    }

    function _unlockWstETH(address vetoer) internal returns (uint256 wstETHUnlocked) {
        ISignallingEscrow escrow = _getVetoSignallingEscrow();

        uint256 vetoerWstETHBalanceBefore = _lido.wstETH.balanceOf(vetoer);
        uint256 escrowStETHBalanceBefore = _lido.stETH.balanceOf(address(escrow));
        ISignallingEscrow.VetoerDetails memory vetoerDetailsBefore = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory escrowDetailsBefore = escrow.getSignallingEscrowDetails();

        vm.startPrank(vetoer);
        {
            wstETHUnlocked = escrow.unlockWstETH();
        }
        vm.stopPrank();

        uint256 vetoerWstETHBalanceAfter = _lido.wstETH.balanceOf(vetoer);
        uint256 escrowStETHBalanceAfter = _lido.stETH.balanceOf(address(escrow));
        ISignallingEscrow.VetoerDetails memory vetoerDetailsAfter = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory escrowDetailsAfter = escrow.getSignallingEscrowDetails();

        // validate lock operation was done correctly
        uint256 expectedStETHAmountUnlocked = _lido.stETH.getPooledEthByShares(wstETHUnlocked);

        // 2 wei rounding issue may arise because of the wrapping stETH into wstETH before
        // sending funds to the user
        assertApproxEqAbs(wstETHUnlocked, vetoerDetailsBefore.stETHLockedShares.toUint256(), ACCURACY);

        assertEq(vetoerWstETHBalanceAfter, vetoerWstETHBalanceBefore + wstETHUnlocked);
        assertApproxEqAbs(escrowStETHBalanceAfter, escrowStETHBalanceBefore - expectedStETHAmountUnlocked, ACCURACY);
        assertEq(vetoerDetailsAfter.stETHLockedShares, SharesValues.ZERO);
        assertEq(
            escrowDetailsAfter.totalStETHLockedShares,
            escrowDetailsBefore.totalStETHLockedShares - vetoerDetailsBefore.stETHLockedShares
        );
    }

    function _lockUnstETH(address vetoer, uint256[] memory unstETHIds) internal {
        ISignallingEscrow escrow = _getVetoSignallingEscrow();
        ISignallingEscrow.VetoerDetails memory vetoerDetailsBefore = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory signallingEscrowDetailsBefore =
            escrow.getSignallingEscrowDetails();

        uint256 unstETHTotalSharesLocked = 0;
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            unstETHTotalSharesLocked += statuses[i].amountOfShares;
        }

        vm.startPrank(vetoer);
        {
            _lido.withdrawalQueue.setApprovalForAll(address(escrow), true);
            escrow.lockUnstETH(unstETHIds);
            _lido.withdrawalQueue.setApprovalForAll(address(escrow), false);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(_lido.withdrawalQueue.ownerOf(unstETHIds[i]), address(escrow));
        }

        ISignallingEscrow.VetoerDetails memory vetoerDetailsAfter = escrow.getVetoerDetails(vetoer);
        assertEq(vetoerDetailsAfter.unstETHIdsCount, vetoerDetailsBefore.unstETHIdsCount + unstETHIds.length);

        ISignallingEscrow.SignallingEscrowDetails memory signallingEscrowDetailsAfter =
            escrow.getSignallingEscrowDetails();
        assertEq(
            signallingEscrowDetailsAfter.totalUnstETHUnfinalizedShares.toUint256(),
            signallingEscrowDetailsBefore.totalUnstETHUnfinalizedShares.toUint256() + unstETHTotalSharesLocked
        );
    }

    function _unlockUnstETH(address vetoer, uint256[] memory unstETHIds) internal {
        ISignallingEscrow escrow = _getVetoSignallingEscrow();
        ISignallingEscrow.VetoerDetails memory vetoerDetailsBefore = escrow.getVetoerDetails(vetoer);
        ISignallingEscrow.SignallingEscrowDetails memory signallingEscrowDetailsBefore =
            escrow.getSignallingEscrowDetails();

        uint256 unstETHTotalUnfinalizedSharesUnlocked = 0;
        uint256 unstETHTotalFinalizedSharesUnlocked = 0;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);

        ISignallingEscrow.LockedUnstETHDetails[] memory lockedUnstETHDetails =
            escrow.getLockedUnstETHDetails(unstETHIds);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            if (lockedUnstETHDetails[i].status == UnstETHRecordStatus.Locked) {
                unstETHTotalUnfinalizedSharesUnlocked += statuses[i].amountOfShares;
            } else if (lockedUnstETHDetails[i].status == UnstETHRecordStatus.Finalized) {
                unstETHTotalFinalizedSharesUnlocked += statuses[i].amountOfShares;
            }
        }

        vm.startPrank(vetoer);
        {
            escrow.unlockUnstETH(unstETHIds);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(_lido.withdrawalQueue.ownerOf(unstETHIds[i]), vetoer);
        }

        ISignallingEscrow.VetoerDetails memory vetoerDetailsAfter = escrow.getVetoerDetails(vetoer);
        assertEq(vetoerDetailsAfter.unstETHIdsCount, vetoerDetailsBefore.unstETHIdsCount - unstETHIds.length);

        ISignallingEscrow.SignallingEscrowDetails memory signallingEscrowDetailsAfter =
            escrow.getSignallingEscrowDetails();
        assertEq(
            signallingEscrowDetailsAfter.totalUnstETHUnfinalizedShares.toUint256(),
            signallingEscrowDetailsBefore.totalUnstETHUnfinalizedShares.toUint256()
                - unstETHTotalUnfinalizedSharesUnlocked
        );
        assertEq(
            signallingEscrowDetailsAfter.totalUnstETHFinalizedETH.toUint256(),
            signallingEscrowDetailsBefore.totalUnstETHFinalizedETH.toUint256() - unstETHTotalFinalizedSharesUnlocked
        );
    }

    function _assertNormalState() internal view {
        assertEq(_dgDeployedContracts.dualGovernance.getPersistedState(), DGState.Normal);
    }

    function _assertVetoSignalingState() internal view {
        assertEq(_dgDeployedContracts.dualGovernance.getPersistedState(), DGState.VetoSignalling);
    }

    function _assertRageQuitState() internal view {
        assertEq(_dgDeployedContracts.dualGovernance.getPersistedState(), DGState.RageQuit);
    }

    function _assertVetoSignallingDeactivationState() internal view {
        assertEq(_dgDeployedContracts.dualGovernance.getPersistedState(), DGState.VetoSignallingDeactivation);
    }

    function _assertVetoCooldownState() internal view {
        assertEq(_dgDeployedContracts.dualGovernance.getPersistedState(), DGState.VetoCooldown);
    }

    function external__scheduleProposal(uint256 proposalId) external {
        _scheduleProposal(proposalId);
    }

    function external__unlockStETH(address vetoer) external {
        _unlockStETH(vetoer);
    }

    function external__unlockWstETH(address vetoer) external {
        _unlockWstETH(vetoer);
    }

    function external__unlockUnstETH(address vetoer, uint256[] memory unstETHIds) external {
        _unlockUnstETH(vetoer, unstETHIds);
    }
}

contract DGRegressionTestSetup is DGScenarioTestSetup {
    using LidoUtils for LidoUtils.Context;

    function _loadOrDeployDGSetup() internal returns (bool isSetupLoaded) {
        string memory deployArtifactFileName = vm.envOr("DEPLOY_ARTIFACT_FILE_NAME", string(""));

        console.log("File Name:", deployArtifactFileName);

        if (bytes(deployArtifactFileName).length > 0) {
            _loadDGSetup(deployArtifactFileName);
            console.log("Running on the loaded setup from file '%s'", deployArtifactFileName);
            return true;
        }
        _deployDGSetup({isEmergencyProtectionEnabled: true});
        console.log("Running on the deployed setup");
        return false;
    }

    function _loadDGSetup(string memory deployArtifactFileName) internal {
        DGSetupDeployArtifacts.Context memory deployArtifacts = DGSetupDeployArtifacts.load(deployArtifactFileName);

        uint256 chainId = deployArtifacts.deployConfig.chainId;
        console.log("CHAIN ID:", chainId);
        _setupFork(chainId, _getEnvForkBlockNumberOrDefault(chainId));
        console.log("Block Number:", block.number);

        _setDGDeployConfig(deployArtifacts.deployConfig);
        _dgDeployedContracts = deployArtifacts.deployedContracts;

        _setTimelock(_dgDeployedContracts.timelock);

        _processProposals();

        _grantResealingPermissions(deployArtifacts.deployConfig.dualGovernance.sealableWithdrawalBlockers);

        _lido.stETH = IStETH(payable(address(_dgDeployConfig.dualGovernance.signallingTokens.stETH)));
        _lido.wstETH = IWstETH(address(_dgDeployConfig.dualGovernance.signallingTokens.wstETH));
        _lido.withdrawalQueue =
            IWithdrawalQueue(payable(address(_dgDeployConfig.dualGovernance.signallingTokens.withdrawalQueue)));

        _lido.removeStakingLimit();
    }

    function _grantResealingPermissions(address[] memory sealables) internal {
        bool grantPermissionsFlag = vm.envOr("GRANT_RESEALING_PERMISSIONS", false);
        if (!grantPermissionsFlag) {
            return;
        }

        for (uint256 i = 0; i < sealables.length; ++i) {
            ISealable sealable = ISealable(sealables[i]);
            address sealableAdmin = sealable.getRoleMember(sealable.DEFAULT_ADMIN_ROLE(), 0);
            bytes32 pauseRole = sealable.PAUSE_ROLE();
            bytes32 resumeRole = sealable.RESUME_ROLE();

            if (!sealable.hasRole(pauseRole, address(_dgDeployedContracts.resealManager))) {
                console.log("Sealable:", sealableAdmin);
                vm.prank(sealableAdmin);
                sealable.grantRole(pauseRole, address(_dgDeployedContracts.resealManager));
            }
            if (!sealable.hasRole(resumeRole, address(_dgDeployedContracts.resealManager))) {
                vm.prank(sealableAdmin);
                sealable.grantRole(resumeRole, address(_dgDeployedContracts.resealManager));
            }
        }
    }

    function _processProposals() internal {
        uint256 proposalsCount = _timelock.getProposalsCount();
        _wait(_getAfterSubmitDelay());

        for (uint256 i = 1; i <= proposalsCount; ++i) {
            ITimelock.ProposalDetails memory proposalDetails = _timelock.getProposalDetails(i);
            if (proposalDetails.status == ProposalStatus.Submitted) {
                if (_dgDeployedContracts.dualGovernance.getPersistedState() == DGState.RageQuit) {
                    revert("Cannot schedule proposals in RAGE_QUIT state");
                }
                if (_dgDeployedContracts.dualGovernance.getPersistedState() == DGState.VetoSignalling) {
                    Duration vetoSignallingLastFor = _getVetoSignallingDuration()
                        - Durations.from(block.timestamp - _getVetoSignallingActivatedAt().toSeconds());
                    _wait(vetoSignallingLastFor.plusSeconds(1));
                    _activateNextState();
                }
                if (_dgDeployedContracts.dualGovernance.getPersistedState() == DGState.VetoSignallingDeactivation) {
                    _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
                    _activateNextState();
                }

                _assertCanSchedule(i, true);
                _scheduleProposal(i);
                _assertProposalScheduled(i);
            }
        }
        _wait(_getAfterScheduleDelay());

        for (uint256 i = 1; i <= proposalsCount; ++i) {
            ITimelock.ProposalDetails memory proposalDetails = _timelock.getProposalDetails(i);
            if (proposalDetails.status == ProposalStatus.Scheduled) {
                console.log("Executing proposal %s", i);
                _timelock.execute(i);
                _assertProposalExecuted(i);
            }
        }
    }
}

contract TGScenarioTestSetup is GovernedTimelockSetup {
    using LidoUtils for LidoUtils.Context;

    TGSetupDeployConfig.Context internal _tgDeployConfig;
    TGSetupDeployedContracts.Context internal _tgDeployedContracts;

    function _getDefaultTGDeployConfig(bool isEmergencyProtectionEnabled)
        internal
        view
        returns (TGSetupDeployConfig.Context memory)
    {
        return TGSetupDeployConfig.Context({
            chainId: block.chainid,
            governance: address(_lido.voting),
            timelock: _getDefaultTimelockDeployConfig(isEmergencyProtectionEnabled ? address(_lido.voting) : address(0))
        });
    }

    function _setTGDeployConfig(TGSetupDeployConfig.Context memory deployConfig) internal {
        _tgDeployConfig = deployConfig;
    }

    function _deployTGSetup(bool isEmergencyProtectionEnabled) internal {
        _setupFork(MAINNET_CHAIN_ID, DEFAULT_MAINNET_FORK_BLOCK_NUMBER);
        _setTGDeployConfig(_getDefaultTGDeployConfig(isEmergencyProtectionEnabled));
        _tgDeployedContracts = ContractsDeployment.deployTGSetup(address(this), _tgDeployConfig);

        _setTimelock(_tgDeployedContracts.timelock);
        _lido.removeStakingLimit();
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

    function _adoptProposal(
        ExternalCall[] memory calls,
        string memory metadata
    ) internal returns (uint256 proposalId) {
        proposalId = _adoptProposal(address(_tgDeployedContracts.timelockedGovernance.GOVERNANCE()), calls, metadata);
    }
}
