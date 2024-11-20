// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdError} from "forge-std/StdError.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ETHValue, ETHValues, ETHValueOverflow, ETHValueUnderflow} from "contracts/types/ETHValue.sol";
import {SharesValue, SharesValues, SharesValueOverflow, SharesValueUnderflow} from "contracts/types/SharesValue.sol";
import {IndicesOneBased} from "contracts/types/IndexOneBased.sol";
import {Durations} from "contracts/types/Duration.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {AssetsAccounting, UnstETHRecordStatus} from "contracts/libraries/AssetsAccounting.sol";

import {UnitTest, Duration} from "test/utils/unit-test.sol";

contract AssetsAccountingUnitTests is UnitTest {
    AssetsAccounting.Context private _accountingContext;

    // ---
    // accountStETHSharesLock()
    // ---

    function testFuzz_accountStETHSharesLock_happyPath(address holder, SharesValue shares) external {
        SharesValue totalLockedShares = SharesValues.from(3);
        SharesValue holderLockedShares = SharesValues.from(1);

        vm.assume(shares.toUint256() > 0);
        vm.assume(
            shares.toUint256()
                < type(uint128).max - Math.max(totalLockedShares.toUint256(), holderLockedShares.toUint256())
        );

        _accountingContext.stETHTotals.lockedShares = totalLockedShares;
        _accountingContext.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesLocked(holder, shares);

        AssetsAccounting.accountStETHSharesLock(_accountingContext, holder, shares);

        checkAccountingContextTotalCounters(
            totalLockedShares + shares, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO
        );
        assertEq(_accountingContext.assets[holder].stETHLockedShares, holderLockedShares + shares);
        assertEq(_accountingContext.assets[holder].unstETHLockedShares, SharesValues.ZERO);
        assertLe(_accountingContext.assets[holder].lastAssetsLockTimestamp.toSeconds(), Timestamps.now().toSeconds());
        assertEq(_accountingContext.assets[holder].unstETHIds.length, 0);
    }

    function testFuzz_accountStETHSharesLock_RevertWhen_ZeroSharesProvided(address holder) external {
        SharesValue shares = SharesValues.ZERO;

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesLock(_accountingContext, holder, shares);
    }

    function testFuzz_accountStETHSharesLock_WhenNoSharesWereLockedBefore(
        address stranger,
        SharesValue shares
    ) external {
        SharesValue totalLockedShares = SharesValues.from(3);

        vm.assume(shares.toUint256() > 0);
        vm.assume(shares.toUint256() < type(uint128).max - totalLockedShares.toUint256());

        _accountingContext.stETHTotals.lockedShares = totalLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesLocked(stranger, shares);

        AssetsAccounting.accountStETHSharesLock(_accountingContext, stranger, shares);

        assertEq(_accountingContext.stETHTotals.lockedShares, totalLockedShares + shares);
        assertEq(_accountingContext.assets[stranger].stETHLockedShares, shares);
        assertLe(_accountingContext.assets[stranger].lastAssetsLockTimestamp.toSeconds(), Timestamps.now().toSeconds());
    }

    // ---
    // accountStETHSharesUnlock(Context storage self, address holder, SharesValue shares)
    // ---

    function testFuzz_accountStETHSharesUnlock_happyPath(
        address holder,
        SharesValue shares,
        SharesValue holderLockedShares
    ) external {
        SharesValue totalLockedSharesWithoutHolder = SharesValues.from(3);
        vm.assume(shares.toUint256() > 0);
        vm.assume(holderLockedShares.toUint256() < type(uint128).max - totalLockedSharesWithoutHolder.toUint256());
        vm.assume(shares.toUint256() <= holderLockedShares.toUint256());

        SharesValue totalLockedShares = totalLockedSharesWithoutHolder + holderLockedShares;

        _accountingContext.stETHTotals.lockedShares = totalLockedShares;
        _accountingContext.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesUnlocked(holder, shares);

        AssetsAccounting.accountStETHSharesUnlock(_accountingContext, holder, shares);

        checkAccountingContextTotalCounters(
            totalLockedShares - shares, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO
        );
        assertEq(_accountingContext.assets[holder].stETHLockedShares, holderLockedShares - shares);
        assertEq(_accountingContext.assets[holder].unstETHLockedShares, SharesValues.ZERO);
        assertEq(_accountingContext.assets[holder].lastAssetsLockTimestamp, Timestamps.ZERO);
        assertEq(_accountingContext.assets[holder].unstETHIds.length, 0);
    }

    function testFuzz_accountStETHSharesUnlock_RevertOn_ZeroSharesProvided(address holder) external {
        SharesValue shares = SharesValues.ZERO;

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesUnlock(_accountingContext, holder, shares);
    }

    function testFuzz_accountStETHSharesUnlock_RevertWhen_HolderHaveLessSharesThanProvided(
        address holder,
        SharesValue shares,
        SharesValue holderLockedShares
    ) external {
        SharesValue totalLockedSharesWithoutHolder = SharesValues.from(3);
        vm.assume(shares.toUint256() > 0);
        vm.assume(holderLockedShares.toUint256() < type(uint128).max - totalLockedSharesWithoutHolder.toUint256());
        vm.assume(shares.toUint256() > holderLockedShares.toUint256());

        _accountingContext.stETHTotals.lockedShares = totalLockedSharesWithoutHolder + holderLockedShares;
        _accountingContext.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesUnlock(_accountingContext, holder, shares);
    }

    function testFuzz_accountStETHSharesUnlock_RevertOn_AccountingError_TotalLockedSharesCounterIsLessThanProvidedSharesAmount(
        address holder,
        SharesValue shares,
        SharesValue totalLockedShares
    ) external {
        vm.assume(shares.toUint256() > 0);
        vm.assume(totalLockedShares.toUint256() < shares.toUint256());

        _accountingContext.stETHTotals.lockedShares = totalLockedShares;
        _accountingContext.assets[holder].stETHLockedShares = shares;

        vm.expectRevert(SharesValueUnderflow.selector);

        AssetsAccounting.accountStETHSharesUnlock(_accountingContext, holder, shares);
    }

    function testFuzz_accountStETHSharesUnlock_RevertWhen_NoSharesWereLockedBefore(
        address stranger,
        SharesValue shares
    ) external {
        vm.assume(shares.toUint256() > 0);

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesUnlock(_accountingContext, stranger, shares);
    }

    // ---
    // accountStETHSharesUnlock(Context storage self, address holder)
    // ---

    function testFuzz_accountStETHSharesUnlock_simple_happyPath(
        address holder,
        SharesValue holderLockedShares
    ) external {
        SharesValue totalLockedSharesWithoutHolder = SharesValues.from(3);
        vm.assume(holderLockedShares.toUint256() > 0);
        vm.assume(holderLockedShares.toUint256() < type(uint128).max - totalLockedSharesWithoutHolder.toUint256());

        SharesValue totalLockedShares = totalLockedSharesWithoutHolder + holderLockedShares;

        _accountingContext.stETHTotals.lockedShares = totalLockedShares;
        _accountingContext.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesUnlocked(holder, holderLockedShares);

        SharesValue unlockedShares = AssetsAccounting.accountStETHSharesUnlock(_accountingContext, holder);

        assertEq(unlockedShares, holderLockedShares);
        checkAccountingContextTotalCounters(
            totalLockedShares - holderLockedShares, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO
        );
        assertEq(_accountingContext.assets[holder].stETHLockedShares, holderLockedShares - holderLockedShares);
        assertEq(_accountingContext.assets[holder].unstETHLockedShares, SharesValues.ZERO);
        assertEq(_accountingContext.assets[holder].lastAssetsLockTimestamp, Timestamps.ZERO);
        assertEq(_accountingContext.assets[holder].unstETHIds.length, 0);
    }

    function testFuzz_accountStETHSharesUnlock_simple_RevertWhen_NoSharesWereLockedBefore(address stranger) external {
        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, SharesValues.ZERO));

        AssetsAccounting.accountStETHSharesUnlock(_accountingContext, stranger);
    }

    // ---
    // accountStETHSharesWithdraw
    // ---

    function testFuzz_accountStETHSharesWithdraw_happyPath(
        address holder,
        SharesValue holderLockedShares,
        SharesValue totalLockedShares,
        ETHValue totalClaimedETH
    ) external {
        vm.assume(totalLockedShares.toUint256() > 0);
        vm.assume(holderLockedShares.toUint256() > 0);
        vm.assume(holderLockedShares.toUint256() <= totalLockedShares.toUint256());

        _accountingContext.assets[holder].stETHLockedShares = holderLockedShares;
        _accountingContext.stETHTotals.lockedShares = totalLockedShares;
        _accountingContext.stETHTotals.claimedETH = totalClaimedETH;

        ETHValue expectedETHWithdrawn = ETHValues.from(
            (totalClaimedETH.toUint256() * holderLockedShares.toUint256()) / totalLockedShares.toUint256()
        );

        vm.expectEmit();
        emit AssetsAccounting.ETHWithdrawn(holder, holderLockedShares, expectedETHWithdrawn);

        ETHValue ethWithdrawn = AssetsAccounting.accountStETHSharesWithdraw(_accountingContext, holder);

        assertEq(ethWithdrawn, expectedETHWithdrawn);
        checkAccountingContextTotalCounters(totalLockedShares, totalClaimedETH, SharesValues.ZERO, ETHValues.ZERO);
        assertEq(_accountingContext.assets[holder].stETHLockedShares, SharesValues.ZERO);
        assertEq(_accountingContext.assets[holder].unstETHLockedShares, SharesValues.ZERO);
        assertEq(_accountingContext.assets[holder].lastAssetsLockTimestamp, Timestamps.ZERO);
        assertEq(_accountingContext.assets[holder].unstETHIds.length, 0);
    }

    function testFuzz_accountStETHSharesWithdraw_RevertWhen_HolderHaveZeroShares(address stranger) external {
        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, SharesValues.ZERO));

        AssetsAccounting.accountStETHSharesWithdraw(_accountingContext, stranger);
    }

    function testFuzz_accountStETHSharesWithdraw_RevertOn_AccountingError_TotalLockedSharesCounterIsZero(
        address holder,
        SharesValue holderLockedShares,
        ETHValue totalClaimedETH
    ) external {
        vm.assume(holderLockedShares.toUint256() > 0);

        _accountingContext.assets[holder].stETHLockedShares = holderLockedShares;
        _accountingContext.stETHTotals.lockedShares = SharesValues.ZERO;
        _accountingContext.stETHTotals.claimedETH = totalClaimedETH;

        vm.expectRevert(stdError.divisionError);

        AssetsAccounting.accountStETHSharesWithdraw(_accountingContext, holder);
    }

    function testFuzz_accountStETHSharesWithdraw_AccountingError_WithdrawAmountMoreThanTotalClaimedETH(
        address holder,
        SharesValue holderLockedShares,
        ETHValue totalClaimedETH
    ) external {
        uint128 totalLockedSharesAmount = 10;
        vm.assume(holderLockedShares.toUint256() > totalLockedSharesAmount);
        vm.assume(holderLockedShares.toUint256() < type(uint64).max);
        vm.assume(totalClaimedETH.toUint256() < type(uint64).max);

        SharesValue totalLockedShares = SharesValues.from(totalLockedSharesAmount);

        _accountingContext.assets[holder].stETHLockedShares = holderLockedShares;
        _accountingContext.stETHTotals.lockedShares = totalLockedShares;
        _accountingContext.stETHTotals.claimedETH = totalClaimedETH;

        ETHValue expectedETHWithdrawn =
            ETHValues.from((totalClaimedETH.toUint256() * holderLockedShares.toUint256()) / totalLockedSharesAmount);

        vm.expectEmit();
        emit AssetsAccounting.ETHWithdrawn(holder, holderLockedShares, expectedETHWithdrawn);

        ETHValue ethWithdrawn = AssetsAccounting.accountStETHSharesWithdraw(_accountingContext, holder);

        assertEq(ethWithdrawn, expectedETHWithdrawn);
        assertGe(ethWithdrawn.toUint256(), totalClaimedETH.toUint256());
        assertEq(_accountingContext.assets[holder].stETHLockedShares, SharesValues.ZERO);
    }

    function testFuzz_accountStETHSharesWithdraw_RevertOn_AccountingError_WithdrawAmountOverflow(address holder)
        external
    {
        SharesValue holderLockedShares = SharesValues.from(type(uint96).max);
        SharesValue totalLockedShares = SharesValues.from(1);
        ETHValue totalClaimedETH = ETHValues.from(type(uint96).max);

        _accountingContext.assets[holder].stETHLockedShares = holderLockedShares;
        _accountingContext.stETHTotals.lockedShares = totalLockedShares;
        _accountingContext.stETHTotals.claimedETH = totalClaimedETH;

        vm.expectRevert(ETHValueOverflow.selector);

        AssetsAccounting.accountStETHSharesWithdraw(_accountingContext, holder);
    }

    // ---
    // accountClaimedETH
    // ---

    function testFuzz_accountClaimedETH_happyPath(ETHValue amount, ETHValue totalClaimedETH) external {
        vm.assume(amount.toUint256() < type(uint128).max / 2);
        vm.assume(totalClaimedETH.toUint256() < type(uint128).max / 2);

        _accountingContext.stETHTotals.claimedETH = totalClaimedETH;

        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(amount);

        AssetsAccounting.accountClaimedETH(_accountingContext, amount);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO, totalClaimedETH + amount, SharesValues.ZERO, ETHValues.ZERO
        );
    }

    // ---
    // accountUnstETHLock
    // ---

    // TODO: make a research on gas consumption when a lot of unstNFTs provided.
    function testFuzz_accountUnstETHLock_happyPath(
        address holder,
        uint96[] memory amountsOfShares,
        SharesValue holderUnstETHLockedShares,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(amountsOfShares.length > 1);
        vm.assume(amountsOfShares.length <= 500);
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        uint256 expectedTotalUnstETHLockedAmount = 0;

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.assets[holder].unstETHIds.push(genRandomUnstEthId(1024));
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
            expectedTotalUnstETHLockedAmount += amountsOfShares[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHLocked(holder, unstETHIds, SharesValues.from(expectedTotalUnstETHLockedAmount));
        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO,
            ETHValues.ZERO,
            initialTotalUnfinalizedShares + SharesValues.from(expectedTotalUnstETHLockedAmount),
            ETHValues.ZERO
        );
        assertEq(_accountingContext.assets[holder].stETHLockedShares, SharesValues.ZERO);
        assertEq(
            _accountingContext.assets[holder].unstETHLockedShares,
            holderUnstETHLockedShares + SharesValues.from(expectedTotalUnstETHLockedAmount)
        );
        assertLe(_accountingContext.assets[holder].lastAssetsLockTimestamp.toSeconds(), Timestamps.now().toSeconds());
        assertEq(_accountingContext.assets[holder].unstETHIds.length, amountsOfShares.length + 1);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].lockedBy, holder);
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].status, UnstETHRecordStatus.Locked);
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].index.toZeroBasedValue(), i + 1);
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].shares, SharesValues.from(amountsOfShares[i]));
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].claimableAmount, ETHValues.ZERO);
        }
    }

    function testFuzz_accountUnstETHLock_RevertOn_UnstETHIdsLengthNotEqualToWithdrawalRequestStatusesLength(
        address holder
    ) external {
        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](1);
        uint256[] memory unstETHIds = new uint256[](0);

        vm.expectRevert();

        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_RevertOn_WithdrawalRequestStatusIsFinalized(
        address holder,
        uint96[] memory amountsOfShares,
        SharesValue holderUnstETHLockedShares,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
        }

        withdrawalRequestStatuses[withdrawalRequestStatuses.length - 1].isFinalized = true;

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector,
                unstETHIds[unstETHIds.length - 1],
                UnstETHRecordStatus.Finalized
            )
        );

        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_RevertOn_WithdrawalRequestStatusIsClaimed(
        address holder,
        uint96[] memory amountsOfShares,
        SharesValue holderUnstETHLockedShares,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
        }

        withdrawalRequestStatuses[withdrawalRequestStatuses.length - 1].isClaimed = true;

        vm.expectRevert();

        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_RevertOn_UnstETHRecordStatusIsNot_NotLocked(
        address holder,
        uint96[] memory amountsOfShares,
        SharesValue holderUnstETHLockedShares,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
        }

        _accountingContext.unstETHRecords[unstETHIds[unstETHIds.length - 1]].status = UnstETHRecordStatus.Withdrawn;

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector,
                unstETHIds[unstETHIds.length - 1],
                UnstETHRecordStatus.Withdrawn
            )
        );

        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_RevertWhen_DuplicatingUnstETHIdsProvided(
        address holder,
        uint96[] memory amountsOfShares,
        SharesValue holderUnstETHLockedShares,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(amountsOfShares.length > 1);
        vm.assume(amountsOfShares.length <= 500);
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
        }

        unstETHIds[unstETHIds.length - 1] = unstETHIds[unstETHIds.length - 2];

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector,
                unstETHIds[unstETHIds.length - 1],
                UnstETHRecordStatus.Locked
            )
        );

        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);
    }

    // TODO: is it expected behavior?
    function testFuzz_accountUnstETHLock_WhenNoUnstETHIdsProvided(
        address holder,
        SharesValue holderUnstETHLockedShares,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](0);
        uint256[] memory unstETHIds = new uint256[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHLocked(holder, unstETHIds, SharesValues.ZERO);
        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, ETHValues.ZERO
        );
        assertEq(_accountingContext.assets[holder].stETHLockedShares, SharesValues.ZERO);
        assertEq(_accountingContext.assets[holder].unstETHLockedShares, holderUnstETHLockedShares);
        assertLe(_accountingContext.assets[holder].lastAssetsLockTimestamp.toSeconds(), Timestamps.now().toSeconds());
        assertEq(_accountingContext.assets[holder].unstETHIds.length, 0);
    }

    function testFuzz_accountUnstETHLock_AccountingError_WithdrawalRequestStatusAmountOfSharesOverflow(
        address holder,
        SharesValue holderUnstETHLockedShares,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](1);
        uint256[] memory unstETHIds = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(0);
        withdrawalRequestStatuses[0].amountOfShares = uint256(type(uint128).max) + 1;
        withdrawalRequestStatuses[0].isFinalized = false;
        withdrawalRequestStatuses[0].isClaimed = false;
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.NotLocked;

        vm.expectRevert(SharesValueOverflow.selector);

        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_AccountingError_HolderUnstETHLockedSharesOverflow(
        address holder,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        SharesValue holderUnstETHLockedShares = SharesValues.from(type(uint128).max / 2 + 1);

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](1);
        uint256[] memory unstETHIds = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(0);
        withdrawalRequestStatuses[0].amountOfShares = uint128(type(uint128).max / 2) + 1;
        withdrawalRequestStatuses[0].isFinalized = false;
        withdrawalRequestStatuses[0].isClaimed = false;
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.NotLocked;

        vm.expectRevert(SharesValueOverflow.selector);

        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_AccountingError_TotalUnfinalizedSharesOverflow(
        address holder,
        SharesValue holderUnstETHLockedShares
    ) external {
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(type(uint128).max / 2 + 1);

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        IWithdrawalQueue.WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new IWithdrawalQueue.WithdrawalRequestStatus[](1);
        uint256[] memory unstETHIds = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(0);
        withdrawalRequestStatuses[0].amountOfShares = uint128(type(uint128).max / 2) + 1;
        withdrawalRequestStatuses[0].isFinalized = false;
        withdrawalRequestStatuses[0].isClaimed = false;
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.NotLocked;

        vm.expectRevert(SharesValueOverflow.selector);

        AssetsAccounting.accountUnstETHLock(_accountingContext, holder, unstETHIds, withdrawalRequestStatuses);
    }

    // ---
    // accountUnstETHUnlock
    // ---

    // TODO: make a research on gas consumption when a lot of unstNFTs provided.
    function testFuzz_accountUnstETHUnlock_happyPath(
        address holder,
        uint64[] memory amountsOfShares,
        SharesValue holderUnstETHLockedShares,
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);
        vm.assume(holderUnstETHLockedShares.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalUnfinalizedShares.toUint256() > 500 * uint128(type(uint64).max));

        uint256 expectedTotalSharesUnlockedAmount = 0;

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingContext.unstETHRecords[unstETHIds[i]].lockedBy = holder;
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Locked;
            _accountingContext.unstETHRecords[unstETHIds[i]].shares = SharesValues.from(amountsOfShares[i]);
            _accountingContext.unstETHRecords[unstETHIds[i]].index = IndicesOneBased.fromOneBasedValue(i + 1);
            _accountingContext.assets[holder].unstETHIds.push(unstETHIds[i]);
            expectedTotalSharesUnlockedAmount += amountsOfShares[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHUnlocked(
            holder, unstETHIds, SharesValues.from(expectedTotalSharesUnlockedAmount), ETHValues.ZERO
        );

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, holder, unstETHIds);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO,
            ETHValues.ZERO,
            initialTotalUnfinalizedShares - SharesValues.from(expectedTotalSharesUnlockedAmount),
            initialTotalFinalizedETH
        );
        assertEq(_accountingContext.assets[holder].stETHLockedShares, SharesValues.ZERO);
        assertEq(
            _accountingContext.assets[holder].unstETHLockedShares,
            holderUnstETHLockedShares - SharesValues.from(expectedTotalSharesUnlockedAmount)
        );
        assertEq(_accountingContext.assets[holder].lastAssetsLockTimestamp, Timestamps.ZERO);
        assertEq(_accountingContext.assets[holder].unstETHIds.length, 0);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].shares, SharesValues.ZERO);
        }
    }

    function testFuzz_accountUnstETHUnlock_WhenFinalizedUnstETHUnlocked(
        address holder,
        uint64[] memory amountsOfShares,
        SharesValue holderUnstETHLockedShares,
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);
        vm.assume(holderUnstETHLockedShares.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalFinalizedETH.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalFinalizedETH.toUint256() > 500 * uint128(type(uint64).max));

        uint256 expectedTotalSharesUnlockedAmount = 0;

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingContext.unstETHRecords[unstETHIds[i]].lockedBy = holder;
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Finalized;
            _accountingContext.unstETHRecords[unstETHIds[i]].shares = SharesValues.from(amountsOfShares[i]);
            _accountingContext.unstETHRecords[unstETHIds[i]].claimableAmount = ETHValues.from(amountsOfShares[i]);
            _accountingContext.unstETHRecords[unstETHIds[i]].index = IndicesOneBased.fromOneBasedValue(i + 1);
            _accountingContext.assets[holder].unstETHIds.push(unstETHIds[i]);
            expectedTotalSharesUnlockedAmount += amountsOfShares[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHUnlocked(
            holder,
            unstETHIds,
            SharesValues.from(expectedTotalSharesUnlockedAmount),
            ETHValues.from(expectedTotalSharesUnlockedAmount)
        );

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, holder, unstETHIds);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO,
            ETHValues.ZERO,
            initialTotalUnfinalizedShares,
            initialTotalFinalizedETH - ETHValues.from(expectedTotalSharesUnlockedAmount)
        );
        assertEq(_accountingContext.assets[holder].stETHLockedShares, SharesValues.ZERO);
        assertEq(
            _accountingContext.assets[holder].unstETHLockedShares,
            holderUnstETHLockedShares - SharesValues.from(expectedTotalSharesUnlockedAmount)
        );
        assertEq(_accountingContext.assets[holder].lastAssetsLockTimestamp, Timestamps.ZERO);
        assertEq(_accountingContext.assets[holder].unstETHIds.length, 0);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].shares, SharesValues.ZERO);
        }
    }

    function testFuzz_accountUnstETHUnlock_RevertWhen_UnknownUnstETHIdProvided(address holder) external {
        vm.assume(holder != address(0x0));

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidUnstETHHolder.selector, unstETHIds[0], holder));

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertWhen_UnstETHRecordDoesNotBelongToCurrent(
        address holder,
        address current
    ) external {
        vm.assume(holder != current);

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingContext.unstETHRecords[unstETHIds[0]].lockedBy = holder;

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidUnstETHHolder.selector, unstETHIds[0], current));

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, current, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertWhen_UnstETHRecordStatusInvalid(address holder) external {
        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingContext.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.NotLocked;

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector, unstETHIds[0], UnstETHRecordStatus.NotLocked
            )
        );

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertWhen_UnstETHRecordIndexInvalid_OOB(address holder) external {
        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingContext.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingContext.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(1234);
        _accountingContext.unstETHRecords[unstETHIds[0]].index = IndicesOneBased.fromOneBasedValue(10);
        _accountingContext.assets[holder].unstETHIds.push(unstETHIds[0]);

        vm.expectRevert(stdError.indexOOBError);

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, holder, unstETHIds);
    }

    // TODO: is it expected behavior?
    function testFuzz_accountUnstETHUnlock_WhenNoUnstETHIdsProvided(
        address holder,
        SharesValue holderUnstETHLockedShares,
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(holderUnstETHLockedShares.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalFinalizedETH.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(holderUnstETHLockedShares.toUint256() < type(uint96).max);
        vm.assume(initialTotalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHUnlocked(holder, unstETHIds, SharesValues.ZERO, ETHValues.ZERO);

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, holder, unstETHIds);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, initialTotalFinalizedETH
        );
        assertEq(_accountingContext.assets[holder].stETHLockedShares, SharesValues.ZERO);
        assertEq(_accountingContext.assets[holder].unstETHLockedShares, holderUnstETHLockedShares);
        assertEq(_accountingContext.assets[holder].lastAssetsLockTimestamp, Timestamps.ZERO);
        assertEq(_accountingContext.assets[holder].unstETHIds.length, 0);
    }

    function testFuzz_accountUnstETHUnlock_RevertOn_AccountingError_HolderUnstETHLockedSharesUnderflow(address holder)
        external
    {
        _accountingContext.assets[holder].unstETHLockedShares = SharesValues.from(5);

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingContext.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingContext.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(10);
        _accountingContext.unstETHRecords[unstETHIds[0]].index = IndicesOneBased.fromOneBasedValue(1);
        _accountingContext.assets[holder].unstETHIds.push(unstETHIds[0]);

        vm.expectRevert(SharesValueUnderflow.selector);

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertOn_AccountingError_TotalFinalizedETHUnderflow(address holder)
        external
    {
        _accountingContext.assets[holder].unstETHLockedShares = SharesValues.from(10);
        _accountingContext.unstETHTotals.finalizedETH = ETHValues.from(5);

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingContext.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Finalized;
        _accountingContext.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(5);
        _accountingContext.unstETHRecords[unstETHIds[0]].index = IndicesOneBased.fromOneBasedValue(1);
        _accountingContext.unstETHRecords[unstETHIds[0]].claimableAmount = ETHValues.from(10);
        _accountingContext.assets[holder].unstETHIds.push(unstETHIds[0]);

        vm.expectRevert(ETHValueUnderflow.selector);

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertOn_AccountingError_TotalUnfinalizedSharesUnderflow(address holder)
        external
    {
        _accountingContext.assets[holder].unstETHLockedShares = SharesValues.from(10);
        _accountingContext.unstETHTotals.unfinalizedShares = SharesValues.from(5);

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingContext.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingContext.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(10);
        _accountingContext.unstETHRecords[unstETHIds[0]].index = IndicesOneBased.fromOneBasedValue(1);
        _accountingContext.assets[holder].unstETHIds.push(unstETHIds[0]);

        vm.expectRevert(SharesValueUnderflow.selector);

        AssetsAccounting.accountUnstETHUnlock(_accountingContext, holder, unstETHIds);
    }

    // ---
    // accountUnstETHFinalized
    // ---

    // TODO: make a research on gas consumption when a lot of unstNFTs provided.
    function testFuzz_accountUnstETHFinalized_happyPath(
        uint64[] memory claimableAmounts,
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);
        vm.assume(initialTotalUnfinalizedShares.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        uint256 expectedTotalSharesFinalized = 0;
        uint256 expectedTotalAmountFinalized = 0;

        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length);
        uint256[] memory claimableAmountsPrepared = new uint256[](claimableAmounts.length);

        SharesValue[] memory expectedSharesFinalized = new SharesValue[](claimableAmounts.length);
        ETHValue[] memory expectedAmountFinalized = new ETHValue[](claimableAmounts.length);

        for (uint256 i = 0; i < claimableAmounts.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Locked;
            uint256 sharesAmount = 5 * uint256(claimableAmounts[i]);
            _accountingContext.unstETHRecords[unstETHIds[i]].shares = SharesValues.from(sharesAmount);
            expectedTotalSharesFinalized += sharesAmount;
            expectedTotalAmountFinalized += claimableAmounts[i];
            expectedSharesFinalized[i] = SharesValues.from(sharesAmount);
            expectedAmountFinalized[i] = ETHValues.from(claimableAmounts[i]);
            claimableAmountsPrepared[i] = claimableAmounts[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(unstETHIds, expectedSharesFinalized, expectedAmountFinalized);

        AssetsAccounting.accountUnstETHFinalized(_accountingContext, unstETHIds, claimableAmountsPrepared);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO,
            ETHValues.ZERO,
            initialTotalUnfinalizedShares - SharesValues.from(expectedTotalSharesFinalized),
            initialTotalFinalizedETH + ETHValues.from(expectedTotalAmountFinalized)
        );
    }

    function testFuzz_accountUnstETHFinalized_RevertWhen_ClaimableAmountsLengthNotEqUnstETHIdsLength(
        uint64[] memory claimableAmounts
    ) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length);
        uint256[] memory claimableAmountsPrepared = new uint256[](claimableAmounts.length + 1);

        vm.expectRevert(stdError.assertionError);

        AssetsAccounting.accountUnstETHFinalized(_accountingContext, unstETHIds, claimableAmountsPrepared);
    }

    function testFuzz_accountUnstETHFinalized_When_NoClaimableAmountsProvided(
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(initialTotalFinalizedETH.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](0);
        uint256[] memory claimableAmountsPrepared = new uint256[](0);
        SharesValue[] memory expectedSharesFinalized = new SharesValue[](0);
        ETHValue[] memory expectedAmountFinalized = new ETHValue[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(unstETHIds, expectedSharesFinalized, expectedAmountFinalized);

        AssetsAccounting.accountUnstETHFinalized(_accountingContext, unstETHIds, claimableAmountsPrepared);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, initialTotalFinalizedETH
        );
    }

    function testFuzz_accountUnstETHFinalized_When_UnstETHRecordNotFound(
        uint64 claimableAmount,
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(initialTotalFinalizedETH.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        claimableAmountsPrepared[0] = claimableAmount;

        SharesValue[] memory expectedSharesFinalized = new SharesValue[](1);
        ETHValue[] memory expectedAmountFinalized = new ETHValue[](1);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(unstETHIds, expectedSharesFinalized, expectedAmountFinalized);

        AssetsAccounting.accountUnstETHFinalized(_accountingContext, unstETHIds, claimableAmountsPrepared);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, initialTotalFinalizedETH
        );
    }

    function testFuzz_accountUnstETHFinalized_When_ClaimableAmountIsZero(
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(initialTotalFinalizedETH.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingContext.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(123);
        claimableAmountsPrepared[0] = 0;

        SharesValue[] memory expectedSharesFinalized = new SharesValue[](1);
        ETHValue[] memory expectedAmountFinalized = new ETHValue[](1);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(unstETHIds, expectedSharesFinalized, expectedAmountFinalized);

        AssetsAccounting.accountUnstETHFinalized(_accountingContext, unstETHIds, claimableAmountsPrepared);

        checkAccountingContextTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, initialTotalFinalizedETH
        );
    }

    function testFuzz_accountUnstETHFinalized_RevertOn_ClaimableAmountOverflow(
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(initialTotalFinalizedETH.toUint256() > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingContext.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(123);
        claimableAmountsPrepared[0] = uint256(type(uint128).max) + 1;

        vm.expectRevert(ETHValueOverflow.selector);

        AssetsAccounting.accountUnstETHFinalized(_accountingContext, unstETHIds, claimableAmountsPrepared);
    }

    function testFuzz_accountUnstETHFinalized_RevertOn_TotalFinalizedETHOverflow(
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(initialTotalFinalizedETH.toUint256() > type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingContext.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(123);
        claimableAmountsPrepared[0] = uint256(type(uint128).max - 2);

        vm.expectRevert(ETHValueOverflow.selector);

        AssetsAccounting.accountUnstETHFinalized(_accountingContext, unstETHIds, claimableAmountsPrepared);
    }

    function testFuzz_accountUnstETHFinalized_RevertOn_TotalUnfinalizedSharesUnderflow(
        ETHValue initialTotalFinalizedETH,
        SharesValue initialTotalUnfinalizedShares
    ) external {
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint64).max);
        vm.assume(initialTotalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(initialTotalUnfinalizedShares.toUint256() < type(uint96).max);

        _accountingContext.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingContext.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(type(uint64).max);
        claimableAmountsPrepared[0] = 1;

        vm.expectRevert(SharesValueUnderflow.selector);

        AssetsAccounting.accountUnstETHFinalized(_accountingContext, unstETHIds, claimableAmountsPrepared);
    }

    // ---
    // accountUnstETHClaimed
    // ---

    // TODO: make a research on gas consumption when a lot of unstNFTs provided.
    function testFuzz_accountUnstETHClaimed_happyPath(uint64[] memory claimableAmounts) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);

        uint256 expectedTotalAmountClaimed = 0;

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length);
        uint256[] memory claimableAmountsPrepared = new uint256[](claimableAmounts.length);

        for (uint256 i = 0; i < claimableAmounts.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Locked;
            expectedTotalAmountClaimed += claimableAmounts[i];
            claimableAmountsPrepared[i] = claimableAmounts[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHClaimed(unstETHIds, ETHValues.from(expectedTotalAmountClaimed));

        AssetsAccounting.accountUnstETHClaimed(_accountingContext, unstETHIds, claimableAmountsPrepared);

        checkAccountingContextTotalCounters(SharesValues.ZERO, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(
                _accountingContext.unstETHRecords[unstETHIds[i]].claimableAmount, ETHValues.from(claimableAmounts[i])
            );
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].status, UnstETHRecordStatus.Claimed);
        }
    }

    // TODO: Maybe need to add check for `assert(claimableAmounts.length == unstETHIds.length)` to the code
    function testFuzz_accountUnstETHClaimed_RevertWhen_ClaimableAmountsLengthNotEqUnstETHIdsLength(
        uint64[] memory claimableAmounts
    ) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length + 1);
        uint256[] memory claimableAmountsPrepared = new uint256[](claimableAmounts.length);

        for (uint256 i = 0; i < claimableAmounts.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Locked;
            claimableAmountsPrepared[i] = claimableAmounts[i];
        }

        vm.expectRevert(stdError.indexOOBError);

        AssetsAccounting.accountUnstETHClaimed(_accountingContext, unstETHIds, claimableAmountsPrepared);
    }

    function test_accountUnstETHClaimed_WhenNoUnstETHIdsProvided() external {
        uint256 expectedTotalAmountClaimed = 0;

        uint256[] memory unstETHIds = new uint256[](0);
        uint256[] memory claimableAmountsPrepared = new uint256[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHClaimed(unstETHIds, ETHValues.from(expectedTotalAmountClaimed));

        AssetsAccounting.accountUnstETHClaimed(_accountingContext, unstETHIds, claimableAmountsPrepared);

        checkAccountingContextTotalCounters(SharesValues.ZERO, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
    }

    function testFuzz_accountUnstETHClaimed_RevertWhen_UnstETHRecordNotFoundOrHasWrongStatus(
        uint64[] memory claimableAmounts
    ) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length + 1);
        uint256[] memory claimableAmountsPrepared = new uint256[](claimableAmounts.length);

        for (uint256 i = 0; i < claimableAmounts.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            claimableAmountsPrepared[i] = claimableAmounts[i];
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector, unstETHIds[0], UnstETHRecordStatus.NotLocked
            )
        );

        AssetsAccounting.accountUnstETHClaimed(_accountingContext, unstETHIds, claimableAmountsPrepared);
    }

    function testFuzz_accountUnstETHClaimed_RevertWhen_UnstETHRecordIsFinalizedAndClaimableAmountIsIncorrect(
        uint64[] memory claimableAmounts
    ) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length + 1);
        uint256[] memory claimableAmountsPrepared = new uint256[](claimableAmounts.length);

        for (uint256 i = 0; i < claimableAmounts.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Finalized;
            _accountingContext.unstETHRecords[unstETHIds[i]].claimableAmount =
                ETHValues.from(uint256(claimableAmounts[i]) + 1);
            claimableAmountsPrepared[i] = claimableAmounts[i];
        }

        vm.expectRevert(
            abi.encodeWithSelector(AssetsAccounting.InvalidClaimableAmount.selector, unstETHIds[0], claimableAmounts[0])
        );

        AssetsAccounting.accountUnstETHClaimed(_accountingContext, unstETHIds, claimableAmountsPrepared);
    }

    function testFuzz_accountUnstETHClaimed_When_UnstETHRecordIsFinalizedAndClaimableAmountIsCorrect(
        uint64[] memory claimableAmounts
    ) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);

        uint256 expectedTotalAmountClaimed = 0;

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length);
        uint256[] memory claimableAmountsPrepared = new uint256[](claimableAmounts.length);

        for (uint256 i = 0; i < claimableAmounts.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Finalized;
            _accountingContext.unstETHRecords[unstETHIds[i]].claimableAmount = ETHValues.from(claimableAmounts[i]);
            claimableAmountsPrepared[i] = claimableAmounts[i];
            expectedTotalAmountClaimed += claimableAmounts[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHClaimed(unstETHIds, ETHValues.from(expectedTotalAmountClaimed));

        AssetsAccounting.accountUnstETHClaimed(_accountingContext, unstETHIds, claimableAmountsPrepared);

        checkAccountingContextTotalCounters(SharesValues.ZERO, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(
                _accountingContext.unstETHRecords[unstETHIds[i]].claimableAmount, ETHValues.from(claimableAmounts[i])
            );
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].status, UnstETHRecordStatus.Claimed);
        }
    }

    function test_accountUnstETHClaimed_RevertWhen_ClaimableAmountsOverflow() external {
        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(1);
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        claimableAmountsPrepared[0] = uint256(type(uint128).max) + 1;

        vm.expectRevert(ETHValueOverflow.selector);

        AssetsAccounting.accountUnstETHClaimed(_accountingContext, unstETHIds, claimableAmountsPrepared);
    }

    // ---
    // accountUnstETHWithdraw
    // ---

    // TODO: make a research on gas consumption when a lot of unstNFTs provided.
    function testFuzz_accountUnstETHWithdraw_happyPath(address holder, uint64[] memory claimableAmounts) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);

        uint256 expectedAmountWithdrawn = 0;

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length);

        for (uint256 i = 0; i < claimableAmounts.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Claimed;
            _accountingContext.unstETHRecords[unstETHIds[i]].lockedBy = holder;
            _accountingContext.unstETHRecords[unstETHIds[i]].claimableAmount = ETHValues.from(claimableAmounts[i]);
            expectedAmountWithdrawn += claimableAmounts[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHWithdrawn(unstETHIds, ETHValues.from(expectedAmountWithdrawn));

        ETHValue amountWithdrawn = AssetsAccounting.accountUnstETHWithdraw(_accountingContext, holder, unstETHIds);

        assertEq(amountWithdrawn, ETHValues.from(expectedAmountWithdrawn));

        checkAccountingContextTotalCounters(SharesValues.ZERO, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(
                _accountingContext.unstETHRecords[unstETHIds[i]].claimableAmount, ETHValues.from(claimableAmounts[i])
            );
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].status, UnstETHRecordStatus.Withdrawn);
            assertEq(_accountingContext.unstETHRecords[unstETHIds[i]].lockedBy, holder);
        }
    }

    function testFuzz_accountUnstETHWithdraw_WhenNoUnstETHIdsProvided(address holder) external {
        uint256[] memory unstETHIds = new uint256[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHWithdrawn(unstETHIds, ETHValues.ZERO);

        ETHValue amountWithdrawn = AssetsAccounting.accountUnstETHWithdraw(_accountingContext, holder, unstETHIds);

        assertEq(amountWithdrawn, ETHValues.ZERO);
    }

    function testFuzz_accountUnstETHWithdraw_RevertWhen_UnstETHRecordNotFound(
        address holder,
        uint64[] memory claimableAmounts
    ) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length);

        for (uint256 i = 0; i < claimableAmounts.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector, unstETHIds[0], UnstETHRecordStatus.NotLocked
            )
        );

        AssetsAccounting.accountUnstETHWithdraw(_accountingContext, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHWithdraw_RevertWhen_UnstETHRecordDoesNotBelongToCurrent(
        address holder,
        address current
    ) external {
        vm.assume(holder != current);

        uint256[] memory unstETHIds = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(567);
        _accountingContext.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Claimed;
        _accountingContext.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingContext.unstETHRecords[unstETHIds[0]].claimableAmount = ETHValues.from(123);

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidUnstETHHolder.selector, unstETHIds[0], current));

        AssetsAccounting.accountUnstETHWithdraw(_accountingContext, current, unstETHIds);
    }

    function testFuzz_accountUnstETHWithdraw_RevertOn_WithdrawnAmountOverflow(address holder) external {
        uint256[] memory unstETHIds = new uint256[](2);

        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingContext.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Claimed;
            _accountingContext.unstETHRecords[unstETHIds[i]].lockedBy = holder;
            _accountingContext.unstETHRecords[unstETHIds[i]].claimableAmount =
                ETHValues.from(uint256(type(uint128).max) / 2 + 1);
        }

        vm.expectRevert(ETHValueOverflow.selector);

        AssetsAccounting.accountUnstETHWithdraw(_accountingContext, holder, unstETHIds);
    }

    // ---
    // getLockedAssetsTotals
    // ---

    function testFuzz_getLockedAssetsTotals_happyPath(
        ETHValue totalFinalizedETH,
        SharesValue totalLockedShares,
        SharesValue totalUnfinalizedShares
    ) external {
        vm.assume(totalFinalizedETH.toUint256() < type(uint96).max);
        vm.assume(totalLockedShares.toUint256() < type(uint96).max);
        vm.assume(totalUnfinalizedShares.toUint256() < type(uint96).max);
        _accountingContext.unstETHTotals.finalizedETH = totalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = totalUnfinalizedShares;
        _accountingContext.stETHTotals.lockedShares = totalLockedShares;

        (SharesValue unfinalizedShares, ETHValue finalizedETH) =
            AssetsAccounting.getLockedAssetsTotals(_accountingContext);

        assertEq(unfinalizedShares, totalLockedShares + totalUnfinalizedShares);
        assertEq(finalizedETH, totalFinalizedETH);
    }

    function test_getLockedAssetsTotals_RevertOn_UnfinalizedSharesOverflow() external {
        ETHValue totalFinalizedETH = ETHValues.from(1);
        SharesValue totalUnfinalizedShares = SharesValues.from(type(uint128).max - 1);
        SharesValue totalLockedShares = SharesValues.from(type(uint128).max - 1);

        _accountingContext.unstETHTotals.finalizedETH = totalFinalizedETH;
        _accountingContext.unstETHTotals.unfinalizedShares = totalUnfinalizedShares;
        _accountingContext.stETHTotals.lockedShares = totalLockedShares;

        vm.expectRevert(SharesValueOverflow.selector);
        AssetsAccounting.getLockedAssetsTotals(_accountingContext);
    }

    // ---
    // checkMinAssetsLockDurationPassed
    // ---

    function testFuzz_checkMinAssetsLockDurationPassed_happyPath(address holder) external {
        Duration minAssetsLockDuration = Durations.from(0);
        _accountingContext.assets[holder].lastAssetsLockTimestamp = Timestamps.from(Timestamps.now().toSeconds() - 1);

        AssetsAccounting.checkMinAssetsLockDurationPassed(_accountingContext, holder, minAssetsLockDuration);
    }

    function testFuzz_checkMinAssetsLockDurationPassed_RevertOn_MinAssetsLockDurationNotPassed(address holder)
        external
    {
        Duration minAssetsLockDuration = Durations.from(1);
        _accountingContext.assets[holder].lastAssetsLockTimestamp = Timestamps.from(Timestamps.now().toSeconds() - 1);

        vm.expectRevert(
            abi.encodeWithSelector(AssetsAccounting.MinAssetsLockDurationNotPassed.selector, Timestamps.now())
        );

        AssetsAccounting.checkMinAssetsLockDurationPassed(_accountingContext, holder, minAssetsLockDuration);
    }

    // ---
    // helpers
    // ---

    function genRandomUnstEthId(uint256 salt) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, salt))); // random id
    }

    function checkAccountingContextTotalCounters(
        SharesValue lockedShares,
        ETHValue claimedETH,
        SharesValue unfinalizedShares,
        ETHValue finalizedETH
    ) internal {
        assertEq(_accountingContext.stETHTotals.lockedShares, lockedShares);
        assertEq(_accountingContext.stETHTotals.claimedETH, claimedETH);
        assertEq(_accountingContext.unstETHTotals.unfinalizedShares, unfinalizedShares);
        assertEq(_accountingContext.unstETHTotals.finalizedETH, finalizedETH);
    }

    function assertEq(UnstETHRecordStatus a, UnstETHRecordStatus b) internal {
        assertEq(uint256(a), uint256(b));
    }
}
