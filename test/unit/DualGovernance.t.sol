// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations, lte} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {PercentsD16, PercentD16} from "contracts/types/PercentD16.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Executor} from "contracts/Executor.sol";
import {DualGovernance, State} from "contracts/DualGovernance.sol";
import {Tiebreaker} from "contracts/libraries/Tiebreaker.sol";
import {Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";
import {Proposers} from "contracts/libraries/Proposers.sol";
import {IResealManager} from "contracts/interfaces/IResealManager.sol";
import {
    DualGovernanceConfig,
    IDualGovernanceConfigProvider,
    ImmutableDualGovernanceConfigProvider
} from "contracts/DualGovernanceConfigProvider.sol";

import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {ISealable} from "contracts/interfaces/ISealable.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {StETHMock} from "test/mocks/StETHMock.sol";
import {TimelockMock} from "test/mocks/TimelockMock.sol";
import {WithdrawalQueueMock} from "test/mocks/WithdrawalQueueMock.sol";
import {SealableMock} from "test/mocks/SealableMock.sol";

contract DualGovernanceUnitTests is UnitTest {
    Executor private _executor = new Executor(address(this));

    address private vetoer = makeAddr("vetoer");

    StETHMock private immutable _STETH_MOCK = new StETHMock();
    IWithdrawalQueue private immutable _WITHDRAWAL_QUEUE_MOCK = new WithdrawalQueueMock();

    // TODO: Replace with mocks
    IWstETH private immutable _WSTETH_STUB = IWstETH(makeAddr("WSTETH_STUB"));
    IResealManager private immutable _RESEAL_MANAGER_STUB = IResealManager(makeAddr("RESEAL_MANAGER_STUB"));

    TimelockMock internal _timelock = new TimelockMock(address(_executor));
    ImmutableDualGovernanceConfigProvider internal _configProvider = new ImmutableDualGovernanceConfigProvider(
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
            //
            vetoCooldownDuration: Durations.from(4 days),
            //
            rageQuitExtensionPeriodDuration: Durations.from(7 days),
            rageQuitEthWithdrawalsMinDelay: Durations.from(30 days),
            rageQuitEthWithdrawalsMaxDelay: Durations.from(180 days),
            rageQuitEthWithdrawalsDelayGrowth: Durations.from(15 days)
        })
    );

    DualGovernance internal _dualGovernance = new DualGovernance({
        dependencies: DualGovernance.ExternalDependencies({
            stETH: _STETH_MOCK,
            wstETH: _WSTETH_STUB,
            withdrawalQueue: _WITHDRAWAL_QUEUE_MOCK,
            timelock: _timelock,
            resealManager: _RESEAL_MANAGER_STUB,
            configProvider: _configProvider
        }),
        sanityCheckParams: DualGovernance.SanityCheckParams({
            minWithdrawalsBatchSize: 4,
            minTiebreakerActivationTimeout: Durations.from(30 days),
            maxTiebreakerActivationTimeout: Durations.from(180 days),
            maxSealableWithdrawalBlockersCount: 128
        })
    });

    Escrow internal _escrow;

    function setUp() external {
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, address(this), address(_executor))
        );

        _escrow = Escrow(payable(_dualGovernance.getVetoSignallingEscrow()));
        _STETH_MOCK.mint(vetoer, 10 ether);
        vm.prank(vetoer);
        _STETH_MOCK.approve(address(_escrow), 10 ether);
    }

    // ---
    // submitProposal()
    // ---

    function test_submitProposal_HappyPath() external {
        ExternalCall[] memory calls = _generateExternalCalls();
        Proposers.Proposer memory proposer = _dualGovernance.getProposer(address(this));
        vm.expectCall(
            address(_timelock), 0, abi.encodeWithSelector(TimelockMock.submit.selector, proposer.executor, calls, "")
        );

        uint256 proposalId = _dualGovernance.submitProposal(calls, "");
        uint256[] memory submittedProposals = _timelock.getSubmittedProposals();

        assertEq(submittedProposals.length, 1);
        assertEq(submittedProposals[0], proposalId);
        assertEq(_timelock.getProposalsCount(), 1);
    }

    function test_submitProposal_ActivatesNextStateOnSubmit() external {
        vm.prank(vetoer);
        _escrow.lockStETH(5 ether);

        State currentStateBefore = _dualGovernance.getState();

        assertEq(currentStateBefore, State.VetoSignalling);
        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        assertEq(currentStateBefore, _dualGovernance.getState());

        _dualGovernance.submitProposal(_generateExternalCalls(), "");

        State currentStateAfter = _dualGovernance.getState();
        assertEq(currentStateAfter, State.RageQuit);
        assert(currentStateBefore != currentStateAfter);
    }

    function test_submitProposal_RevertOn_NotInNormalState() external {
        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);

        assertEq(_dualGovernance.getState(), State.VetoSignalling);
        _wait(_configProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));
        _escrow.unlockStETH();

        assertEq(_dualGovernance.getState(), State.VetoSignallingDeactivation);

        vm.expectRevert(abi.encodeWithSelector(DualGovernance.ProposalSubmissionBlocked.selector));
        _dualGovernance.submitProposal(_generateExternalCalls(), "");
    }

    // ---
    // scheduleProposal()
    // ---

    function test_scheduleProposal_HappyPath() external {
        uint256 proposalId = _dualGovernance.submitProposal(_generateExternalCalls(), "");
        Timestamp submittedAt = Timestamps.now();

        _wait(_configProvider.VETO_SIGNALLING_MIN_DURATION());
        _timelock.setSchedule(proposalId);

        vm.mockCall(
            address(_timelock),
            abi.encodeWithSelector(TimelockMock.getProposalDetails.selector, proposalId),
            abi.encode(
                ITimelock.ProposalDetails({
                    id: proposalId,
                    status: ProposalStatus.Submitted,
                    executor: address(0),
                    submittedAt: submittedAt,
                    scheduledAt: Timestamps.from(0)
                })
            )
        );
        vm.expectCall(address(_timelock), 0, abi.encodeWithSelector(TimelockMock.schedule.selector, proposalId));
        _dualGovernance.scheduleProposal(proposalId);

        uint256[] memory scheduledProposals = _timelock.getScheduledProposals();
        assertEq(scheduledProposals.length, 1);
        assertEq(scheduledProposals[0], proposalId);
    }

    function test_scheduleProposal_ActivatesNextState() external {
        uint256 proposalId = _dualGovernance.submitProposal(_generateExternalCalls(), "");
        Timestamp submittedAt = Timestamps.now();

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        _wait(_configProvider.VETO_SIGNALLING_MIN_DURATION());
        _escrow.unlockStETH();
        vm.stopPrank();
        _wait(_configProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));

        _timelock.setSchedule(proposalId);

        vm.mockCall(
            address(_timelock),
            abi.encodeWithSelector(TimelockMock.getProposalDetails.selector, proposalId),
            abi.encode(
                ITimelock.ProposalDetails({
                    id: proposalId,
                    status: ProposalStatus.Submitted,
                    executor: address(_executor),
                    submittedAt: submittedAt,
                    scheduledAt: Timestamps.from(0)
                })
            )
        );

        assertEq(_dualGovernance.getState(), State.VetoSignallingDeactivation);
        _dualGovernance.scheduleProposal(proposalId);
        assertEq(_dualGovernance.getState(), State.VetoCooldown);
    }

    function test_scheduleProposal_RevertOn_CannotSchedule() external {
        uint256 proposalId = _dualGovernance.submitProposal(_generateExternalCalls(), "");
        Timestamp submittedAt = Timestamps.now();

        vm.prank(vetoer);
        _escrow.lockStETH(5 ether);

        vm.mockCall(
            address(_timelock),
            abi.encodeWithSelector(TimelockMock.getProposalDetails.selector, proposalId),
            abi.encode(
                ITimelock.ProposalDetails({
                    id: proposalId,
                    status: ProposalStatus.Submitted,
                    executor: address(_executor),
                    submittedAt: submittedAt,
                    scheduledAt: Timestamps.from(0)
                })
            )
        );

        vm.expectRevert(abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, proposalId));
        _dualGovernance.scheduleProposal(proposalId);
    }

    // ---
    // cancelAllPendingProposals()
    // ---

    function test_cancelAllPendingProposals_HappyPath_SkippedInNormalState() external {
        _submitMockProposal();
        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 0);
        assertEq(_dualGovernance.getState(), State.Normal);

        vm.expectEmit();
        emit DualGovernance.CancelAllPendingProposalsSkipped();

        _dualGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 0);
    }

    function test_cancelAllPendingProposals_HappyPath_SkippedInVetoCooldownState() external {
        _submitMockProposal();
        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 0);
        assertEq(_dualGovernance.getState(), State.Normal);

        Escrow signallingEscrow = Escrow(payable(_dualGovernance.getVetoSignallingEscrow()));

        vm.startPrank(vetoer);
        signallingEscrow.lockStETH(5 ether);
        vm.stopPrank();

        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        _wait(_configProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        vm.prank(vetoer);
        signallingEscrow.unlockStETH();

        assertEq(_dualGovernance.getState(), State.VetoSignallingDeactivation);

        _wait(_configProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));

        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.VetoCooldown);

        vm.expectEmit();
        emit DualGovernance.CancelAllPendingProposalsSkipped();

        _dualGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 0);
    }

    function test_cancelAllPendingProposals_HappyPath_SkippedInRageQuitState() external {
        _submitMockProposal();
        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 0);
        assertEq(_dualGovernance.getState(), State.Normal);

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();

        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.RageQuit);

        vm.expectEmit();
        emit DualGovernance.CancelAllPendingProposalsSkipped();

        _dualGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 0);
    }

    function test_cancelAllPendingProposals_HappyPath_ExecutedInVetoSignallingState() external {
        _submitMockProposal();
        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 0);
        assertEq(_dualGovernance.getState(), State.Normal);

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();

        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        vm.expectEmit();
        emit DualGovernance.CancelAllPendingProposalsExecuted();

        _dualGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 1);
    }

    function test_cancelAllPendingProposals_HappyPath_ExecutedInVetoSignallingDeactivationState() external {
        _submitMockProposal();
        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 0);
        assertEq(_dualGovernance.getState(), State.Normal);

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();

        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        _wait(_configProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        vm.prank(vetoer);
        _escrow.unlockStETH();

        assertEq(_dualGovernance.getState(), State.VetoSignallingDeactivation);

        vm.expectEmit();
        emit DualGovernance.CancelAllPendingProposalsExecuted();

        _dualGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 1);
    }

    function test_cancelAllPendingProposals_RevertOn_NotAdminProposer() external {
        address nonAdminProposer = makeAddr("NON_ADMIN_PROPOSER");
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, nonAdminProposer, address(0x123))
        );
        _submitMockProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        vm.prank(nonAdminProposer);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.NotAdminProposer.selector));
        _dualGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 0);
    }

    // ---
    // canSubmitProposal()
    // ---

    function test_canSubmitProposal_HappyPath() external {
        assertTrue(_dualGovernance.canSubmitProposal());
        assertEq(_dualGovernance.getState(), State.Normal);

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);

        _dualGovernance.activateNextState();
        assertTrue(_dualGovernance.canSubmitProposal());
        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        _wait(_configProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        _escrow.unlockStETH();
        _dualGovernance.activateNextState();

        assertFalse(_dualGovernance.canSubmitProposal());
        assertEq(_dualGovernance.getState(), State.VetoSignallingDeactivation);

        _wait(_configProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
        _dualGovernance.activateNextState();

        assertFalse(_dualGovernance.canSubmitProposal());
        assertEq(_dualGovernance.getState(), State.VetoCooldown);

        _wait(_configProvider.VETO_COOLDOWN_DURATION().plusSeconds(1));

        _dualGovernance.activateNextState();

        assertTrue(_dualGovernance.canSubmitProposal());
        assertEq(_dualGovernance.getState(), State.Normal);

        _escrow.lockStETH(5 ether);
        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        _dualGovernance.activateNextState();

        assertTrue(_dualGovernance.canSubmitProposal());
        assertEq(_dualGovernance.getState(), State.RageQuit);
    }

    // ---
    // canScheduleProposal()
    // ---

    function test_canScheduleProposal_HappyPath() external {
        uint256 proposalId = 1;
        Timestamp submittedAt = Timestamps.now();

        vm.mockCall(
            address(_timelock),
            abi.encodeWithSelector(TimelockMock.getProposalDetails.selector, proposalId),
            abi.encode(
                ITimelock.ProposalDetails({
                    id: proposalId,
                    status: ProposalStatus.Submitted,
                    executor: address(_executor),
                    submittedAt: submittedAt,
                    scheduledAt: Timestamps.from(0)
                })
            )
        );

        vm.mockCall(
            address(_timelock), abi.encodeWithSelector(TimelockMock.canSchedule.selector, proposalId), abi.encode(true)
        );

        _wait(_configProvider.VETO_SIGNALLING_MIN_DURATION());

        assertTrue(_dualGovernance.canScheduleProposal(proposalId));
    }

    function test_canScheduleProposal_WhenTimelockCannotSchedule() external {
        uint256 proposalId = 1;
        Timestamp submittedAt = Timestamps.now();

        vm.mockCall(
            address(_timelock),
            abi.encodeWithSelector(TimelockMock.getProposalDetails.selector, proposalId),
            abi.encode(
                ITimelock.ProposalDetails({
                    id: proposalId,
                    status: ProposalStatus.Submitted,
                    executor: address(_executor),
                    submittedAt: submittedAt,
                    scheduledAt: Timestamps.from(0)
                })
            )
        );

        vm.mockCall(
            address(_timelock), abi.encodeWithSelector(TimelockMock.canSchedule.selector, proposalId), abi.encode(false)
        );

        _wait(_configProvider.VETO_SIGNALLING_MIN_DURATION());

        bool canSchedule = _dualGovernance.canScheduleProposal(proposalId);
        assertFalse(canSchedule);
    }

    function test_canScheduleProposal_WhenNotEnoughTimeElapsed() external {
        uint256 proposalId = 1;

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        _wait(_configProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));
        _escrow.unlockStETH();
        _wait(_configProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
        _dualGovernance.activateNextState();

        assertEq(_dualGovernance.getState(), State.VetoCooldown);

        vm.mockCall(
            address(_timelock),
            abi.encodeWithSelector(TimelockMock.getProposalDetails.selector, proposalId),
            abi.encode(
                ITimelock.ProposalDetails({
                    id: proposalId,
                    status: ProposalStatus.Submitted,
                    executor: address(_executor),
                    submittedAt: Timestamps.now(),
                    scheduledAt: Timestamps.from(0)
                })
            )
        );

        vm.mockCall(
            address(_timelock), abi.encodeWithSelector(TimelockMock.canSchedule.selector, proposalId), abi.encode(true)
        );
        assertFalse(_dualGovernance.canScheduleProposal(proposalId));
    }

    // ---
    // activateNextState() & getState()
    // ---

    function test_activateNextState_getState_HappyPath() external {
        assertEq(_dualGovernance.getState(), State.Normal);

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        _wait(_configProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));
        _escrow.unlockStETH();
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.VetoSignallingDeactivation);

        _wait(_configProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.VetoCooldown);

        _wait(_configProvider.VETO_COOLDOWN_DURATION().plusSeconds(1));
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.Normal);

        _escrow.lockStETH(5 ether);
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.RageQuit);
    }

    // ---
    // setConfigProvider()
    // ---

    function test_setConfigProvider() external {
        ImmutableDualGovernanceConfigProvider newConfigProvider = new ImmutableDualGovernanceConfigProvider(
            DualGovernanceConfig.Context({
                firstSealRageQuitSupport: PercentsD16.fromBasisPoints(5_00), // 5%
                secondSealRageQuitSupport: PercentsD16.fromBasisPoints(20_00), // 20%
                //
                minAssetsLockDuration: Durations.from(6 hours),
                //
                vetoSignallingMinDuration: Durations.from(4 days),
                vetoSignallingMaxDuration: Durations.from(35 days),
                vetoSignallingMinActiveDuration: Durations.from(6 hours),
                vetoSignallingDeactivationMaxDuration: Durations.from(6 days),
                vetoCooldownDuration: Durations.from(5 days),
                //
                rageQuitExtensionPeriodDuration: Durations.from(8 days),
                rageQuitEthWithdrawalsMinDelay: Durations.from(30 days),
                rageQuitEthWithdrawalsMaxDelay: Durations.from(180 days),
                rageQuitEthWithdrawalsDelayGrowth: Durations.from(15 days)
            })
        );

        IDualGovernanceConfigProvider oldConfigProvider = _dualGovernance.getConfigProvider();

        vm.expectEmit();
        emit DualGovernance.ConfigProviderSet(IDualGovernanceConfigProvider(address(newConfigProvider)));

        vm.expectCall(
            address(_escrow),
            0,
            abi.encodeWithSelector(Escrow.setMinAssetsLockDuration.selector, Durations.from(6 hours))
        );
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setConfigProvider.selector, address(newConfigProvider))
        );

        assertEq(address(_dualGovernance.getConfigProvider()), address(newConfigProvider));
        assertTrue(address(_dualGovernance.getConfigProvider()) != address(oldConfigProvider));
    }

    function testFuzz_setConfigProvider_RevertOn_NotAdminExecutor(address stranger) external {
        vm.assume(stranger != address(_executor));
        ImmutableDualGovernanceConfigProvider newConfigProvider = new ImmutableDualGovernanceConfigProvider(
            DualGovernanceConfig.Context({
                firstSealRageQuitSupport: PercentsD16.fromBasisPoints(5_00), // 5%
                secondSealRageQuitSupport: PercentsD16.fromBasisPoints(20_00), // 20%
                //
                minAssetsLockDuration: Durations.from(6 hours),
                //
                vetoSignallingMinDuration: Durations.from(4 days),
                vetoSignallingMaxDuration: Durations.from(35 days),
                vetoSignallingMinActiveDuration: Durations.from(6 hours),
                vetoSignallingDeactivationMaxDuration: Durations.from(6 days),
                vetoCooldownDuration: Durations.from(5 days),
                //
                rageQuitExtensionPeriodDuration: Durations.from(8 days),
                rageQuitEthWithdrawalsMinDelay: Durations.from(30 days),
                rageQuitEthWithdrawalsMaxDelay: Durations.from(180 days),
                rageQuitEthWithdrawalsDelayGrowth: Durations.from(15 days)
            })
        );

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotAdminExecutor.selector, stranger));
        _dualGovernance.setConfigProvider(newConfigProvider);

        assertEq(address(_dualGovernance.getConfigProvider()), address(_configProvider));
    }

    function test_setConfigProvider_RevertOn_ConfigZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.InvalidConfigProvider.selector, address(0)));
        _executor.execute(
            address(_dualGovernance), 0, abi.encodeWithSelector(DualGovernance.setConfigProvider.selector, address(0))
        );
    }

    function test_setConfigProvider_RevertOn_SameAddress() external {
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.InvalidConfigProvider.selector, address(_configProvider)));
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setConfigProvider.selector, address(_configProvider))
        );
    }

    // ---
    // getConfigProvider()
    // ---

    function test_getConfigProvider_HappyPath() external {
        assertEq(address(_dualGovernance.getConfigProvider()), address(_configProvider));

        ImmutableDualGovernanceConfigProvider newConfigProvider = new ImmutableDualGovernanceConfigProvider(
            DualGovernanceConfig.Context({
                firstSealRageQuitSupport: PercentsD16.fromBasisPoints(5_00), // 5%
                secondSealRageQuitSupport: PercentsD16.fromBasisPoints(20_00), // 20%
                //
                minAssetsLockDuration: Durations.from(6 hours),
                //
                vetoSignallingMinDuration: Durations.from(4 days),
                vetoSignallingMaxDuration: Durations.from(35 days),
                vetoSignallingMinActiveDuration: Durations.from(6 hours),
                vetoSignallingDeactivationMaxDuration: Durations.from(6 days),
                vetoCooldownDuration: Durations.from(5 days),
                //
                rageQuitExtensionPeriodDuration: Durations.from(8 days),
                rageQuitEthWithdrawalsMinDelay: Durations.from(30 days),
                rageQuitEthWithdrawalsMaxDelay: Durations.from(180 days),
                rageQuitEthWithdrawalsDelayGrowth: Durations.from(15 days)
            })
        );

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setConfigProvider.selector, address(newConfigProvider))
        );

        assertEq(address(_dualGovernance.getConfigProvider()), address(newConfigProvider));
        assertTrue(address(_dualGovernance.getConfigProvider()) != address(_configProvider));
    }

    // ---
    // getVetoSignallingEscrow()
    // ---

    function test_getVetoSignallingEscrow_HappyPath() external {
        assertEq(_dualGovernance.getVetoSignallingEscrow(), address(_escrow));

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);

        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.RageQuit);

        assertTrue(_dualGovernance.getVetoSignallingEscrow() != address(_escrow));
    }

    // ---
    // getRageQuitEscrow()
    // ---

    function test_getRageQuitEscrow_HappyPath() external {
        assertEq(_dualGovernance.getRageQuitEscrow(), address(0));

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);

        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.RageQuit);

        assertEq(_dualGovernance.getRageQuitEscrow(), address(_escrow));
    }

    // ---
    // getStateDetails()
    // ---

    function test_getStateDetails_HappyPath() external {
        Timestamp startTime = Timestamps.now();

        IDualGovernance.StateDetails memory details = _dualGovernance.getStateDetails();
        assertEq(details.state, State.Normal);
        assertEq(details.enteredAt, startTime);
        assertEq(details.vetoSignallingActivatedAt, Timestamps.from(0));
        assertEq(details.vetoSignallingReactivationTime, Timestamps.from(0));
        assertEq(details.normalOrVetoCooldownExitedAt, Timestamps.from(0));
        assertEq(details.rageQuitRound, 0);
        assertEq(details.dynamicDelay, Durations.from(0));

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();
        Timestamp vetoSignallingTime = Timestamps.now();
        _dualGovernance.activateNextState();

        details = _dualGovernance.getStateDetails();
        assertEq(details.state, State.VetoSignalling);
        assertEq(details.enteredAt, vetoSignallingTime);
        assertEq(details.vetoSignallingActivatedAt, vetoSignallingTime);
        assertEq(details.vetoSignallingReactivationTime, Timestamps.from(0));
        assertEq(details.normalOrVetoCooldownExitedAt, vetoSignallingTime);
        assertEq(details.rageQuitRound, 0);
        assertTrue(details.dynamicDelay > _configProvider.VETO_SIGNALLING_MIN_DURATION());

        _wait(_configProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));
        vm.prank(vetoer);
        _escrow.unlockStETH();
        Timestamp deactivationTime = Timestamps.now();
        _dualGovernance.activateNextState();

        details = _dualGovernance.getStateDetails();
        assertEq(details.state, State.VetoSignallingDeactivation);
        assertEq(details.enteredAt, deactivationTime);
        assertEq(details.vetoSignallingActivatedAt, vetoSignallingTime);
        assertEq(details.vetoSignallingReactivationTime, Timestamps.from(0));
        assertEq(details.normalOrVetoCooldownExitedAt, vetoSignallingTime);
        assertEq(details.rageQuitRound, 0);
        assertEq(details.dynamicDelay, Durations.from(0));

        _wait(_configProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
        Timestamp vetoCooldownTime = Timestamps.now();
        _dualGovernance.activateNextState();

        details = _dualGovernance.getStateDetails();
        assertEq(details.state, State.VetoCooldown);
        assertEq(details.enteredAt, vetoCooldownTime);
        assertEq(details.vetoSignallingActivatedAt, vetoSignallingTime);
        assertEq(details.vetoSignallingReactivationTime, Timestamps.from(0));
        assertEq(details.normalOrVetoCooldownExitedAt, vetoSignallingTime);
        assertEq(details.rageQuitRound, 0);
        assertEq(details.dynamicDelay, Durations.from(0));

        _wait(_configProvider.VETO_COOLDOWN_DURATION().plusSeconds(1));
        Timestamp backToNormalTime = Timestamps.now();
        _dualGovernance.activateNextState();

        details = _dualGovernance.getStateDetails();
        assertEq(details.state, State.Normal);
        assertEq(details.enteredAt, backToNormalTime);
        assertEq(details.vetoSignallingActivatedAt, vetoSignallingTime);
        assertEq(details.vetoSignallingReactivationTime, Timestamps.from(0));
        assertEq(details.normalOrVetoCooldownExitedAt, backToNormalTime);
        assertEq(details.rageQuitRound, 0);
        assertEq(details.dynamicDelay, Durations.from(0));

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        Timestamp secondVetoSignallingTime = Timestamps.now();
        _dualGovernance.activateNextState();
        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
        Timestamp rageQuitTime = Timestamps.now();
        _dualGovernance.activateNextState();
        vm.stopPrank();

        details = _dualGovernance.getStateDetails();
        assertEq(details.state, State.RageQuit);
        assertEq(details.enteredAt, rageQuitTime);
        assertEq(details.vetoSignallingActivatedAt, secondVetoSignallingTime);
        assertEq(details.vetoSignallingReactivationTime, Timestamps.from(0));
        assertEq(details.normalOrVetoCooldownExitedAt, backToNormalTime);
        assertEq(details.rageQuitRound, 1);
        assertEq(details.dynamicDelay, Durations.from(0));
    }

    // ---
    // registerProposer()
    // ---

    function test_registerProposer_HappyPath() external {
        address newProposer = makeAddr("NEW_PROPOSER");
        address newExecutor = makeAddr("NEW_EXECUTOR");

        assertFalse(_dualGovernance.isProposer(newProposer));
        assertFalse(_dualGovernance.isExecutor(newExecutor));

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, newProposer, newExecutor)
        );

        assertTrue(_dualGovernance.isProposer(newProposer));
        assertTrue(_dualGovernance.isExecutor(newExecutor));

        Proposers.Proposer memory proposer = _dualGovernance.getProposer(newProposer);
        assertEq(proposer.account, newProposer);
        assertEq(proposer.executor, newExecutor);
    }

    function testFuzz_registerProposer_RevertOn_NotAdminExecutor(address stranger) external {
        vm.assume(stranger != address(_executor));
        address newProposer = makeAddr("NEW_PROPOSER");
        address newExecutor = makeAddr("NEW_EXECUTOR");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotAdminExecutor.selector, stranger));
        _dualGovernance.registerProposer(newProposer, newExecutor);
    }

    // ---
    // unregisterProposer()
    // ---

    function test_unregisterProposer_HappyPath() external {
        address proposer = makeAddr("PROPOSER");
        address proposerExecutor = makeAddr("PROPOSER_EXECUTOR");

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, proposer, proposerExecutor)
        );

        assertTrue(_dualGovernance.isProposer(proposer));
        assertTrue(_dualGovernance.isExecutor(proposerExecutor));

        _executor.execute(
            address(_dualGovernance), 0, abi.encodeWithSelector(DualGovernance.unregisterProposer.selector, proposer)
        );

        assertFalse(_dualGovernance.isProposer(proposer));
        assertFalse(_dualGovernance.isExecutor(proposerExecutor));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, proposer));
        _dualGovernance.getProposer(proposer);
    }

    function testFuzz_unregisterProposer_RevertOn_NotAdminExecutor(address stranger) external {
        vm.assume(stranger != address(_executor));
        address proposer = makeAddr("PROPOSER");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotAdminExecutor.selector, stranger));
        _dualGovernance.unregisterProposer(proposer);
    }

    function test_unregisterProposer_RevertOn_UnownedAdminExecutor() external {
        address proposer = makeAddr("PROPOSER");
        address proposerExecutor = makeAddr("PROPOSER_EXECUTOR");
        address adminExecutor = _timelock.getAdminExecutor();

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, proposer, proposerExecutor)
        );

        vm.expectRevert(abi.encodeWithSelector(DualGovernance.UnownedAdminExecutor.selector));
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.unregisterProposer.selector, address(this))
        );

        assertTrue(_dualGovernance.isProposer(address(this)));
        assertTrue(_dualGovernance.isExecutor(adminExecutor));
    }

    // ---
    // isProposer()
    // ---

    function test_isProposer_HappyPath() external {
        address proposer = makeAddr("PROPOSER");
        address proposerExecutor = makeAddr("PROPOSER_EXECUTOR");

        assertFalse(_dualGovernance.isProposer(proposer));
        assertFalse(_dualGovernance.isExecutor(proposerExecutor));

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, proposer, proposerExecutor)
        );

        assertTrue(_dualGovernance.isProposer(proposer));
        assertTrue(_dualGovernance.isExecutor(proposerExecutor));
    }

    function testFuzz_isProposer_UnregisteredProposer(address proposer) external {
        vm.assume(proposer != address(this));

        assertFalse(_dualGovernance.isProposer(proposer));
    }

    // ---
    // getProposer()
    // ---

    function test_getProposer_HappyPath() external {
        address proposer = makeAddr("PROPOSER");
        address proposerExecutor = makeAddr("PROPOSER_EXECUTOR");

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, proposer, proposerExecutor)
        );

        Proposers.Proposer memory proposerData = _dualGovernance.getProposer(proposer);
        assertEq(proposerData.account, proposer);
        assertEq(proposerData.executor, proposerExecutor);
    }

    function testFuzz_getProposer_RevertOn_UnregisteredProposer(address proposer) external {
        vm.assume(proposer != address(this));

        vm.expectRevert(abi.encodeWithSelector(Proposers.ProposerNotRegistered.selector, proposer));
        _dualGovernance.getProposer(proposer);
    }

    // ---
    // getProposers()
    // ---

    function test_getProposers_HappyPath() external {
        address proposer1 = makeAddr("PROPOSER1");
        address proposer2 = makeAddr("PROPOSER2");
        address proposer3 = makeAddr("PROPOSER3");
        address proposerExecutor1 = makeAddr("PROPOSER_EXECUTOR1");
        address proposerExecutor2 = makeAddr("PROPOSER_EXECUTOR2");
        address proposerExecutor3 = makeAddr("PROPOSER_EXECUTOR3");

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, proposer1, proposerExecutor1)
        );
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, proposer2, proposerExecutor2)
        );
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, proposer3, proposerExecutor3)
        );

        Proposers.Proposer[] memory proposers = _dualGovernance.getProposers();
        assertEq(proposers.length, 4);
        assertEq(proposers[0].account, address(this));
        assertEq(proposers[0].executor, address(_executor));
        assertEq(proposers[1].executor, proposerExecutor1);
        assertEq(proposers[1].account, proposer1);
        assertEq(proposers[2].executor, proposerExecutor2);
        assertEq(proposers[2].account, proposer2);
        assertEq(proposers[3].executor, proposerExecutor3);
        assertEq(proposers[3].account, proposer3);
    }

    // ---
    // isExecutor()
    // ---

    function test_isExecutor_HappyPath() external {
        address executor = makeAddr("EXECUTOR1");

        assertFalse(_dualGovernance.isExecutor(executor));

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, address(0x123), executor)
        );

        assertTrue(_dualGovernance.isExecutor(executor));
        assertTrue(_dualGovernance.isExecutor(address(_executor)));
    }

    function testFuzz_isExecutor_UnregisteredExecutor(address executor) external {
        vm.assume(executor != address(_executor));

        assertFalse(_dualGovernance.isExecutor(executor));
    }

    // ---
    // addTiebreakerSealableWithdrawalBlocker()
    // ---

    function test_addTiebreakerSealableWithdrawalBlocker_HappyPath() external {
        address blocker = address(new SealableMock());

        vm.expectEmit();
        emit Tiebreaker.SealableWithdrawalBlockerAdded(blocker);
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.addTiebreakerSealableWithdrawalBlocker.selector, blocker)
        );
    }

    function testFuzz_addTiebreakerSealableWithdrawalBlocker_RevertOn_NotAdminExecutor(address stranger) external {
        vm.assume(stranger != address(_executor));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotAdminExecutor.selector, stranger));
        _dualGovernance.addTiebreakerSealableWithdrawalBlocker(address(0x123));
    }

    // ---
    // removeTiebreakerSealableWithdrawalBlocker()
    // ---

    function test_removeTiebreakerSealableWithdrawalBlocker_HappyPath() external {
        address blocker = address(new SealableMock());

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.addTiebreakerSealableWithdrawalBlocker.selector, blocker)
        );

        vm.expectEmit();
        emit Tiebreaker.SealableWithdrawalBlockerRemoved(blocker);
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.removeTiebreakerSealableWithdrawalBlocker.selector, blocker)
        );
    }

    function test_removeTiebreakerSealableWithdrawalBlocker_RevertOn_NotAdminExecutor(address stranger) external {
        vm.assume(stranger != address(_executor));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotAdminExecutor.selector, stranger));
        _dualGovernance.removeTiebreakerSealableWithdrawalBlocker(address(0x123));
    }

    // ---
    // setTiebreakerCommittee()
    // ---

    function testFuzz_setTiebreakerCommittee_HappyPath(address committee) external {
        vm.assume(committee != address(0));

        vm.expectEmit();
        emit Tiebreaker.TiebreakerCommitteeSet(committee);
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerCommittee.selector, committee)
        );
    }

    function testFuzz_setTiebreakerCommittee_RevertOn_NotAdminExecutor(address stranger) external {
        vm.assume(stranger != address(_executor));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotAdminExecutor.selector, stranger));
        _dualGovernance.setTiebreakerCommittee(address(0x123));
    }

    // ---
    // setTiebreakerActivationTimeout()
    // ---

    function testFuzz_setTiebreakerActivationTimeout_HappyPath(Duration timeout) external {
        vm.assume(
            lte(_dualGovernance.MIN_TIEBREAKER_ACTIVATION_TIMEOUT(), timeout)
                && lte(timeout, _dualGovernance.MAX_TIEBREAKER_ACTIVATION_TIMEOUT())
        );
        vm.expectEmit();
        emit Tiebreaker.TiebreakerActivationTimeoutSet(timeout);
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerActivationTimeout.selector, timeout)
        );
    }

    function testFuzz_setTiebreakerActivationTimeout_RevertOn_NotAdminExecutor(address stranger) external {
        vm.assume(stranger != address(_executor));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotAdminExecutor.selector, stranger));
        _dualGovernance.setTiebreakerActivationTimeout(Durations.from(1 days));
    }

    // ---
    // tiebreakerResumeSealable()
    // ---

    function test_tiebreakerResumeSealable_HappyPath() external {
        address sealable = address(new SealableMock());
        address tiebreakerCommittee = makeAddr("TIEBREAKER_COMMITTEE");

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerCommittee.selector, tiebreakerCommittee)
        );

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();
        _dualGovernance.activateNextState();
        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        vm.mockCall(
            address(_RESEAL_MANAGER_STUB),
            abi.encodeWithSelector(IResealManager.resume.selector, sealable),
            abi.encode()
        );
        vm.expectCall(address(_RESEAL_MANAGER_STUB), abi.encodeWithSelector(IResealManager.resume.selector, sealable));
        vm.prank(tiebreakerCommittee);
        _dualGovernance.tiebreakerResumeSealable(sealable);
    }

    function testFuzz_tiebreakerResumeSealable_RevertOn_NotTiebreakerCommittee(address stranger) external {
        vm.assume(stranger != makeAddr("TIEBREAKER_COMMITTEE"));
        address sealable = address(new SealableMock());

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerCommittee.selector, makeAddr("TIEBREAKER_COMMITTEE"))
        );

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();
        _dualGovernance.activateNextState();
        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.CallerIsNotTiebreakerCommittee.selector, stranger));
        _dualGovernance.tiebreakerResumeSealable(sealable);
    }

    function test_tiebreakerResumeSealable_ActivatesNextState() external {
        address sealable = address(new SealableMock());
        address tiebreakerCommittee = makeAddr("TIEBREAKER_COMMITTEE");

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerCommittee.selector, tiebreakerCommittee)
        );

        vm.startPrank(vetoer);
        _escrow.lockStETH(1 ether);
        vm.stopPrank();
        _dualGovernance.activateNextState();
        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        vm.mockCall(
            address(_RESEAL_MANAGER_STUB),
            abi.encodeWithSelector(IResealManager.resume.selector, sealable),
            abi.encode()
        );

        vm.prank(tiebreakerCommittee);
        _dualGovernance.tiebreakerResumeSealable(sealable);

        assertEq(_dualGovernance.getState(), State.VetoSignallingDeactivation);
        IDualGovernance.StateDetails memory stateDetails = _dualGovernance.getStateDetails();
        assertEq(stateDetails.enteredAt, Timestamps.now());
    }

    // ---
    // tiebreakerScheduleProposal()
    // ---

    function test_tiebreakerScheduleProposal_HappyPath() external {
        address tiebreakerCommittee = makeAddr("TIEBREAKER_COMMITTEE");

        _submitMockProposal();
        uint256 proposalId = 1;

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerCommittee.selector, tiebreakerCommittee)
        );

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();
        _dualGovernance.activateNextState();
        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        vm.mockCall(address(_timelock), abi.encodeWithSelector(ITimelock.schedule.selector, proposalId), abi.encode());
        vm.expectCall(address(_timelock), abi.encodeWithSelector(ITimelock.schedule.selector, proposalId));

        vm.prank(tiebreakerCommittee);
        _dualGovernance.tiebreakerScheduleProposal(proposalId);
    }

    function testFuzz_tiebreakerScheduleProposal_RevertOn_NotTiebreakerCommittee(address stranger) external {
        vm.assume(stranger != makeAddr("TIEBREAKER_COMMITTEE"));
        uint256 proposalId = 1;

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerCommittee.selector, makeAddr("TIEBREAKER_COMMITTEE"))
        );

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.CallerIsNotTiebreakerCommittee.selector, stranger));
        _dualGovernance.tiebreakerScheduleProposal(proposalId);
    }

    function test_tiebreakerScheduleProposal_ActivatesNextState() external {
        address tiebreakerCommittee = makeAddr("TIEBREAKER_COMMITTEE");
        _submitMockProposal();
        uint256 proposalId = 1;

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerCommittee.selector, tiebreakerCommittee)
        );

        vm.startPrank(vetoer);
        _escrow.lockStETH(1 ether);
        vm.stopPrank();
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.getState()), uint256(State.VetoSignalling));

        _wait(_configProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

        vm.expectCall(address(_timelock), abi.encodeWithSelector(ITimelock.schedule.selector, proposalId));
        vm.mockCall(address(_timelock), abi.encodeWithSelector(ITimelock.schedule.selector, proposalId), abi.encode());
        vm.prank(tiebreakerCommittee);
        _dualGovernance.tiebreakerScheduleProposal(proposalId);

        assertEq(uint256(_dualGovernance.getState()), uint256(State.VetoSignallingDeactivation));

        IDualGovernance.StateDetails memory stateDetails = _dualGovernance.getStateDetails();
        assertEq(stateDetails.enteredAt, Timestamps.now());
    }

    // ---
    // getTiebreakerDetails()
    // ---

    function test_getTiebreakerDetails_HappyPath() external {
        ITiebreaker.TiebreakerDetails memory details = _dualGovernance.getTiebreakerDetails();

        assertEq(details.tiebreakerCommittee, address(0));
        assertEq(details.tiebreakerActivationTimeout, Durations.from(0));
        assertFalse(details.isTie);
        assertEq(details.sealableWithdrawalBlockers.length, 0);

        address tiebreakerCommittee = makeAddr("TIEBREAKER_COMMITTEE");
        address sealable1 = address(new SealableMock());
        address sealable2 = address(new SealableMock());
        Duration newTimeout = _dualGovernance.MIN_TIEBREAKER_ACTIVATION_TIMEOUT().plusSeconds(1);

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerCommittee.selector, tiebreakerCommittee)
        );
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerActivationTimeout.selector, newTimeout)
        );
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.addTiebreakerSealableWithdrawalBlocker.selector, sealable1)
        );
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.addTiebreakerSealableWithdrawalBlocker.selector, sealable2)
        );

        details = _dualGovernance.getTiebreakerDetails();

        assertEq(details.tiebreakerCommittee, tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, newTimeout);
        assertFalse(details.isTie);
        assertEq(details.sealableWithdrawalBlockers.length, 2);
        assertTrue(
            details.sealableWithdrawalBlockers[0] == sealable1 || details.sealableWithdrawalBlockers[1] == sealable1
        );
        assertTrue(
            details.sealableWithdrawalBlockers[0] == sealable2 || details.sealableWithdrawalBlockers[1] == sealable2
        );
    }

    function test_getTiebreakerDetails_TieCondition() external {
        address tiebreakerCommittee = makeAddr("TIEBREAKER_COMMITTEE");
        address sealable = address(new SealableMock());
        Duration newTimeout = _dualGovernance.MIN_TIEBREAKER_ACTIVATION_TIMEOUT().plusSeconds(1);

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerCommittee.selector, tiebreakerCommittee)
        );
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setTiebreakerActivationTimeout.selector, newTimeout)
        );
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.addTiebreakerSealableWithdrawalBlocker.selector, sealable)
        );

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();
        _dualGovernance.activateNextState();
        assertEq(uint256(_dualGovernance.getState()), uint256(State.VetoSignalling));

        _wait(newTimeout.plusSeconds(1));

        ITiebreaker.TiebreakerDetails memory details = _dualGovernance.getTiebreakerDetails();

        assertEq(details.tiebreakerCommittee, tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, newTimeout);
        assertTrue(details.isTie);
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.sealableWithdrawalBlockers[0], sealable);
    }

    // ---
    // resealSealable()
    // ---

    function test_resealSealable_HappyPath() external {
        address resealCommittee = makeAddr("RESEAL_COMMITTEE");
        address sealable = address(new SealableMock());

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setResealCommittee.selector, resealCommittee)
        );

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        vm.mockCall(
            address(_RESEAL_MANAGER_STUB),
            abi.encodeWithSelector(IResealManager.reseal.selector, sealable),
            abi.encode()
        );
        vm.expectCall(address(_RESEAL_MANAGER_STUB), abi.encodeWithSelector(IResealManager.reseal.selector, sealable));
        vm.prank(resealCommittee);
        _dualGovernance.resealSealable(sealable);
    }

    function test_resealSealable_RevertOn_NotResealCommittee() external {
        address notResealCommittee = makeAddr("NOT_RESEAL_COMMITTEE");
        address sealable = address(new SealableMock());

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setResealCommittee.selector, makeAddr("RESEAL_COMMITTEE"))
        );

        vm.startPrank(vetoer);
        _escrow.lockStETH(5 ether);
        vm.stopPrank();
        _dualGovernance.activateNextState();
        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        vm.prank(notResealCommittee);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotResealCommittee.selector, notResealCommittee));
        _dualGovernance.resealSealable(sealable);
    }

    function test_resealSealable_RevertOn_NormalState() external {
        address resealCommittee = makeAddr("RESEAL_COMMITTEE");
        address sealable = address(new SealableMock());

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setResealCommittee.selector, resealCommittee)
        );

        assertEq(_dualGovernance.getState(), State.Normal);

        vm.prank(resealCommittee);
        vm.expectRevert(DualGovernance.ResealIsNotAllowedInNormalState.selector);
        _dualGovernance.resealSealable(sealable);
    }

    // ---
    // setResealCommittee()
    // ---

    function testFuzz_setResealCommittee_HappyPath(address newResealCommittee) external {
        vm.expectEmit();
        emit DualGovernance.ResealCommitteeSet(newResealCommittee);

        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.setResealCommittee.selector, newResealCommittee)
        );
    }

    function testFuzz_setResealCommittee_RevertOn_NotAdminExecutor(address stranger) external {
        vm.assume(stranger != address(_executor));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(DualGovernance.CallerIsNotAdminExecutor.selector, stranger));
        _dualGovernance.setResealCommittee(makeAddr("NEW_RESEAL_COMMITTEE"));
    }

    // ---
    // Helper methods
    // ---

    function _submitMockProposal() internal {
        // mock timelock doesn't uses proposal data
        _timelock.submit(address(0), new ExternalCall[](0), "");
    }

    function _generateExternalCalls() internal pure returns (ExternalCall[] memory calls) {
        calls = new ExternalCall[](1);
        calls[0] = ExternalCall({target: address(0x123), value: 0, payload: abi.encodeWithSignature("someFunction()")});
    }
}
