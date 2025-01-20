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

import {LidoUtils} from "../utils/scenario-test-blueprint.sol";

import {RegressionBase} from "../utils/regression-base.sol";

contract EscrowHappyPath is RegressionBase {
    using LidoUtils for LidoUtils.Context;

    Escrow internal escrow;

    Duration internal immutable _RAGE_QUIT_EXTRA_TIMELOCK = Durations.from(14 days);
    Duration internal immutable _RAGE_QUIT_WITHDRAWALS_TIMELOCK = Durations.from(7 days);

    address internal immutable _VETOER_1 = makeAddr("VETOER_1");
    address internal immutable _VETOER_2 = makeAddr("VETOER_2");

    function setUp() external {
        _setUpEnvironment();

        escrow = _getVetoSignallingEscrow();

        _setupStETHBalance(_VETOER_1, 200_000 * 10 ** 18);

        vm.startPrank(_VETOER_1);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        _lido.wstETH.wrap(100_000 * 10 ** 18);
        vm.stopPrank();

        _setupStETHBalance(_VETOER_2, 200_000 * 10 ** 18);

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

        _wait(escrow.getMinAssetsLockDuration().plusSeconds(1));

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

        _wait(escrow.getMinAssetsLockDuration().plusSeconds(1));

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
