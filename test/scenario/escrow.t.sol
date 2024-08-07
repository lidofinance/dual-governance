// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {WithdrawalRequestStatus} from "contracts/interfaces/IWithdrawalQueue.sol";

import {EscrowState, State} from "contracts/libraries/EscrowState.sol";

import {Escrow, VetoerState, LockedAssetsTotals} from "contracts/Escrow.sol";

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
        uint256 totalAmountLocked = 2 ether;
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1 ether;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        uint256 totalSharesLocked;
        WithdrawalRequestStatus[] memory statuses = _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            totalSharesLocked += statuses[i].amountOfShares;
        }

        _lockUnstETH(_VETOER_1, unstETHIds);

        VetoerState memory vetoerState = escrow.getVetoerState(_VETOER_1);
        assertEq(vetoerState.unstETHIdsCount, 2);

        LockedAssetsTotals memory totals = escrow.getLockedAssetsTotals();
        assertEq(totals.unstETHFinalizedETH, 0);
        assertEq(totals.unstETHUnfinalizedShares, totalSharesLocked);

        _finalizeWithdrawalQueue(unstETHIds[0]);
        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());
        escrow.markUnstETHFinalized(unstETHIds, hints);

        totals = escrow.getLockedAssetsTotals();
        assertEq(totals.unstETHUnfinalizedShares, statuses[0].amountOfShares);
        uint256 ethAmountFinalized = _lido.withdrawalQueue.getClaimableEther(unstETHIds, hints)[0];
        assertApproxEqAbs(totals.unstETHFinalizedETH, ethAmountFinalized, 1);
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
        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).stETHLockedShares, 2 * sharesToLock, 2);
        assertEq(escrow.getVetoerState(_VETOER_1).unstETHIdsCount, 2);

        assertEq(escrow.getRageQuitSupport(), PercentsD16.fromFraction({numerator: 4 ether, denominator: totalSupply}));

        _finalizeWithdrawalQueue(unstETHIds[0]);
        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());
        escrow.markUnstETHFinalized(unstETHIds, hints);

        assertEq(escrow.getLockedAssetsTotals().unstETHUnfinalizedShares, sharesToLock);

        uint256 ethAmountFinalized = _lido.withdrawalQueue.getClaimableEther(unstETHIds, hints)[0];
        assertApproxEqAbs(escrow.getLockedAssetsTotals().unstETHFinalizedETH, ethAmountFinalized, 1);

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
        uint256 expectedWithdrawalBatchesCount = escrowStETHBalance / requestAmount + 1;
        assertEq(_lido.withdrawalQueue.balanceOf(address(escrow)), 10);

        escrow.requestNextWithdrawalsBatch(10);

        assertEq(_lido.withdrawalQueue.balanceOf(address(escrow)), 20);

        while (!escrow.isWithdrawalsBatchesFinalized()) {
            escrow.requestNextWithdrawalsBatch(96);
        }

        assertEq(_lido.withdrawalQueue.balanceOf(address(escrow)), 10 + expectedWithdrawalBatchesCount);
        assertEq(escrow.isRageQuitFinalized(), false);

        _finalizeWithdrawalQueue();

        uint256[] memory unstETHIdsToClaim = escrow.getNextWithdrawalBatch(expectedWithdrawalBatchesCount);
        // assertEq(total, expectedWithdrawalBatchesCount);

        WithdrawalRequestStatus[] memory statuses = _lido.withdrawalQueue.getWithdrawalStatus(unstETHIdsToClaim);

        for (uint256 i = 0; i < statuses.length; ++i) {
            assertTrue(statuses[i].isFinalized);
            assertFalse(statuses[i].isClaimed);
        }

        uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
            unstETHIdsToClaim, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );

        while (!escrow.isWithdrawalsClaimed()) {
            escrow.claimNextWithdrawalsBatch(32);
        }

        assertEq(escrow.isRageQuitFinalized(), false);

        // ---
        // unstETH holders claim their withdrawal requests
        // ---
        {
            uint256[] memory hints =
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

        escrow.claimNextWithdrawalsBatch(0, new uint256[](0));

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

    function test_request_st_eth_wst_eth_withdrawals() external {
        uint256 firstVetoerStETHAmount = 10 ether;
        uint256 firstVetoerWstETHAmount = 11 ether;

        uint256 firstVetoerStETHShares = _lido.stETH.getSharesByPooledEth(firstVetoerStETHAmount);
        uint256 totalSharesLocked = firstVetoerWstETHAmount + firstVetoerStETHShares;

        _lockStETH(_VETOER_1, firstVetoerStETHAmount);
        assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).stETHLockedShares, firstVetoerStETHShares, 1);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().stETHLockedShares, firstVetoerStETHShares, 1);

        _lockWstETH(_VETOER_1, firstVetoerWstETHAmount);
        assertApproxEqAbs(
            escrow.getVetoerState(_VETOER_1).stETHLockedShares, firstVetoerWstETHAmount + firstVetoerStETHShares, 2
        );
        assertApproxEqAbs(escrow.getLockedAssetsTotals().stETHLockedShares, totalSharesLocked, 2);

        _wait(_dualGovernanceConfigProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        uint256[] memory stETHWithdrawalRequestAmounts = new uint256[](1);
        stETHWithdrawalRequestAmounts[0] = firstVetoerStETHAmount;

        vm.prank(_VETOER_1);
        uint256[] memory stETHWithdrawalRequestIds = escrow.requestWithdrawals(stETHWithdrawalRequestAmounts);

        assertApproxEqAbs(escrow.getLockedAssetsTotals().stETHLockedShares, firstVetoerWstETHAmount, 2);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().unstETHUnfinalizedShares, firstVetoerStETHShares, 2);

        uint256[] memory wstETHWithdrawalRequestAmounts = new uint256[](1);
        wstETHWithdrawalRequestAmounts[0] = _lido.stETH.getPooledEthByShares(firstVetoerWstETHAmount);

        vm.prank(_VETOER_1);
        uint256[] memory wstETHWithdrawalRequestIds = escrow.requestWithdrawals(wstETHWithdrawalRequestAmounts);

        assertApproxEqAbs(escrow.getLockedAssetsTotals().stETHLockedShares, 0, 2);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().unstETHUnfinalizedShares, totalSharesLocked, 2);

        _finalizeWithdrawalQueue(wstETHWithdrawalRequestIds[0]);

        escrow.markUnstETHFinalized(
            stETHWithdrawalRequestIds,
            _lido.withdrawalQueue.findCheckpointHints(
                stETHWithdrawalRequestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
            )
        );
        assertApproxEqAbs(escrow.getLockedAssetsTotals().stETHLockedShares, 0, 2);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().unstETHUnfinalizedShares, firstVetoerWstETHAmount, 2);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().unstETHFinalizedETH, firstVetoerStETHAmount, 2);

        escrow.markUnstETHFinalized(
            wstETHWithdrawalRequestIds,
            _lido.withdrawalQueue.findCheckpointHints(
                wstETHWithdrawalRequestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
            )
        );
        assertApproxEqAbs(escrow.getLockedAssetsTotals().stETHLockedShares, 0, 2);
        assertApproxEqAbs(escrow.getLockedAssetsTotals().unstETHUnfinalizedShares, 0, 2);

        _wait(_dualGovernanceConfigProvider.MIN_ASSETS_LOCK_DURATION().plusSeconds(1));

        vm.prank(_VETOER_1);
        escrow.unlockUnstETH(stETHWithdrawalRequestIds);

        // // assertApproxEqAbs(escrow.getVetoerState(_VETOER_1).unstETHShares, firstVetoerWstETHAmount, 1);
        // assertApproxEqAbs(escrow.getLockedAssetsTotals().stETHLockedShares, firstVetoerWstETHAmount, 1);

        vm.prank(_VETOER_1);
        escrow.unlockUnstETH(wstETHWithdrawalRequestIds);
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

        vm.expectRevert(abi.encodeWithSelector(EscrowState.InvalidState.selector, State.SignallingEscrow));
        this.externalLockStETH(_VETOER_1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.InvalidState.selector, State.SignallingEscrow));
        this.externalLockWstETH(_VETOER_1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.InvalidState.selector, State.SignallingEscrow));
        this.externalLockUnstETH(_VETOER_1, notLockedWithdrawalNfts);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.InvalidState.selector, State.SignallingEscrow));
        this.externalUnlockStETH(_VETOER_1);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.InvalidState.selector, State.SignallingEscrow));
        this.externalUnlockWstETH(_VETOER_1);

        vm.expectRevert(abi.encodeWithSelector(EscrowState.InvalidState.selector, State.SignallingEscrow));
        this.externalUnlockUnstETH(_VETOER_1, lockedWithdrawalNfts);
    }

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
