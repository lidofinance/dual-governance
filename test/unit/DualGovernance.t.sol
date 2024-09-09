// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Executor} from "contracts/Executor.sol";
import {DualGovernance, State} from "contracts/DualGovernance.sol";
import {IResealManager} from "contracts/interfaces/IResealManager.sol";
import {
    DualGovernanceConfig,
    IDualGovernanceConfigProvider,
    ImmutableDualGovernanceConfigProvider
} from "contracts/DualGovernanceConfigProvider.sol";

import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {StETHMock} from "test/mocks/StETHMock.sol";
import {TimelockMock} from "test/mocks/TimelockMock.sol";
import {WithdrawalQueueMock} from "test/mocks/WithdrawalQueueMock.sol";

contract DualGovernanceUnitTests is UnitTest {
    Executor private _executor = new Executor(address(this));

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
            dynamicTimelockMinDuration: Durations.from(3 days),
            dynamicTimelockMaxDuration: Durations.from(30 days),
            //
            vetoSignallingMinActiveDuration: Durations.from(5 hours),
            vetoSignallingDeactivationMaxDuration: Durations.from(5 days),
            vetoCooldownDuration: Durations.from(4 days),
            //
            rageQuitExtensionDelay: Durations.from(7 days),
            rageQuitEthWithdrawalsMinTimelock: Durations.from(60 days),
            rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber: 2,
            rageQuitEthWithdrawalsTimelockGrowthCoeffs: [uint256(0), 0, 0]
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

    function setUp() external {
        _executor.execute(
            address(_dualGovernance),
            0,
            abi.encodeWithSelector(DualGovernance.registerProposer.selector, address(this), address(_executor))
        );
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

        address vetoer = makeAddr("VETOER");
        _STETH_MOCK.mint(vetoer, 10 ether);

        vm.startPrank(vetoer);
        _STETH_MOCK.approve(address(signallingEscrow), 10 ether);
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

        Escrow signallingEscrow = Escrow(payable(_dualGovernance.getVetoSignallingEscrow()));

        address vetoer = makeAddr("VETOER");
        _STETH_MOCK.mint(vetoer, 10 ether);

        vm.startPrank(vetoer);
        _STETH_MOCK.approve(address(signallingEscrow), 10 ether);
        signallingEscrow.lockStETH(5 ether);
        vm.stopPrank();

        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        _wait(_configProvider.DYNAMIC_TIMELOCK_MAX_DURATION().plusSeconds(1));

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

        Escrow signallingEscrow = Escrow(payable(_dualGovernance.getVetoSignallingEscrow()));

        address vetoer = makeAddr("VETOER");
        _STETH_MOCK.mint(vetoer, 10 ether);

        vm.startPrank(vetoer);
        _STETH_MOCK.approve(address(signallingEscrow), 10 ether);
        signallingEscrow.lockStETH(5 ether);
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

        Escrow signallingEscrow = Escrow(payable(_dualGovernance.getVetoSignallingEscrow()));

        address vetoer = makeAddr("VETOER");
        _STETH_MOCK.mint(vetoer, 10 ether);

        vm.startPrank(vetoer);
        _STETH_MOCK.approve(address(signallingEscrow), 10 ether);
        signallingEscrow.lockStETH(5 ether);
        vm.stopPrank();

        assertEq(_dualGovernance.getState(), State.VetoSignalling);

        _wait(_configProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        vm.prank(vetoer);
        signallingEscrow.unlockStETH();

        assertEq(_dualGovernance.getState(), State.VetoSignallingDeactivation);

        vm.expectEmit();
        emit DualGovernance.CancelAllPendingProposalsExecuted();

        _dualGovernance.cancelAllPendingProposals();

        assertEq(_timelock.getProposalsCount(), 1);
        assertEq(_timelock.lastCancelledProposalId(), 1);
    }

    // ---
    // Helper methods
    // ---

    function _submitMockProposal() internal {
        // mock timelock doesn't uses proposal data
        _timelock.submit(address(0), new ExternalCall[](0), "");
    }
}
