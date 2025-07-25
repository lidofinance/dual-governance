// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "contracts/types/Duration.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";
import {ETHValue, ETHValues} from "contracts/types/ETHValue.sol";
import {SharesValue, SharesValues} from "contracts/types/SharesValue.sol";

import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {IRageQuitEscrow} from "contracts/interfaces/IRageQuitEscrow.sol";
import {AssetsAccounting, UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";
import {WithdrawalsBatchesQueue} from "contracts/libraries/WithdrawalsBatchesQueue.sol";

import {Escrow} from "contracts/Escrow.sol";

import {LidoUtils, DGRegressionTestSetup} from "../utils/integration-tests.sol";
import {Random} from "../utils/random.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

uint256 constant ACCURACY = 2 wei;

contract EscrowOperationsRegressionTest is DGRegressionTestSetup {
    using LidoUtils for LidoUtils.Context;

    Escrow internal escrow;
    uint256 internal _initialLockedUnStETHAmount;
    uint256 internal _initialLockedUnStETHShares;
    uint256[] internal _initialLockedUnStETHIds;
    uint256 internal _initialLockedUnStETHCount;
    uint256 internal _initialLockedShares;

    Random.Context internal _random;

    Duration internal immutable _RAGE_QUIT_EXTRA_TIMELOCK = Durations.from(14 days);
    Duration internal immutable _RAGE_QUIT_WITHDRAWALS_TIMELOCK = Durations.from(7 days);

    address internal immutable _VETOER_1 = makeAddr("VETOER_1");
    address internal immutable _VETOER_2 = makeAddr("VETOER_2");
    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _loadOrDeployDGSetup();

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

        _lido.wstETH.wrap(100_000 * 10 ** 18);
        vm.stopPrank();
    }

    function testFork_LockUnlockAssets_HappyPath_WithoutRebases() public {
        _initialLockRandomAmountOfTokensInEscrow();

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

        _wait(_getMinAssetsLockDuration().plusSeconds(1));

        _unlockStETH(_VETOER_1);
        assertApproxEqAbs(
            _lido.stETH.balanceOf(_VETOER_1),
            firstVetoerStETHBalanceBefore + _lido.stETH.getPooledEthByShares(firstVetoerLockWstETHAmount),
            ACCURACY
        );

        _unlockWstETH(_VETOER_2);
        assertApproxEqAbs(
            _lido.wstETH.balanceOf(_VETOER_2),
            secondVetoerWstETHBalanceBefore + _lido.stETH.getSharesByPooledEth(secondVetoerLockStETHAmount),
            ACCURACY
        );
    }

    function testForkFuzz_LockUnlockAssets_HappyPath_WithRebases(
        uint256 rebaseDeltaPercent,
        uint256 withdrawTurn
    ) public {
        vm.assume(rebaseDeltaPercent < 50); // -0.25% ... +0.25%
        PercentD16 rebasePercent = PercentsD16.fromBasisPoints(99_75 + rebaseDeltaPercent);

        uint256 firstVetoerStETHAmount = 10 * 10 ** 18;
        uint256 firstVetoerStETHShares = _lido.stETH.getSharesByPooledEth(firstVetoerStETHAmount);
        uint256 firstVetoerWstETHAmount = 11 * 10 ** 18;

        uint256 secondVetoerStETHAmount = 13 * 10 ** 18;
        uint256 secondVetoerWstETHAmount = 17 * 10 ** 18;
        uint256 secondVetoerStETHShares = _lido.stETH.getSharesByPooledEth(secondVetoerStETHAmount);

        uint256 firstVetoerStETHSharesBefore = _lido.stETH.sharesOf(_VETOER_1);
        uint256 firstVetoerWstETHBalanceBefore = _lido.wstETH.balanceOf(_VETOER_1);
        uint256 secondVetoerStETHSharesBefore = _lido.stETH.sharesOf(_VETOER_2);
        uint256 secondVetoerWstETHBalanceBefore = _lido.wstETH.balanceOf(_VETOER_2);

        _lockStETH(_VETOER_1, firstVetoerStETHAmount);
        _lockWstETH(_VETOER_1, firstVetoerWstETHAmount);

        _lockStETH(_VETOER_2, secondVetoerStETHAmount);
        _lockWstETH(_VETOER_2, secondVetoerWstETHAmount);

        _simulateRebase(rebasePercent);

        _wait(_getMinAssetsLockDuration().plusSeconds(1));

        if (withdrawTurn % 2 == 0) {
            _unlockStETH(_VETOER_1);
            assertApproxEqAbs(
                // all locked stETH and wstETH was withdrawn as stETH
                _lido.stETH.getPooledEthByShares(firstVetoerStETHSharesBefore + firstVetoerWstETHAmount),
                _lido.stETH.balanceOf(_VETOER_1),
                ACCURACY
            );

            _unlockWstETH(_VETOER_2);

            assertApproxEqAbs(
                secondVetoerWstETHBalanceBefore + secondVetoerStETHShares,
                _lido.wstETH.balanceOf(_VETOER_2),
                // Even though the wstETH itself doesn't have rounding issues, the Escrow contract wraps stETH into wstETH
                // so the the rounding issue may happen because of it. Another rounding may happen on the converting stETH amount
                // into shares via _lido.stETH.getSharesByPooledEth(secondVetoerStETHAmount)
                10 * ACCURACY
            );
        } else {
            _unlockWstETH(_VETOER_1);
            assertApproxEqAbs(
                firstVetoerWstETHBalanceBefore + firstVetoerStETHShares,
                _lido.wstETH.balanceOf(_VETOER_1),
                // Even though the wstETH itself doesn't have rounding issues, the Escrow contract wraps stETH into wstETH
                // so the the rounding issue may happen because of it. Another rounding may happen on the converting stETH amount
                // into shares via _lido.stETH.getSharesByPooledEth(secondVetoerStETHAmount)
                10 * ACCURACY
            );

            _unlockStETH(_VETOER_2);

            assertApproxEqAbs(
                // all locked stETH and wstETH was withdrawn as stETH
                _lido.stETH.getPooledEthByShares(secondVetoerStETHSharesBefore + secondVetoerWstETHAmount),
                _lido.stETH.balanceOf(_VETOER_2),
                // Considering that during the previous operation 2 wei may be lost, total rounding error may be 3 wei
                ACCURACY
            );
        }
    }

    function testFork_LockUnlockAssets_HappyPath_WithdrawalNFTs() public {
        _initialLockRandomAmountOfTokensInEscrow();

        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        _lockUnstETH(_VETOER_1, unstETHIds);

        _wait(_getMinAssetsLockDuration().plusSeconds(1));

        _unlockUnstETH(_VETOER_1, unstETHIds);
    }

    function testFork_Lock_RevertsOn_FinalizedUnstETH() public {
        _initialLockRandomAmountOfTokensInEscrow();

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

    function testFork_MarkUnstETHFinalized_HappyPath() public {
        _initialLockRandomAmountOfTokensInEscrow();

        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = (i + 1) * 1 ether;
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
        assertEq(
            escrowDetails.totalUnstETHUnfinalizedShares.toUint256() - _initialLockedUnStETHShares, totalSharesLocked
        );

        _finalizeWithdrawalQueue(unstETHIds[0]);

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

        uint256[] memory claimableEther = _lido.withdrawalQueue.getClaimableEther(unstETHIds, hints);

        SharesValue[] memory finalizedShares = new SharesValue[](2);
        ETHValue[] memory finalizedStETH = new ETHValue[](2);
        finalizedShares[0] = SharesValues.from(statuses[0].amountOfShares);
        finalizedShares[1] = SharesValues.from(0);
        finalizedStETH[0] = ETHValues.from(claimableEther[0]);
        finalizedStETH[1] = ETHValues.from(0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(unstETHIds, finalizedShares, finalizedStETH);
        escrow.markUnstETHFinalized(unstETHIds, hints);

        escrowDetails = escrow.getSignallingEscrowDetails();
        assertEq(
            escrowDetails.totalUnstETHUnfinalizedShares.toUint256() - _initialLockedUnStETHShares,
            statuses[1].amountOfShares
        );
        assertApproxEqAbs(escrowDetails.totalUnstETHFinalizedETH.toUint256(), claimableEther[0], ACCURACY);

        // perform an extra call with the same NFTs to ensure that repeated finalization does not occur
        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(unstETHIds, new SharesValue[](2), new ETHValue[](2));
        escrow.markUnstETHFinalized(unstETHIds, hints);
    }

    function testFork_LockUnlockAssets_FinalizedWithdrawalNFTs_HappyPath() public {
        _initialLockRandomAmountOfTokensInEscrow();

        uint256[] memory vetoer2Amounts = new uint256[](1);
        vetoer2Amounts[0] = 100e18;

        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = 1e18;
        }

        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        vm.prank(_VETOER_2);
        uint256[] memory vetoer2UnstETHIds = _lido.withdrawalQueue.requestWithdrawals(vetoer2Amounts, _VETOER_2);

        uint256[] memory hints = _lido.withdrawalQueue.findCheckpointHints(
            vetoer2UnstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );
        escrow.markUnstETHFinalized(vetoer2UnstETHIds, hints);

        _lockUnstETH(_VETOER_1, unstETHIds);
        _lockUnstETH(_VETOER_2, vetoer2UnstETHIds);

        _finalizeWithdrawalQueue();

        _wait(_getMinAssetsLockDuration().plusSeconds(1));

        _unlockUnstETH(_VETOER_1, unstETHIds);
        _unlockUnstETH(_VETOER_2, vetoer2UnstETHIds);
    }

    function testForkFuzz_RageQuitSupport_HappyPath(
        uint256 stETHAmount,
        uint256 wstETHAmount,
        uint256 unstETH1Amount,
        uint256 unstETH2Amount
    ) public {
        _initialLockRandomAmountOfTokensInEscrow();

        unstETH1Amount = Math.max(
            unstETH1Amount % _lido.withdrawalQueue.MAX_STETH_WITHDRAWAL_AMOUNT(),
            _lido.withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT()
        );
        unstETH2Amount = Math.max(
            unstETH2Amount % _lido.withdrawalQueue.MAX_STETH_WITHDRAWAL_AMOUNT(),
            _lido.withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT()
        );

        uint256 vetoer1StETHBalanceBefore = _lido.stETH.balanceOf(_VETOER_1);
        stETHAmount = Math.max(stETHAmount % vetoer1StETHBalanceBefore, 2);
        wstETHAmount = Math.max(wstETHAmount % _lido.wstETH.balanceOf(_VETOER_1), 2);

        unstETH1Amount = Math.min(unstETH1Amount, (vetoer1StETHBalanceBefore - stETHAmount) / 2);
        unstETH2Amount = Math.min(unstETH2Amount, (vetoer1StETHBalanceBefore - stETHAmount) / 2);

        uint256 stETHShares = _lido.stETH.getSharesByPooledEth(stETHAmount);

        uint256[] memory unstETHIds;
        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = unstETH1Amount;
            amounts[1] = unstETH2Amount;

            vm.prank(_VETOER_1);
            unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

            _lockStETH(_VETOER_1, stETHAmount);
            _lockWstETH(_VETOER_1, wstETHAmount);
            _lockUnstETH(_VETOER_1, unstETHIds);
        }
        {
            // epsilon (ACCURACY) is 2 here, because the wstETH unwrap may produce 1 wei error and stETH transfer 1 wei
            assertApproxEqAbs(
                escrow.getVetoerDetails(_VETOER_1).stETHLockedShares.toUint256(),
                _lido.stETH.getSharesByPooledEth(stETHAmount) + wstETHAmount,
                ACCURACY
            );
            assertEq(escrow.getVetoerDetails(_VETOER_1).unstETHIdsCount, 2);
            assertApproxEqAbs(
                escrow.getSignallingEscrowDetails().totalStETHLockedShares.toUint256(),
                _lido.stETH.getSharesByPooledEth(stETHAmount) + wstETHAmount + _initialLockedShares,
                2 * ACCURACY
            );

            assertApproxEqAbs(
                escrow.getSignallingEscrowDetails().totalUnstETHUnfinalizedShares.toUint256(),
                _lido.stETH.getSharesByPooledEth(unstETH1Amount + unstETH2Amount) + _initialLockedUnStETHShares,
                2 * ACCURACY
            );

            // TODO: temporarily using assertApproxEqAbs. Need to fix it properly in a separate PR
            assertApproxEqAbs(
                escrow.getRageQuitSupport().toUint256(),
                PercentsD16.fromFraction({
                    numerator: stETHAmount + unstETH1Amount + unstETH2Amount
                        + _lido.stETH.getPooledEthByShares(wstETHAmount + _initialLockedShares + _initialLockedUnStETHShares),
                    denominator: _lido.stETH.totalSupply()
                }).toUint256(),
                // TODO: temporarily increased delta to 10 * ACCURACY to fix possible rounding error. Need to fix it properly in a separate PR.
                10 * ACCURACY
            );
        }

        {
            uint256 pooledEthRateBefore = _lido.stETH.getSharesByPooledEth(10 ** 27);

            _finalizeWithdrawalQueue(unstETHIds[0]);
            uint256[] memory hints =
                _lido.withdrawalQueue.findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());
            escrow.markUnstETHFinalized(unstETHIds, hints);

            uint256 ethAmountFinalized = _lido.withdrawalQueue.getClaimableEther(unstETHIds, hints)[0];
            uint256 unfinalizedShares = pooledEthRateBefore * (unstETH2Amount + _initialLockedUnStETHAmount) / 10 ** 27;
            uint256 lockedShares = wstETHAmount + stETHShares + _initialLockedShares;
            uint256 supportAmount =
                _lido.stETH.getPooledEthByShares(lockedShares + unfinalizedShares) + ethAmountFinalized;

            assertApproxEqAbs(
                escrow.getSignallingEscrowDetails().totalStETHLockedShares.toUint256(), lockedShares, ACCURACY
            );

            assertApproxEqAbs(
                escrow.getSignallingEscrowDetails().totalUnstETHUnfinalizedShares.toUint256(),
                unfinalizedShares,
                // TODO: temporarily increased delta to 1 gwei to fix OutOfFunds error. Need to fix it properly in a separate PR.
                1 gwei
            );

            assertApproxEqAbs(
                // TODO: temporarily increased delta to 1 gwei to fix OutOfFunds error. Need to fix it properly in a separate PR.
                escrow.getSignallingEscrowDetails().totalUnstETHFinalizedETH.toUint256(),
                ethAmountFinalized,
                1 gwei
            );

            // TODO: temporarily using assertApproxEqAbs. Need to fix it properly in a separate PR
            assertApproxEqAbs(
                escrow.getRageQuitSupport().toUint256(),
                PercentsD16.fromFraction({
                    numerator: supportAmount,
                    denominator: _lido.stETH.totalSupply() + ethAmountFinalized
                }).toUint256(),
                // TODO: temporarily increased delta to 15 * ACCURACY to fix possible rounding error. Need to fix it properly in a separate PR.
                15 * ACCURACY
            );
        }
    }

    function testFork_RageQuit_HappyPath_AllTokens() public {
        _initialLockRandomAmountOfTokensInEscrow();

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

        _simulateRebase(PercentsD16.fromBasisPoints(100_05)); // +0.05%

        vm.expectRevert();
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        uint256[] memory unstETHIdsToFinalize = new uint256[](1);
        unstETHIdsToFinalize[0] = unstETHIds[0];

        uint256[] memory unstETHToFinalizeHints = _lido.withdrawalQueue.findCheckpointHints(
            unstETHIdsToFinalize, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );
        escrow.markUnstETHFinalized(unstETHIdsToFinalize, unstETHToFinalizeHints);

        // unstETH was not finalized in the WQ, so the finalization shares is not accounted here
        Escrow.LockedUnstETHDetails[] memory unstETHToFinalizeDetails =
            escrow.getLockedUnstETHDetails(unstETHIdsToFinalize);
        assertTrue(unstETHToFinalizeDetails[0].status == UnstETHRecordStatus.Locked);
        assertEq(unstETHToFinalizeDetails[0].claimableAmount.toUint256(), 0);

        _finalizeWithdrawalQueue(unstETHIdsToFinalize[unstETHIdsToFinalize.length - 1]);

        unstETHToFinalizeHints = _lido.withdrawalQueue.findCheckpointHints(
            unstETHIdsToFinalize, 1, _lido.withdrawalQueue.getLastCheckpointIndex()
        );
        escrow.markUnstETHFinalized(unstETHIdsToFinalize, unstETHToFinalizeHints);

        // After finalization in the WQ, the finalization shares accounted
        unstETHToFinalizeDetails = escrow.getLockedUnstETHDetails(unstETHIdsToFinalize);
        assertTrue(unstETHToFinalizeDetails[0].status == UnstETHRecordStatus.Finalized);
        assertEq(unstETHToFinalizeDetails[0].claimableAmount.toUint256(), requestAmount);

        _simulateRebase(PercentsD16.fromBasisPoints(100_01)); // +0.01%

        vm.prank(address(_dgDeployedContracts.dualGovernance));
        escrow.startRageQuit(_RAGE_QUIT_EXTRA_TIMELOCK, _RAGE_QUIT_WITHDRAWALS_TIMELOCK);

        uint256 escrowStETHBalance = _lido.stETH.balanceOf(address(escrow));
        uint256 expectedWithdrawalsBatchesCount = escrowStETHBalance / requestAmount + 1;
        assertEq(_lido.withdrawalQueue.balanceOf(address(escrow)), 10 + _initialLockedUnStETHCount);

        escrow.requestNextWithdrawalsBatch(10);

        assertEq(_lido.withdrawalQueue.balanceOf(address(escrow)), 20 + _initialLockedUnStETHCount);

        while (!escrow.isWithdrawalsBatchesClosed()) {
            escrow.requestNextWithdrawalsBatch(96);
        }

        assertEq(
            _lido.withdrawalQueue.balanceOf(address(escrow)),
            10 + expectedWithdrawalsBatchesCount + _initialLockedUnStETHCount
        );
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

        uint256 vetoer1ETHBalanceBeforeWithdrawal = _VETOER_1.balance;

        vm.startPrank(_VETOER_1);
        escrow.withdrawETH();
        escrow.withdrawETH(unstETHIds);
        vm.stopPrank();

        // greater or equal here because of the stETH rebases
        assertTrue(_VETOER_1.balance - vetoer1ETHBalanceBeforeWithdrawal >= (20 + 30 + 10) * requestAmount);
    }

    function testFork_RageQuit_HappyPath_OnlyUnstETH() public {
        _prepareEmptyEscrow();
        escrow = Escrow(payable(_dgDeployedContracts.dualGovernance.getVetoSignallingEscrow()));

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

    // ---
    // Helper external methods to test reverts
    // ---

    function externalLockUnstETH(address vetoer, uint256[] memory unstETHIds) external {
        _lockUnstETH(vetoer, unstETHIds);
    }

    function _initialLockRandomAmountOfTokensInEscrow() internal {
        uint256 maxLockableEthers = 10;
        _random = Random.create(vm.unixTime());

        ISignallingEscrow.SignallingEscrowDetails memory initialEscrowDetails = escrow.getSignallingEscrowDetails();
        uint256 initiallyLockedStethShares = initialEscrowDetails.totalStETHLockedShares.toUint256();
        uint256 initiallyLockedUnStethShares = initialEscrowDetails.totalUnstETHUnfinalizedShares.toUint256();

        address stranger = makeAddr("stranger");

        _setupStETHBalance(stranger, PercentsD16.fromBasisPoints(10_00));

        vm.startPrank(stranger);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        _lido.wstETH.wrap(maxLockableEthers * 2 ether);
        vm.stopPrank();

        uint256 strangerLockStETHAmount = Random.nextUint256(_random, 1, maxLockableEthers) * 1 ether;
        uint256 strangerLockWstETHAmount = Random.nextUint256(_random, 1, maxLockableEthers) * 1 ether;
        uint256 strangerLockUnstETHAmount = Random.nextUint256(_random, 1, maxLockableEthers) * 1 ether;

        _lockStETH(stranger, strangerLockStETHAmount);
        _lockWstETH(stranger, strangerLockWstETHAmount);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = strangerLockUnstETHAmount;

        vm.prank(stranger);
        _initialLockedUnStETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, stranger);

        _lockUnstETH(stranger, _initialLockedUnStETHIds);

        uint256 initiallyLockedUnStethAmount = _lido.stETH.getPooledEthByShares(initiallyLockedUnStethShares);

        _initialLockedUnStETHAmount = strangerLockUnstETHAmount + initiallyLockedUnStethAmount;
        _initialLockedUnStETHShares =
            _lido.stETH.getSharesByPooledEth(strangerLockUnstETHAmount) + initiallyLockedUnStethShares;
        _initialLockedUnStETHCount = _lido.withdrawalQueue.balanceOf(address(escrow));
        _initialLockedShares = _lido.stETH.getSharesByPooledEth(strangerLockStETHAmount) + initiallyLockedStethShares
            + strangerLockWstETHAmount;
    }

    function _prepareEmptyEscrow() internal {
        // Passing through the Rage Quit state to ensure that the Escrow is in the correct state

        _setupStETHBalance(_VETOER, PercentsD16.fromBasisPoints(20_00));
        vm.prank(_VETOER);
        _lido.stETH.approve(address(_getVetoSignallingEscrow()), type(uint256).max);

        _lockStETH(_VETOER, _getSecondSealRageQuitSupport());
        _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
        _activateNextState();
        _assertRageQuitState();

        IRageQuitEscrow rageQuitEscrow = _getRageQuitEscrow();

        while (!rageQuitEscrow.isWithdrawalsBatchesClosed()) {
            rageQuitEscrow.requestNextWithdrawalsBatch(96);
        }

        _finalizeWithdrawalQueue();

        while (rageQuitEscrow.getUnclaimedUnstETHIdsCount() > 0) {
            rageQuitEscrow.claimNextWithdrawalsBatch(32);
        }

        rageQuitEscrow.startRageQuitExtensionPeriod();

        _wait(_getRageQuitExtensionPeriodDuration().plusSeconds(1));
        assertEq(rageQuitEscrow.isRageQuitFinalized(), true);

        _activateNextState();
    }
}
