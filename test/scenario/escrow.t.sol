// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";

import {EscrowState, State} from "contracts/libraries/EscrowState.sol";
import {WithdrawalsBatchesQueue} from "contracts/libraries/WithdrawalsBatchesQueue.sol";
import {AssetsAccounting, UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";

import {Escrow} from "contracts/Escrow.sol";

import {ScenarioTestBlueprint, LidoUtils, console} from "../utils/scenario-test-blueprint.sol";

contract EscrowHappyPath is ScenarioTestBlueprint {
    using LidoUtils for LidoUtils.Context;

    Escrow internal escrow;

    Duration internal immutable _RAGE_QUIT_EXTRA_TIMELOCK = Durations.from(14 days);
    Duration internal immutable _RAGE_QUIT_WITHDRAWALS_TIMELOCK = Durations.from(7 days);

    address internal immutable _VETOER_1 = makeAddr("VETOER_1");
    address internal immutable _VETOER_2 = makeAddr("VETOER_2");

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});

        escrow = _getVetoSignallingEscrow();

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

        _lido.wstETH.wrap(100_000 * 10 ** 18);
        vm.stopPrank();
    }

    function test_lock_unlock() public {
        uint256 firstVetoerStETHBalanceBefore = _lido.stETH.balanceOf(_VETOER_1);
        uint256 secondVetoerWstETHBalanceBefore = _lido.wstETH.balanceOf(_VETOER_2);

        uint256 firstVetoerLockStETHAmount = 1 ether;
        uint256 firstVetoerLockWstETHAmount = 2 ether;

        uint256 secondVetoerLockStETHAmount = 3 ether;
        uint256 secondVetoerLockWstETHAmount = 5 ether;

        _lockStETH(_VETOER_1, firstVetoerLockStETHAmount);
        _lockWstETH(_VETOER_1, firstVetoerLockWstETHAmount);

        _lockStETH(_VETOER_2, secondVetoerLockStETHAmount);
        _lockWstETH(_VETOER_2, secondVetoerLockWstETHAmount);

        _wait(_dualGovernanceConfigProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        _unlockStETH(_VETOER_1);
        assertApproxEqAbs(
            _lido.stETH.balanceOf(_VETOER_1),
            firstVetoerStETHBalanceBefore + _lido.stETH.getPooledEthByShares(firstVetoerLockWstETHAmount),
            1
        );

        _unlockWstETH(_VETOER_2);
        assertApproxEqAbs(
            secondVetoerWstETHBalanceBefore,
            _lido.wstETH.balanceOf(_VETOER_2),
            secondVetoerWstETHBalanceBefore + _lido.stETH.getSharesByPooledEth(secondVetoerLockWstETHAmount)
        );
    }

    function test_lock_unlock_w_rebase() public {
        uint256 firstVetoerStETHAmount = 10 * 10 ** 18;
        uint256 firstVetoerStETHShares = _lido.stETH.getSharesByPooledEth(firstVetoerStETHAmount);
        uint256 firstVetoerWstETHAmount = 11 * 10 ** 18;

        uint256 secondVetoerStETHAmount = 13 * 10 ** 18;
        uint256 secondVetoerWstETHAmount = 17 * 10 ** 18;

        uint256 firstVetoerWstETHBalanceBefore = _lido.wstETH.balanceOf(_VETOER_1);
        uint256 secondVetoerStETHSharesBefore = _lido.stETH.sharesOf(_VETOER_2);

        _lockStETH(_VETOER_1, firstVetoerStETHAmount);
        _lockWstETH(_VETOER_1, firstVetoerWstETHAmount);

        _lockStETH(_VETOER_2, secondVetoerStETHAmount);
        _lockWstETH(_VETOER_2, secondVetoerWstETHAmount);

        _simulateRebase(PercentsD16.fromBasisPoints(101_00)); // +1%

        _wait(_dualGovernanceConfigProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        _unlockWstETH(_VETOER_1);
        assertApproxEqAbs(
            firstVetoerWstETHBalanceBefore + firstVetoerStETHShares,
            _lido.wstETH.balanceOf(_VETOER_1),
            // Even though the wstETH itself doesn't have rounding issues, the Escrow contract wraps stETH into wstETH
            // so the the rounding issue may happen because of it. Another rounding may happen on the converting stETH amount
            // into shares via _lido.stETH.getSharesByPooledEth(secondVetoerStETHAmount)
            2
        );

        _unlockStETH(_VETOER_2);

        assertApproxEqAbs(
            // all locked stETH and wstETH was withdrawn as stETH
            _lido.stETH.getPooledEthByShares(secondVetoerStETHSharesBefore + secondVetoerWstETHAmount),
            _lido.stETH.balanceOf(_VETOER_2),
            // Considering that during the previous operation 2 wei may be lost, total rounding error may be 3 wei
            3
        );
    }

    function test_lock_unlock_w_negative_rebase() public {
        uint256 firstVetoerStETHAmount = 10 * 10 ** 18;
        uint256 firstVetoerWstETHAmount = 11 * 10 ** 18;

        uint256 secondVetoerStETHAmount = 13 * 10 ** 18;
        uint256 secondVetoerWstETHAmount = 17 * 10 ** 18;
        uint256 secondVetoerStETHShares = _lido.stETH.getSharesByPooledEth(secondVetoerStETHAmount);

        uint256 firstVetoerStETHSharesBefore = _lido.stETH.sharesOf(_VETOER_1);
        uint256 secondVetoerWstETHBalanceBefore = _lido.wstETH.balanceOf(_VETOER_2);

        _lockStETH(_VETOER_1, firstVetoerStETHAmount);
        _lockWstETH(_VETOER_1, firstVetoerWstETHAmount);

        _lockStETH(_VETOER_2, secondVetoerStETHAmount);
        _lockWstETH(_VETOER_2, secondVetoerWstETHAmount);

        _simulateRebase(PercentsD16.fromBasisPoints(99_00)); // -1%

        _wait(_dualGovernanceConfigProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        _unlockStETH(_VETOER_1);
        assertApproxEqAbs(
            // all locked stETH and wstETH was withdrawn as stETH
            _lido.stETH.getPooledEthByShares(firstVetoerStETHSharesBefore + firstVetoerWstETHAmount),
            _lido.stETH.balanceOf(_VETOER_1),
            1
        );

        _unlockWstETH(_VETOER_2);

        assertApproxEqAbs(
            secondVetoerWstETHBalanceBefore + secondVetoerStETHShares,
            _lido.wstETH.balanceOf(_VETOER_2),
            // Even though the wstETH itself doesn't have rounding issues, the Escrow contract wraps stETH into wstETH
            // so the the rounding issue may happen because of it. Another rounding may happen on the converting stETH amount
            // into shares via _lido.stETH.getSharesByPooledEth(secondVetoerStETHAmount)
            2
        );
    }

    function test_lock_unlock_withdrawal_nfts() public {
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        _lockUnstETH(_VETOER_1, unstETHIds);

        _wait(_dualGovernanceConfigProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        _unlockUnstETH(_VETOER_1, unstETHIds);
    }

    function test_lock_withdrawal_nfts_reverts_on_finalized() public {
        uint256[] memory amounts = new uint256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        _finalizeWithdrawalQueue();

        vm.expectRevert();
        this.externalLockUnstETH(_VETOER_1, unstETHIds);
    }

    function test_check_finalization() public {
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1 ether;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        uint256 totalSharesLocked;
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            totalSharesLocked += statuses[i].amountOfShares;
        }

        _lockUnstETH(_VETOER_1, unstETHIds);

        Escrow.VetoerDetails memory vetoerDetails = escrow.getVetoerDetails(_VETOER_1);
        assertEq(vetoerDetails.unstETHIdsCount, 2);

        ISignallingEscrow.SignallingEscrowDetails memory escrowDetails = escrow.getSignallingEscrowDetails();
        assertEq(escrowDetails.totalUnstETHFinalizedETH.toUint256(), 0);
        assertEq(escrowDetails.totalUnstETHUnfinalizedShares.toUint256(), totalSharesLocked);

        _finalizeWithdrawalQueue(unstETHIds[0]);
        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());
        escrow.markUnstETHFinalized(unstETHIds, hints);

        escrowDetails = escrow.getSignallingEscrowDetails();
        assertEq(escrowDetails.totalUnstETHUnfinalizedShares.toUint256(), statuses[0].amountOfShares);
        uint256 ethAmountFinalized = _lido.withdrawalQueue.getClaimableEther(unstETHIds, hints)[0];
        assertApproxEqAbs(escrowDetails.totalUnstETHFinalizedETH.toUint256(), ethAmountFinalized, 1);
    }

    function test_get_rage_quit_support() public {
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        uint256 amountToLock = 1e18;
        uint256 sharesToLock = _lido.stETH.getSharesByPooledEth(amountToLock);

        _lockStETH(_VETOER_1, amountToLock);
        _lockWstETH(_VETOER_1, sharesToLock);
        _lockUnstETH(_VETOER_1, unstETHIds);

        uint256 totalSupply = _lido.stETH.totalSupply();

        // epsilon is 2 here, because the wstETH unwrap may produce 1 wei error and stETH transfer 1 wei
        assertApproxEqAbs(escrow.getVetoerDetails(_VETOER_1).stETHLockedShares.toUint256(), 2 * sharesToLock, 2);
        assertEq(escrow.getVetoerDetails(_VETOER_1).unstETHIdsCount, 2);

        assertEq(escrow.getRageQuitSupport(), PercentsD16.fromFraction({numerator: 4 ether, denominator: totalSupply}));

        _finalizeWithdrawalQueue(unstETHIds[0]);
        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());
        escrow.markUnstETHFinalized(unstETHIds, hints);

        assertEq(escrow.getSignallingEscrowDetails().totalUnstETHUnfinalizedShares.toUint256(), sharesToLock);

        uint256 ethAmountFinalized = _lido.withdrawalQueue.getClaimableEther(unstETHIds, hints)[0];
        assertApproxEqAbs(
            escrow.getSignallingEscrowDetails().totalUnstETHFinalizedETH.toUint256(), ethAmountFinalized, 1
        );

        assertEq(
            escrow.getRageQuitSupport(),
            PercentsD16.fromFraction({
                numerator: _lido.stETH.getPooledEthByShares(3 * sharesToLock) + ethAmountFinalized,
                denominator: _lido.stETH.totalSupply() + ethAmountFinalized
            })
        );
    }

    function test_rage_quit() public {
        uint256 requestAmount = 1000 * 1e18;
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            amounts[i] = requestAmount;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        uint256 requestShares = _lido.stETH.getSharesByPooledEth(30 * requestAmount);

        _lockStETH(_VETOER_1, 20 * requestAmount);
        _lockWstETH(_VETOER_1, requestShares);
        _lockUnstETH(_VETOER_1, unstETHIds);

        _simulateRebase(PercentsD16.fromBasisPoints(101_00)); // +1%

        vm.expectRevert();
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        vm.prank(address(_dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        uint256 escrowStETHBalance = _lido.stETH.balanceOf(address(escrow));
        uint256 expectedWithdrawalsBatchesCount = escrowStETHBalance / requestAmount + 1;
        assertEq(_lido.withdrawalQueue.balanceOf(address(escrow)), 10);

        escrow.requestNextWithdrawalsBatch(10);

        assertEq(_lido.withdrawalQueue.balanceOf(address(escrow)), 20);

        while (!escrow.isWithdrawalsBatchesClosed()) {
            escrow.requestNextWithdrawalsBatch(96);
        }

        assertEq(_lido.withdrawalQueue.balanceOf(address(escrow)), 10 + expectedWithdrawalsBatchesCount);
        assertEq(escrow.isRageQuitFinalized(), false);

        _finalizeWithdrawalQueue();

        uint256[] memory unstETHIdsToClaim = escrow.getNextWithdrawalBatch(expectedWithdrawalsBatchesCount);
        // assertEq(total, expectedWithdrawalsBatchesCount);

        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            _lido.withdrawalQueue.getWithdrawalStatus(unstETHIdsToClaim);

        for (uint256 i = 0; i < statuses.length; ++i) {
            assertTrue(statuses[i].isFinalized);
            assertFalse(statuses[i].isClaimed);
        }

        uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
            unstETHIdsToClaim, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );

        while (escrow.getUnclaimedUnstETHIdsCount() > 0) {
            escrow.claimNextWithdrawalsBatch(32);
        }

        escrow.startRageQuitExtensionPeriod();
        assertEq(escrow.isRageQuitFinalized(), false);

        // ---
        // unstETH holders claim their withdrawal requests
        // ---
        {
            hints =
                _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());
            escrow.claimUnstETH(unstETHIds, hints);

            // but it can't be withdrawn before withdrawal timelock has passed
            vm.expectRevert();
            vm.prank(_VETOER_1);
            escrow.withdrawETH(unstETHIds);
        }

        vm.expectRevert();
        vm.prank(_VETOER_1);
        escrow.withdrawETH();

        _wait(_RAGE_QUIT_EXTRA_TIMELOCK.plusSeconds(1));
        assertEq(escrow.isRageQuitFinalized(), true);

        _wait(_RAGE_QUIT_WITHDRAWALS_TIMELOCK.plusSeconds(1));

        vm.startPrank(_VETOER_1);
        escrow.withdrawETH();
        escrow.withdrawETH(unstETHIds);
        vm.stopPrank();
    }

    function test_wq_requests_only_happy_path() public {
        uint256 requestAmount = 10 * 1e18;
        uint256 requestsCount = 10;
        uint256[] memory amounts = new uint256[](requestsCount);
        for (uint256 i = 0; i < requestsCount; ++i) {
            amounts[i] = requestAmount;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        _lockUnstETH(_VETOER_1, unstETHIds);

        vm.prank(address(_dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        _finalizeWithdrawalQueue();

        escrow.requestNextWithdrawalsBatch(96);

        vm.expectRevert(WithdrawalsBatchesQueue.EmptyBatch.selector);
        escrow.claimNextWithdrawalsBatch(0, new uint256[](0));

        escrow.startRageQuitExtensionPeriod();

        assertEq(escrow.isRageQuitFinalized(), false);

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

    function test_wq_requests_onlyUnstETHWithUnfinalizedRequestsFails() external {
        uint256 requestAmount = 10 * 1e18;
        uint256 requestsCount = 10;
        uint256[] memory amounts = new uint256[](requestsCount);
        for (uint256 i = 0; i < requestsCount; ++i) {
            amounts[i] = requestAmount;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        _lockUnstETH(_VETOER_1, unstETHIds);

        vm.prank(address(_dualGovernance));
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

    function test_lock_unlock_funds_in_the_rage_quit_state_forbidden() external {
        uint256[] memory nftAmounts = new uint256[](1);
        nftAmounts[0] = 1 ether;

        vm.startPrank(_VETOER_1);
        uint256[] memory lockedWithdrawalNfts = _lido.withdrawalQueue.requestWithdrawals(nftAmounts, _VETOER_1);
        uint256[] memory notLockedWithdrawalNfts = _lido.withdrawalQueue.requestWithdrawals(nftAmounts, _VETOER_1);
        vm.stopPrank();

        _lockStETH(_VETOER_1, 1 ether);
        _lockWstETH(_VETOER_1, 1 ether);
        _lockUnstETH(_VETOER_1, lockedWithdrawalNfts);

        vm.prank(address(_dualGovernance));
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

    // TODO: rewrite this test to use all stETH/wstETH/unstETH tokens
    function testFork_EdgeCase_FrontRunningRageQuitWithTokensUnlockForbidden() external {
        // lock enough funds to initiate RageQuit
        _lockStETH(_VETOER_1, PercentsD16.fromBasisPoints(7_99));
        _lockStETH(_VETOER_2, PercentsD16.fromBasisPoints(7_99));
        _assertVetoSignalingState();

        // wait till the last second of the dynamic timelock duration
        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION());
        _activateNextState();
        _assertVetoSignalingState();

        ( /* bool isActive */ , uint256 duration, uint256 activatedAt, /* uint256 enteredAt */ ) =
            _getVetoSignallingState();
        assertEq(duration + activatedAt, block.timestamp);

        // validate that while the VetoSignalling has not passed, vetoer can unlock funds from Escrow
        uint256 snapshotId = vm.snapshot();
        _unlockStETH(_VETOER_1);
        _assertVetoSignalingDeactivationState();

        // Rollback the state of the node before vetoer unlocked his funds
        vm.revertTo(snapshotId);

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
    }

    function testFork_EdgeCase_frontRunningClaimUnStethFromBatchIsForbidden() external {
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

        vm.prank(address(_dualGovernance));
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
}
