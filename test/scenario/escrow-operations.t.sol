// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";
import {PercentsD16, PercentD16, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";

import {EscrowState, State} from "contracts/libraries/EscrowState.sol";
import {WithdrawalsBatchesQueue} from "contracts/libraries/WithdrawalsBatchesQueue.sol";
import {AssetsAccounting, UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";

import {Escrow, IRageQuitEscrow, ISignallingEscrow} from "contracts/Escrow.sol";

import {LidoUtils, DGScenarioTestSetup} from "../utils/integration-tests.sol";

uint256 constant ST_ETH_TRANSFER_EPSILON = 2 wei;

contract EscrowOperationsScenarioTest is DGScenarioTestSetup {
    using LidoUtils for LidoUtils.Context;

    Escrow internal escrow;

    Duration internal immutable _RAGE_QUIT_EXTRA_TIMELOCK = Durations.from(14 days);
    Duration internal immutable _RAGE_QUIT_WITHDRAWALS_TIMELOCK = Durations.from(7 days);

    address internal immutable _VETOER_1 = makeAddr("VETOER_1");
    address internal immutable _VETOER_2 = makeAddr("VETOER_2");

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});

        escrow = Escrow(payable(address(_getVetoSignallingEscrow())));

        _setupStETHBalance(_VETOER_1, PercentsD16.fromBasisPoints(10_00));

        vm.startPrank(_VETOER_1);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        _lido.wstETH.wrap(100_000 * 10 ** 18);
        vm.stopPrank();

        _setupStETHBalance(_VETOER_2, PercentsD16.fromBasisPoints(10_00));

        vm.startPrank(_VETOER_2);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        _lido.wstETH.wrap(1_000_000 * 10 ** 18);
        vm.stopPrank();
    }

    function testFork_RageQuit_RevertOn_UnfinalizedNFTs() external {
        uint256 requestAmount = 10 * 1e18;
        uint256 requestsCount = 10;
        uint256[] memory amounts = new uint256[](requestsCount);
        for (uint256 i = 0; i < requestsCount; ++i) {
            amounts[i] = requestAmount;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        _lockUnstETH(_VETOER_1, unstETHIds);

        vm.prank(address(_dgDeployedContracts.dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        vm.expectRevert(Escrow.BatchesQueueIsNotClosed.selector);
        escrow.startRageQuitExtensionPeriod();

        escrow.requestNextWithdrawalsBatch(96);

        vm.expectRevert(WithdrawalsBatchesQueue.EmptyBatch.selector);
        escrow.claimNextWithdrawalsBatch(0);

        vm.expectRevert(Escrow.UnfinalizedUnstETHIds.selector);
        escrow.startRageQuitExtensionPeriod();

        _finalizeWithdrawalQueue();

        escrow.startRageQuitExtensionPeriod();

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

        escrow.claimUnstETH(unstETHIds, hints);

        assertEq(escrow.isRageQuitFinalized(), false);

        _wait(_RAGE_QUIT_EXTRA_TIMELOCK.plusSeconds(1));
        assertEq(escrow.isRageQuitFinalized(), true);

        _wait(_RAGE_QUIT_WITHDRAWALS_TIMELOCK.plusSeconds(1));

        vm.startPrank(_VETOER_1);
        escrow.withdrawETH(unstETHIds);
        vm.stopPrank();
    }

    function testFork_LockUnlock_RevertOn_RageQuitEscrow() external {
        uint256[] memory nftAmounts = new uint256[](1);
        nftAmounts[0] = 1 ether;

        vm.startPrank(_VETOER_1);
        uint256[] memory lockedWithdrawalNfts = _lido.withdrawalQueue.requestWithdrawals(nftAmounts, _VETOER_1);
        uint256[] memory notLockedWithdrawalNfts = _lido.withdrawalQueue.requestWithdrawals(nftAmounts, _VETOER_1);
        vm.stopPrank();

        _lockStETH(_VETOER_1, 1 ether);
        _lockWstETH(_VETOER_1, 1 ether);
        _lockUnstETH(_VETOER_1, lockedWithdrawalNfts);

        vm.prank(address(_dgDeployedContracts.dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        // ---
        // After the Escrow enters RageQuitEscrow state, lock/unlock of tokens is forbidden
        // ---

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalLockStETH(_VETOER_1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalLockWstETH(_VETOER_1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalLockUnstETH(_VETOER_1, notLockedWithdrawalNfts);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalUnlockStETH(_VETOER_1);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalUnlockWstETH(_VETOER_1);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
        this.externalUnlockUnstETH(_VETOER_1, lockedWithdrawalNfts);
    }

    function testFork_RageQuit_RevertOn_FrontRunWithTokensUnlock() external {
        uint256[] memory amounts = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            amounts[i] = _lido.withdrawalQueue.MAX_STETH_WITHDRAWAL_AMOUNT() - 1;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        _step("1. Lock enough funds to enter RageQUit");
        {
            _lockStETH(_VETOER_1, PercentsD16.fromBasisPoints(5_00));
            _lockWstETH(_VETOER_2, PercentsD16.fromBasisPoints(4_99));
            _lockUnstETH(_VETOER_1, unstETHIds);

            assertTrue(_getCurrentRageQuitSupport() >= _getSecondSealRageQuitSupport());
            _assertVetoSignalingState();
        }

        _step("2. Wait till the last second of the VetoSignalling duration");
        {
            _wait(_getVetoSignallingMaxDuration());

            _activateNextState();
            _assertVetoSignalingState();

            assertEq(_getVetoSignallingDuration().addTo(_getVetoSignallingActivatedAt()), Timestamps.now());
        }

        uint256 snapshotId = vm.snapshot();
        _step("3.1 While the VetoSignalling has not passed, vetoer can unlock funds from Escrow");
        {
            _unlockStETH(_VETOER_1);
            _assertVetoSignallingDeactivationState();

            // Rollback the state of the node before vetoer unlocked his funds
            vm.revertTo(snapshotId);
            _unlockWstETH(_VETOER_2);
            _assertVetoSignallingDeactivationState();

            // Rollback the state of the node before vetoer unlocked his funds
            vm.revertTo(snapshotId);

            _unlockUnstETH(_VETOER_1, unstETHIds);
            _assertVetoSignallingDeactivationState();

            // Rollback the state of the node before vetoer unlocked his funds
            vm.revertTo(snapshotId);
        }

        _step("3.2 When the RageQuit has entered vetoer can't unlock his funds");
        {
            // validate that the DualGovernance still in the VetoSignalling state
            _activateNextState();
            _assertVetoSignalingState();

            // wait 1 block duration. Full VetoSignalling duration has passed and RageQuit may be started now
            _wait(Durations.from(12 seconds));

            // validate that RageQuit will start when the activateNextState() is called
            snapshotId = vm.snapshot();
            _activateNextState();
            _assertRageQuitState();

            // Rollback the state of the node as it was before RageQuit activation
            vm.revertTo(snapshotId);

            // The attempt to unlock funds from Escrow will fail
            vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
            this.externalUnlockStETH(_VETOER_1);

            // Rollback the state of the node as it was before RageQuit activation
            vm.revertTo(snapshotId);

            // The attempt to unlock funds from Escrow will fail
            vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
            this.externalUnlockWstETH(_VETOER_2);

            // Rollback the state of the node as it was before RageQuit activation
            vm.revertTo(snapshotId);

            // The attempt to unlock funds from Escrow will fail
            vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
            this.externalUnlockUnstETH(_VETOER_1, unstETHIds);
        }
    }

    function testFork_ClaimingUnstETH_RevertOn_UnstETHFromWithdrawalBatch() external {
        // Prepare vetoer1 unstETH nft to lock in Escrow
        uint256 requestAmount = 10 * 1e18;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = requestAmount;
        vm.prank(_VETOER_1);
        uint256[] memory unstETHIdsVetoer1 = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        // Should be the same as vetoer1 unstETH nft
        uint256 lastRequestIdBeforeBatch = _lido.withdrawalQueue.getLastRequestId();

        // Lock unstETH nfts
        _lockUnstETH(_VETOER_1, unstETHIdsVetoer1);
        // Lock stETH to generate batch
        _lockStETH(_VETOER_1, 20 * requestAmount);

        vm.prank(address(_dgDeployedContracts.dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        uint256 batchSizeLimit = 16;
        // Generate batch with stETH locked in Escrow
        escrow.requestNextWithdrawalsBatch(batchSizeLimit);

        uint256[] memory nextWithdrawalBatch = escrow.getNextWithdrawalBatch(batchSizeLimit);
        assertEq(nextWithdrawalBatch.length, 1);
        assertEq(nextWithdrawalBatch[0], _lido.withdrawalQueue.getLastRequestId());

        // Should be the id of unstETH nft in the batch
        uint256 requestIdFromBatch = nextWithdrawalBatch[0];

        // validate that the new unstEth nft is created
        assertEq(requestIdFromBatch, lastRequestIdBeforeBatch + 1);

        _finalizeWithdrawalQueue();

        // Check that unstETH nft of vetoer1 could be claimed
        uint256[] memory unstETHIdsToClaim = new uint256[](1);
        unstETHIdsToClaim[0] = lastRequestIdBeforeBatch;
        uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
            unstETHIdsToClaim, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );
        escrow.claimUnstETH(unstETHIdsToClaim, hints);

        // The attempt to claim funds of untEth from Escrow generated batch will fail
        unstETHIdsToClaim[0] = requestIdFromBatch;
        hints = _lido.withdrawalQueue.findCheckpointHints(
            unstETHIdsToClaim, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector, requestIdFromBatch, UnstETHRecordStatus.NotLocked
            )
        );
        escrow.claimUnstETH(unstETHIdsToClaim, hints);

        // The rage quit process can be successfully finished
        while (escrow.getUnclaimedUnstETHIdsCount() > 0) {
            escrow.claimNextWithdrawalsBatch(batchSizeLimit);
        }

        escrow.startRageQuitExtensionPeriod();
        assertEq(escrow.isRageQuitFinalized(), false);

        _wait(_RAGE_QUIT_EXTRA_TIMELOCK.plusSeconds(1));
        assertEq(escrow.isRageQuitFinalized(), true);

        _wait(_RAGE_QUIT_WITHDRAWALS_TIMELOCK.plusSeconds(1));

        vm.startPrank(_VETOER_1);
        escrow.withdrawETH();
        escrow.withdrawETH(unstETHIdsVetoer1);
        vm.stopPrank();
    }

    function testFork_markUnstETHFinalized_RevertOn_HugeRebaseAtTheEndOfVetoSignallingDeactivation() external {
        uint256[] memory unstETHIds;
        uint256 totalLockedUnstETHAmount;

        _step("1. Lock ~10% of TVL in unstETH token in the Signalling Escrow");
        {
            _setupStETHBalance(_VETOER_1, PercentsD16.fromBasisPoints(1_50));

            uint256 requestAmount = _lido.withdrawalQueue.MAX_STETH_WITHDRAWAL_AMOUNT();
            uint256 requestsCount = _lido.stETH.balanceOf(_VETOER_1) / requestAmount;
            totalLockedUnstETHAmount = requestAmount * requestsCount;

            uint256[] memory amounts = new uint256[](requestsCount);

            for (uint256 i = 0; i < requestsCount; ++i) {
                amounts[i] = requestAmount;
            }

            vm.prank(_VETOER_1);
            unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

            _lockUnstETH(_VETOER_1, unstETHIds);
            _assertVetoSignalingState();

            assertTrue(_getVetoSignallingEscrow().getRageQuitSupport() >= PercentsD16.fromBasisPoints(9_00));
        }

        _step("2. VetoSignallingDeactivation state is entered");
        {
            _wait(_getVetoSignallingMaxDuration());

            _activateNextState();
            _assertVetoSignallingDeactivationState();

            _wait(_getVetoSignallingDeactivationMaxDuration().minusSeconds(12 seconds));
            _finalizeWithdrawalQueue();
            _simulateRebase(PercentsD16.fromBasisPoints(100_22));

            assertTrue(_getVetoSignallingEscrow().getRageQuitSupport() >= _getSecondSealRageQuitSupport());
        }

        _step("3. markUnstETHFinalize() reverts as system entered RageQuit state");
        {
            uint256[] memory hints =
                _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

            vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
            this.externalMarkUnstETHFinalized(unstETHIds, hints);
        }
    }

    function testFork_startRageQuitExtensionPeriod_MayBeCalledOnlyOnce() external {
        _step("1. Lock enough funds to enter RageQuit");
        {
            _lockStETH(_VETOER_1, _lido.stETH.balanceOf(_VETOER_1));
            _lockStETH(_VETOER_2, _lido.stETH.balanceOf(_VETOER_2));
            _lockWstETH(_VETOER_2, _lido.wstETH.balanceOf(_VETOER_2));

            _assertVetoSignalingState();
            assertTrue(_getCurrentRageQuitSupport() >= _getSecondSealRageQuitSupport());
        }

        _step("2. Wait full VetoSignallingDuration and enter RageQuit state");
        {
            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertRageQuitState();
        }

        uint256 batchSizeLimit = 16;
        Escrow rqEscrow = Escrow(payable(address(_getRageQuitEscrow())));
        _step("3. Requesting Withdrawal Batches");
        {
            while (!rqEscrow.isWithdrawalsBatchesClosed()) {
                rqEscrow.requestNextWithdrawalsBatch(batchSizeLimit);
            }
        }

        _step("4. Finalizing Withdrawal Batches");
        {
            _finalizeWithdrawalQueue();
        }

        _step("5. Claiming Withdrawal Batches");
        {
            while (rqEscrow.getUnclaimedUnstETHIdsCount() > 0) {
                rqEscrow.claimNextWithdrawalsBatch(batchSizeLimit);
            }
        }

        _step("6. Start Rage Quit Extension Period");
        {
            assertFalse(rqEscrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);
            assertTrue(rqEscrow.getRageQuitEscrowDetails().rageQuitExtensionPeriodStartedAt == Timestamps.ZERO);

            rqEscrow.startRageQuitExtensionPeriod();

            assertTrue(rqEscrow.getRageQuitEscrowDetails().isRageQuitExtensionPeriodStarted);
            assertTrue(rqEscrow.getRageQuitEscrowDetails().rageQuitExtensionPeriodStartedAt == Timestamps.now());
        }

        _step("7. Attempt to call startRageQuitExtensionPeriod second time fails");
        {
            vm.expectRevert(abi.encodeWithSelector(EscrowState.RageQuitExtensionPeriodAlreadyStarted.selector));
            rqEscrow.startRageQuitExtensionPeriod();
        }

        _step("8. Wait Rage Quit Extension Period has passed");
        {
            assertFalse(escrow.isRageQuitFinalized());
            _wait(_RAGE_QUIT_EXTRA_TIMELOCK.plusSeconds(1));
            assertTrue(escrow.isRageQuitFinalized());
        }

        _step("9. DG enters VetoCooldown state");
        {
            _assertRageQuitState();
            _activateNextState();
            _assertVetoCooldownState();
        }

        _step("10. Wait Rage Quit ETH Withdrawals Delay has passed");
        {
            _wait(rqEscrow.getRageQuitEscrowDetails().rageQuitEthWithdrawalsDelay.plusSeconds(1));
        }

        _step("11. Rage Quit may be successfully finalized");
        {
            vm.startPrank(_VETOER_1);
            {
                uint256 vetoer1ETHBalanceBefore = _VETOER_1.balance;
                escrow.withdrawETH();
                uint256 vetoer1ETHBalanceAfter = _VETOER_1.balance;
                assertTrue(vetoer1ETHBalanceAfter > vetoer1ETHBalanceBefore);
            }
            vm.stopPrank();

            vm.expectRevert(abi.encodeWithSelector(EscrowState.RageQuitExtensionPeriodAlreadyStarted.selector));
            rqEscrow.startRageQuitExtensionPeriod();

            vm.startPrank(_VETOER_2);
            {
                uint256 vetoer2ETHBalanceBefore = _VETOER_2.balance;
                escrow.withdrawETH();
                uint256 vetoer2ETHBalanceAfter = _VETOER_2.balance;
                assertTrue(vetoer2ETHBalanceAfter > vetoer2ETHBalanceBefore);
            }
            vm.stopPrank();
        }
    }

    function testFork_CreationAndClaimingBatchesInParallel_HappyPath() external {
        uint256 vetoer1LockedShares;
        uint256 vetoer2LockedShares;
        _step("1. Lock enough funds to enter RageQuit");
        {
            vetoer1LockedShares = _lockStETH(_VETOER_1, _lido.stETH.balanceOf(_VETOER_1));
            vetoer2LockedShares += _lockStETH(_VETOER_2, _lido.stETH.balanceOf(_VETOER_2));
            vetoer2LockedShares += _lockWstETH(_VETOER_2, _lido.wstETH.balanceOf(_VETOER_2));

            _assertVetoSignalingState();
            assertTrue(_getCurrentRageQuitSupport() >= _getSecondSealRageQuitSupport());
        }

        _step("2. Wait full VetoSignallingDuration and enter RageQuit state");
        {
            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertRageQuitState();
        }

        uint256 batchSizeLimit = 16;
        Escrow rqEscrow = Escrow(payable(address(_getRageQuitEscrow())));
        _step("3. Parallel creation and claiming of the withdrawal batches works correctly");
        {
            while (true) {
                if (!rqEscrow.isWithdrawalsBatchesClosed()) {
                    rqEscrow.requestNextWithdrawalsBatch(batchSizeLimit);
                }
                if (_lido.withdrawalQueue.getLastRequestId() > _lido.withdrawalQueue.getLastFinalizedRequestId()) {
                    _finalizeWithdrawalQueue();
                }
                if (rqEscrow.getUnclaimedUnstETHIdsCount() == 0) {
                    break;
                }
                rqEscrow.claimNextWithdrawalsBatch(batchSizeLimit);
            }

            escrow.startRageQuitExtensionPeriod();
            assertEq(escrow.isRageQuitFinalized(), false);

            _wait(_RAGE_QUIT_EXTRA_TIMELOCK.plusSeconds(1));
            assertEq(escrow.isRageQuitFinalized(), true);
        }

        _step("4. Vetoers withdraw locked stETH and wstETH as ETH after withdraw timelock");
        {
            Escrow.SignallingEscrowDetails memory escrowDetails = rqEscrow.getSignallingEscrowDetails();
            Escrow.VetoerDetails memory vetoer1Details = rqEscrow.getVetoerDetails(_VETOER_1);
            Escrow.VetoerDetails memory vetoer2Details = rqEscrow.getVetoerDetails(_VETOER_2);

            assertEq(
                vetoer1Details.stETHLockedShares + vetoer2Details.stETHLockedShares,
                escrowDetails.totalStETHLockedShares
            );

            assertEq(vetoer1LockedShares, vetoer1Details.stETHLockedShares.toUint256());
            assertEq(vetoer2LockedShares, vetoer2Details.stETHLockedShares.toUint256());

            _wait(rqEscrow.getRageQuitEscrowDetails().rageQuitEthWithdrawalsDelay.plusSeconds(1));

            vm.startPrank(_VETOER_1);
            {
                uint256 vetoer1ETHBalanceBefore = _VETOER_1.balance;
                escrow.withdrawETH();
                uint256 vetoer1ETHBalanceAfter = _VETOER_1.balance;
                uint256 expectedWithdraw = escrowDetails.totalStETHClaimedETH.toUint256()
                    * vetoer1Details.stETHLockedShares.toUint256() / escrowDetails.totalStETHLockedShares.toUint256();
                assertApproxEqAbs(
                    vetoer1ETHBalanceAfter - vetoer1ETHBalanceBefore, expectedWithdraw, ST_ETH_TRANSFER_EPSILON
                );
            }
            vm.stopPrank();

            vm.startPrank(_VETOER_2);
            {
                uint256 vetoer2ETHBalanceBefore = _VETOER_2.balance;
                escrow.withdrawETH();
                uint256 vetoer2ETHBalanceAfter = _VETOER_2.balance;
                uint256 expectedWithdraw = escrowDetails.totalStETHClaimedETH.toUint256()
                    * vetoer2Details.stETHLockedShares.toUint256() / escrowDetails.totalStETHLockedShares.toUint256();
                assertApproxEqAbs(
                    vetoer2ETHBalanceAfter - vetoer2ETHBalanceBefore, expectedWithdraw, ST_ETH_TRANSFER_EPSILON
                );
            }
            vm.stopPrank();
        }
    }

    function testFork_VetoSignallingFlashLoan_RevertOn_SameAddress() external {
        FlashLoanStub flashLoanStub;
        FlashLoanReceiver flashLoanReceiver;

        _step("0. Deploy and set up FlashLoanStub contract");
        {
            flashLoanStub = new FlashLoanStub();
            flashLoanReceiver = new FlashLoanReceiver(address(_lido.stETH));

            _setupStETHBalance(address(flashLoanStub), _getSecondSealRageQuitSupport());

            // Receiver should have some stETH to pay fee for FlashLoan
            _setupStETHBalance(address(flashLoanReceiver), 100 ether);
        }

        _step(
            "1. An attempt to lock and unlock stETH in the Escrow during the FlashLoan reverts with MinAssetsLockDurationNotPassed error"
        );
        {
            _assertNormalState();

            // amount of stETH required to trigger VetoSignalling state change
            uint256 flashLoanAmount =
                _lido.calcAmountToDepositFromPercentageOfTVL(_getFirstSealRageQuitSupport()) + 1 gwei;
            uint256 flashLoanFeeAmount = flashLoanStub.calcFlashLoanFee(flashLoanAmount);

            ISignallingEscrow signallingEscrow = _getVetoSignallingEscrow();
            Timestamp assetsLockDurationExpiresAt = _getMinAssetsLockDuration().addTo(Timestamps.now());
            vm.expectRevert(
                abi.encodeWithSelector(
                    AssetsAccounting.MinAssetsLockDurationNotPassed.selector, (assetsLockDurationExpiresAt)
                )
            );
            flashLoanStub.flashLoanSimple({
                receiverAddress: address(flashLoanReceiver),
                asset: address(_lido.stETH),
                amount: flashLoanAmount + flashLoanFeeAmount,
                params: abi.encodeCall(flashLoanReceiver.lockUnlockInTheEscrowByOneActor, (signallingEscrow))
            });

            _assertNormalState();
        }
    }

    function testFork_VetoSignallingFlashLoan_HappyPath_MultipleAddresses() external {
        FlashLoanStub flashLoanStub;
        FlashLoanReceiver flashLoanReceiver;
        ISignallingEscrow signallingEscrow = _getVetoSignallingEscrow();

        _step("0. Deploy and set up FlashLoanStub contract");
        {
            flashLoanStub = new FlashLoanStub();
            flashLoanReceiver = new FlashLoanReceiver(address(_lido.stETH));

            _setupStETHBalance(address(flashLoanStub), _getSecondSealRageQuitSupport());
        }

        PercentD16 halfOfFirstSealRageQuitSupport = PercentsD16.from(_getFirstSealRageQuitSupport().toUint256() / 2);
        _step("1. Lock half of the first seal threshold in the Signalling Escrow by escrowActor1");
        {
            // add some extra stETH to the actor1 to pay flash loan fee later
            _setupStETHBalance(
                address(flashLoanReceiver.actor1()), halfOfFirstSealRageQuitSupport + PercentsD16.fromBasisPoints(10)
            );

            flashLoanReceiver.actor1().lockStETH(signallingEscrow);
        }

        _step("2. Wait minAssetsLockDuration before unlock funds during FlashLoan");
        {
            _wait(_getMinAssetsLockDuration().plusSeconds(1));
        }

        _step(
            "3. Use FlashLoan to lock half of the VetoSignalling threshold by escrowActor2 and unlock by escrowActor1"
        );
        {
            _assertNormalState();

            // amount of stETH required to trigger VetoSignalling state change
            uint256 flashLoanAmount = _lido.calcAmountToDepositFromPercentageOfTVL(halfOfFirstSealRageQuitSupport);
            uint256 flashLoanFeeAmount = flashLoanStub.calcFlashLoanFee(flashLoanAmount);

            flashLoanStub.flashLoanSimple({
                receiverAddress: address(flashLoanReceiver),
                asset: address(_lido.stETH),
                amount: flashLoanAmount + flashLoanFeeAmount,
                params: abi.encodeCall(flashLoanReceiver.lockUnlockInTheEscrowByTwoActors, (signallingEscrow))
            });
        }

        _step("3. After FlashLoan rageQuitSupport < firstSealRageQuitSupport");
        {
            assertTrue(_getCurrentRageQuitSupport() < _getFirstSealRageQuitSupport());
        }

        _step(
            "4. But system entered VetoSignalling state for minVetoSignallingDuration and then VetoSignallingDeactivation"
        );
        {
            _assertVetoSignalingState();
            _wait(_getVetoSignallingMinActiveDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoSignallingDeactivationState();
        }
    }

    // ---
    // Helper external methods to test reverts
    // ---

    function externalLockUnstETH(address vetoer, uint256[] memory unstETHIds) external {
        _lockUnstETH(vetoer, unstETHIds);
    }

    function externalLockStETH(address vetoer, uint256 stEthAmount) external {
        _lockStETH(vetoer, stEthAmount);
    }

    function externalLockWstETH(address vetoer, uint256 wstEthAmount) external {
        _lockWstETH(vetoer, wstEthAmount);
    }

    function externalUnlockStETH(address vetoer) external {
        _unlockStETH(vetoer);
    }

    function externalUnlockWstETH(address vetoer) external {
        _unlockWstETH(vetoer);
    }

    function externalUnlockUnstETH(address vetoer, uint256[] memory nftIds) external {
        _unlockUnstETH(vetoer, nftIds);
    }

    function externalMarkUnstETHFinalized(uint256[] memory unstETHIds, uint256[] memory hints) external {
        _getVetoSignallingEscrow().markUnstETHFinalized(unstETHIds, hints);
    }
}

contract FlashLoanStub {
    PercentD16 public immutable FLASH_LOAN_FEE = PercentsD16.fromBasisPoints(5); // 0.05%

    function flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes calldata params) external {
        IERC20(asset).transfer(receiverAddress, amount);
        Address.functionCall(receiverAddress, params);
        IERC20(asset).transferFrom(receiverAddress, address(this), amount + calcFlashLoanFee(amount));
    }

    function calcFlashLoanFee(uint256 flashLoanAmount) public view returns (uint256) {
        return FLASH_LOAN_FEE.toUint256() * flashLoanAmount / HUNDRED_PERCENT_D16;
    }
}

contract FlashLoanReceiver {
    IERC20 public immutable ST_ETH;

    EscrowActor public actor1;
    EscrowActor public actor2;

    constructor(address stETH) {
        ST_ETH = IERC20(stETH);
        actor1 = new EscrowActor(stETH);
        actor2 = new EscrowActor(stETH);
    }

    function lockUnlockInTheEscrowByOneActor(ISignallingEscrow escrow) external {
        ST_ETH.approve(msg.sender, type(uint256).max);
        ST_ETH.transfer(address(actor1), ST_ETH.balanceOf(address(this)));

        actor1.lockStETH(escrow);
        actor1.unlockStETH(escrow);
    }

    function lockUnlockInTheEscrowByTwoActors(ISignallingEscrow escrow) external {
        ST_ETH.approve(msg.sender, type(uint256).max);
        ST_ETH.transfer(address(actor2), ST_ETH.balanceOf(address(this)));

        actor2.lockStETH(escrow);
        actor1.unlockStETH(escrow);
    }
}

contract EscrowActor {
    IERC20 public immutable ST_ETH;

    constructor(address stETH) {
        ST_ETH = IERC20(stETH);
    }

    function lockStETH(ISignallingEscrow escrow) external {
        ST_ETH.approve(address(escrow), type(uint256).max);
        escrow.lockStETH(ST_ETH.balanceOf(address(this)));
    }

    function unlockStETH(ISignallingEscrow escrow) external {
        escrow.unlockStETH();
        ST_ETH.transfer(msg.sender, ST_ETH.balanceOf(address(this)));
    }
}
