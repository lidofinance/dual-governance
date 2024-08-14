// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdError} from "forge-std/StdError.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ETHValue, ETHValues, ETHValueOverflow, ETHValueUnderflow} from "contracts/types/ETHValue.sol";
import {SharesValue, SharesValues, SharesValueOverflow} from "contracts/types/SharesValue.sol";
import {IndicesOneBased} from "contracts/types/IndexOneBased.sol";
import {Durations} from "contracts/types/Duration.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";
import {
    AssetsAccounting, WithdrawalRequestStatus, UnstETHRecordStatus
} from "contracts/libraries/AssetsAccounting.sol";

import {UnitTest, Duration} from "test/utils/unit-test.sol";

contract AssetsAccountingUnitTests is UnitTest {
    AssetsAccounting.Context private _accountingState;

    // ---
    // accountStETHSharesLock()
    // ---

    function testFuzz_accountStETHSharesLock_happyPath(address holder, uint128 sharesAmount) external {
        SharesValue totalLockedShares = SharesValues.from(3);
        SharesValue holderLockedShares = SharesValues.from(1);

        vm.assume(sharesAmount > 0);
        vm.assume(
            sharesAmount < type(uint128).max - Math.max(totalLockedShares.toUint256(), holderLockedShares.toUint256())
        );

        SharesValue shares = SharesValues.from(sharesAmount);

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesLocked(holder, shares);

        AssetsAccounting.accountStETHSharesLock(_accountingState, holder, shares);

        checkAccountingStateTotalCounters(totalLockedShares + shares, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
        assert(_accountingState.assets[holder].stETHLockedShares == holderLockedShares + shares);
        assert(_accountingState.assets[holder].unstETHLockedShares == SharesValues.ZERO);
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp <= Timestamps.now());
        assert(_accountingState.assets[holder].unstETHIds.length == 0);
    }

    function testFuzz_accountStETHSharesLock_RevertWhen_ZeroSharesProvided(address holder) external {
        SharesValue shares = SharesValues.ZERO;

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesLock(_accountingState, holder, shares);
    }

    function testFuzz_accountStETHSharesLock_WhenNoSharesWereLockedBefore(
        address stranger,
        uint128 sharesAmount
    ) external {
        SharesValue totalLockedShares = SharesValues.from(3);

        vm.assume(sharesAmount > 0);
        vm.assume(sharesAmount < type(uint128).max - totalLockedShares.toUint256());

        SharesValue shares = SharesValues.from(sharesAmount);

        _accountingState.stETHTotals.lockedShares = totalLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesLocked(stranger, shares);

        AssetsAccounting.accountStETHSharesLock(_accountingState, stranger, shares);

        assert(_accountingState.stETHTotals.lockedShares == totalLockedShares + shares);
        assert(_accountingState.assets[stranger].stETHLockedShares == shares);
        assert(_accountingState.assets[stranger].lastAssetsLockTimestamp <= Timestamps.now());
    }

    // ---
    // accountStETHSharesUnlock(State storage self, address holder, SharesValue shares)
    // ---

    function testFuzz_accountStETHSharesUnlock_happyPath(
        address holder,
        uint128 sharesAmount,
        uint128 holderSharesAmount
    ) external {
        SharesValue totalLockedSharesWithoutHolder = SharesValues.from(3);
        vm.assume(sharesAmount > 0);
        vm.assume(holderSharesAmount < type(uint128).max - totalLockedSharesWithoutHolder.toUint256());
        vm.assume(sharesAmount <= holderSharesAmount);

        SharesValue shares = SharesValues.from(sharesAmount);
        SharesValue holderLockedShares = SharesValues.from(holderSharesAmount);
        SharesValue totalLockedShares = totalLockedSharesWithoutHolder + holderLockedShares;

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesUnlocked(holder, shares);

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder, shares);

        checkAccountingStateTotalCounters(totalLockedShares - shares, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
        assert(_accountingState.assets[holder].stETHLockedShares == holderLockedShares - shares);
        assert(_accountingState.assets[holder].unstETHLockedShares == SharesValues.ZERO);
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp == Timestamps.ZERO);
        assert(_accountingState.assets[holder].unstETHIds.length == 0);
    }

    function testFuzz_accountStETHSharesUnlock_RevertOn_ZeroSharesProvided(address holder) external {
        SharesValue shares = SharesValues.ZERO;

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder, shares);
    }

    function testFuzz_accountStETHSharesUnlock_RevertWhen_HolderHaveLessSharesThanProvided(
        address holder,
        uint128 sharesAmount,
        uint128 holderSharesAmount
    ) external {
        SharesValue totalLockedSharesWithoutHolder = SharesValues.from(3);
        vm.assume(sharesAmount > 0);
        vm.assume(holderSharesAmount < type(uint128).max - totalLockedSharesWithoutHolder.toUint256());
        vm.assume(sharesAmount > holderSharesAmount);

        SharesValue shares = SharesValues.from(sharesAmount);
        SharesValue holderLockedShares = SharesValues.from(holderSharesAmount);
        SharesValue totalLockedShares = totalLockedSharesWithoutHolder + holderLockedShares;

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder, shares);
    }

    function testFuzz_accountStETHSharesUnlock_RevertOn_AccountingError_TotalLockedSharesCounterIsLessThanProvidedSharesAmount(
        address holder,
        uint128 sharesAmount,
        uint128 totalSharesAmount
    ) external {
        vm.assume(sharesAmount > 0);
        vm.assume(totalSharesAmount < sharesAmount);

        SharesValue shares = SharesValues.from(sharesAmount);
        SharesValue holderLockedShares = SharesValues.from(sharesAmount);
        SharesValue totalLockedShares = SharesValues.from(totalSharesAmount);

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectRevert(stdError.arithmeticError);

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder, shares);
    }

    function testFuzz_accountStETHSharesUnlock_RevertWhen_NoSharesWereLockedBefore(
        address stranger,
        uint128 sharesAmount
    ) external {
        vm.assume(sharesAmount > 0);

        SharesValue shares = SharesValues.from(sharesAmount);

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, stranger, shares);
    }

    // ---
    // accountStETHSharesUnlock(State storage self, address holder)
    // ---

    function testFuzz_accountStETHSharesUnlock_simple_happyPath(address holder, uint128 holderSharesAmount) external {
        SharesValue totalLockedSharesWithoutHolder = SharesValues.from(3);
        vm.assume(holderSharesAmount > 0);
        vm.assume(holderSharesAmount < type(uint128).max - totalLockedSharesWithoutHolder.toUint256());

        SharesValue holderLockedShares = SharesValues.from(holderSharesAmount);
        SharesValue totalLockedShares = totalLockedSharesWithoutHolder + holderLockedShares;

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesUnlocked(holder, holderLockedShares);

        SharesValue unlockedShares = AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder);

        assert(unlockedShares == holderLockedShares);
        checkAccountingStateTotalCounters(
            totalLockedShares - holderLockedShares, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO
        );
        assert(_accountingState.assets[holder].stETHLockedShares == holderLockedShares - holderLockedShares);
        assert(_accountingState.assets[holder].unstETHLockedShares == SharesValues.ZERO);
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp == Timestamps.ZERO);
        assert(_accountingState.assets[holder].unstETHIds.length == 0);
    }

    function testFuzz_accountStETHSharesUnlock_simple_RevertWhen_NoSharesWereLockedBefore(address stranger) external {
        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, SharesValues.ZERO));

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, stranger);
    }

    // ---
    // accountStETHSharesWithdraw
    // ---

    function testFuzz_accountStETHSharesWithdraw_happyPath(
        address holder,
        uint128 holderLockedSharesAmount,
        uint128 totalLockedSharesAmount,
        uint128 totalClaimedETHAmount
    ) external {
        vm.assume(totalLockedSharesAmount > 0);
        vm.assume(holderLockedSharesAmount > 0);
        vm.assume(holderLockedSharesAmount <= totalLockedSharesAmount);

        SharesValue holderLockedShares = SharesValues.from(holderLockedSharesAmount);
        SharesValue totalLockedShares = SharesValues.from(totalLockedSharesAmount);
        ETHValue totalClaimedETH = ETHValues.from(totalClaimedETHAmount);

        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;
        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.stETHTotals.claimedETH = totalClaimedETH;

        ETHValue expectedETHWithdrawn =
            ETHValues.from((uint256(totalClaimedETHAmount) * holderLockedSharesAmount) / totalLockedSharesAmount);

        vm.expectEmit();
        emit AssetsAccounting.ETHWithdrawn(holder, holderLockedShares, expectedETHWithdrawn);

        ETHValue ethWithdrawn = AssetsAccounting.accountStETHSharesWithdraw(_accountingState, holder);

        assert(ethWithdrawn == expectedETHWithdrawn);
        checkAccountingStateTotalCounters(totalLockedShares, totalClaimedETH, SharesValues.ZERO, ETHValues.ZERO);
        assert(_accountingState.assets[holder].stETHLockedShares == SharesValues.ZERO);
        assert(_accountingState.assets[holder].unstETHLockedShares == SharesValues.ZERO);
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp == Timestamps.ZERO);
        assert(_accountingState.assets[holder].unstETHIds.length == 0);
    }

    function testFuzz_accountStETHSharesWithdraw_RevertWhen_HolderHaveZeroShares(address stranger) external {
        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, SharesValues.ZERO));

        AssetsAccounting.accountStETHSharesWithdraw(_accountingState, stranger);
    }

    function testFuzz_accountStETHSharesWithdraw_RevertOn_AccountingError_TotalLockedSharesCounterIsZero(
        address holder,
        uint128 holderLockedSharesAmount,
        uint128 totalClaimedETHAmount
    ) external {
        vm.assume(holderLockedSharesAmount > 0);

        SharesValue holderLockedShares = SharesValues.from(holderLockedSharesAmount);
        ETHValue totalClaimedETH = ETHValues.from(totalClaimedETHAmount);

        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;
        _accountingState.stETHTotals.lockedShares = SharesValues.ZERO;
        _accountingState.stETHTotals.claimedETH = totalClaimedETH;

        vm.expectRevert(stdError.divisionError);

        AssetsAccounting.accountStETHSharesWithdraw(_accountingState, holder);
    }

    function testFuzz_accountStETHSharesWithdraw_AccountingError_WithdrawAmountMoreThanTotalClaimedETH(
        address holder,
        uint128 holderLockedSharesAmount,
        uint128 totalClaimedETHAmount
    ) external {
        uint128 totalLockedSharesAmount = 10;
        vm.assume(holderLockedSharesAmount > totalLockedSharesAmount);
        vm.assume(holderLockedSharesAmount < type(uint64).max);
        vm.assume(totalClaimedETHAmount < type(uint64).max);

        SharesValue holderLockedShares = SharesValues.from(holderLockedSharesAmount);
        SharesValue totalLockedShares = SharesValues.from(totalLockedSharesAmount);
        ETHValue totalClaimedETH = ETHValues.from(totalClaimedETHAmount);

        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;
        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.stETHTotals.claimedETH = totalClaimedETH;

        ETHValue expectedETHWithdrawn =
            ETHValues.from((uint256(totalClaimedETHAmount) * holderLockedSharesAmount) / totalLockedSharesAmount);

        vm.expectEmit();
        emit AssetsAccounting.ETHWithdrawn(holder, holderLockedShares, expectedETHWithdrawn);

        ETHValue ethWithdrawn = AssetsAccounting.accountStETHSharesWithdraw(_accountingState, holder);

        assert(ethWithdrawn == expectedETHWithdrawn);
        assert(ethWithdrawn.toUint256() >= totalClaimedETHAmount);
        assert(_accountingState.assets[holder].stETHLockedShares == SharesValues.ZERO);
    }

    function testFuzz_accountStETHSharesWithdraw_RevertOn_AccountingError_WithdrawAmountOverflow(address holder)
        external
    {
        SharesValue holderLockedShares = SharesValues.from(type(uint96).max);
        SharesValue totalLockedShares = SharesValues.from(1);
        ETHValue totalClaimedETH = ETHValues.from(type(uint96).max);

        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;
        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.stETHTotals.claimedETH = totalClaimedETH;

        vm.expectRevert(ETHValueOverflow.selector);

        AssetsAccounting.accountStETHSharesWithdraw(_accountingState, holder);
    }

    // ---
    // accountClaimedStETH
    // ---

    function testFuzz_accountClaimedStETH_happyPath(uint128 ethAmount, uint128 totalClaimedETHAmount) external {
        vm.assume(ethAmount < type(uint128).max / 2);
        vm.assume(totalClaimedETHAmount < type(uint128).max / 2);

        ETHValue amount = ETHValues.from(ethAmount);
        ETHValue totalClaimedETH = ETHValues.from(totalClaimedETHAmount);

        _accountingState.stETHTotals.claimedETH = totalClaimedETH;

        vm.expectEmit();
        emit AssetsAccounting.ETHClaimed(amount);

        AssetsAccounting.accountClaimedStETH(_accountingState, amount);

        checkAccountingStateTotalCounters(
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
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(amountsOfShares.length > 1);
        vm.assume(amountsOfShares.length <= 500);

        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);
        uint256 expectedTotalUnstETHLockedAmount = 0;

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.assets[holder].unstETHIds.push(genRandomUnstEthId(1024));
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
            expectedTotalUnstETHLockedAmount += amountsOfShares[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHLocked(holder, unstETHIds, SharesValues.from(expectedTotalUnstETHLockedAmount));
        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);

        checkAccountingStateTotalCounters(
            SharesValues.ZERO,
            ETHValues.ZERO,
            initialTotalUnfinalizedShares + SharesValues.from(expectedTotalUnstETHLockedAmount),
            ETHValues.ZERO
        );
        assert(_accountingState.assets[holder].stETHLockedShares == SharesValues.ZERO);
        assert(
            _accountingState.assets[holder].unstETHLockedShares
                == holderUnstETHLockedShares + SharesValues.from(expectedTotalUnstETHLockedAmount)
        );
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp <= Timestamps.now());
        assert(_accountingState.assets[holder].unstETHIds.length == amountsOfShares.length + 1);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assert(_accountingState.unstETHRecords[unstETHIds[i]].lockedBy == holder);
            assert(_accountingState.unstETHRecords[unstETHIds[i]].status == UnstETHRecordStatus.Locked);
            assert(_accountingState.unstETHRecords[unstETHIds[i]].index.toZeroBasedValue() == i + 1);
            assert(_accountingState.unstETHRecords[unstETHIds[i]].shares == SharesValues.from(amountsOfShares[i]));
            assert(_accountingState.unstETHRecords[unstETHIds[i]].claimableAmount == ETHValues.ZERO);
        }
    }

    function testFuzz_accountUnstETHLock_RevertOn_UnstETHIdsLengthNotEqualToWithdrawalRequestStatusesLength(
        address holder
    ) external {
        WithdrawalRequestStatus[] memory withdrawalRequestStatuses = new WithdrawalRequestStatus[](1);
        uint256[] memory unstETHIds = new uint256[](0);

        vm.expectRevert(stdError.assertionError);

        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_RevertOn_WithdrawalRequestStatusIsFinalized(
        address holder,
        uint96[] memory amountsOfShares,
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);

        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
        }

        withdrawalRequestStatuses[withdrawalRequestStatuses.length - 1].isFinalized = true;

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector,
                unstETHIds[unstETHIds.length - 1],
                UnstETHRecordStatus.Finalized
            )
        );

        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_RevertOn_WithdrawalRequestStatusIsClaimed(
        address holder,
        uint96[] memory amountsOfShares,
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);

        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
        }

        withdrawalRequestStatuses[withdrawalRequestStatuses.length - 1].isClaimed = true;

        vm.expectRevert(stdError.assertionError);

        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_RevertOn_UnstETHRecordStatusIsNot_NotLocked(
        address holder,
        uint96[] memory amountsOfShares,
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);

        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
        }

        _accountingState.unstETHRecords[unstETHIds[unstETHIds.length - 1]].status = UnstETHRecordStatus.Withdrawn;

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector,
                unstETHIds[unstETHIds.length - 1],
                UnstETHRecordStatus.Withdrawn
            )
        );

        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_RevertWhen_DuplicatingUnstETHIdsProvided(
        address holder,
        uint96[] memory amountsOfShares,
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(amountsOfShares.length > 1);
        vm.assume(amountsOfShares.length <= 500);

        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        WithdrawalRequestStatus[] memory withdrawalRequestStatuses =
            new WithdrawalRequestStatus[](amountsOfShares.length);
        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            withdrawalRequestStatuses[i].amountOfShares = amountsOfShares[i];
            withdrawalRequestStatuses[i].isFinalized = false;
            withdrawalRequestStatuses[i].isClaimed = false;
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.NotLocked;
        }

        unstETHIds[unstETHIds.length - 1] = unstETHIds[unstETHIds.length - 2];

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector,
                unstETHIds[unstETHIds.length - 1],
                UnstETHRecordStatus.Locked
            )
        );

        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);
    }

    // TODO: is it expected behavior?
    function testFuzz_accountUnstETHLock_WhenNoUnstETHIdsProvided(
        address holder,
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        WithdrawalRequestStatus[] memory withdrawalRequestStatuses = new WithdrawalRequestStatus[](0);
        uint256[] memory unstETHIds = new uint256[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHLocked(holder, unstETHIds, SharesValues.ZERO);
        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);

        checkAccountingStateTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, ETHValues.ZERO
        );
        assert(_accountingState.assets[holder].stETHLockedShares == SharesValues.ZERO);
        assert(_accountingState.assets[holder].unstETHLockedShares == holderUnstETHLockedShares);
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp <= Timestamps.now());
        assert(_accountingState.assets[holder].unstETHIds.length == 0);
    }

    function testFuzz_accountUnstETHLock_AccountingError_WithdrawalRequestStatusAmountOfSharesOverflow(
        address holder,
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        WithdrawalRequestStatus[] memory withdrawalRequestStatuses = new WithdrawalRequestStatus[](1);
        uint256[] memory unstETHIds = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(0);
        withdrawalRequestStatuses[0].amountOfShares = uint256(type(uint128).max) + 1;
        withdrawalRequestStatuses[0].isFinalized = false;
        withdrawalRequestStatuses[0].isClaimed = false;
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.NotLocked;

        vm.expectRevert(SharesValueOverflow.selector);

        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_AccountingError_HolderUnstETHLockedSharesOverflow(
        address holder,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        SharesValue holderUnstETHLockedShares = SharesValues.from(type(uint128).max / 2 + 1);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        WithdrawalRequestStatus[] memory withdrawalRequestStatuses = new WithdrawalRequestStatus[](1);
        uint256[] memory unstETHIds = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(0);
        withdrawalRequestStatuses[0].amountOfShares = uint128(type(uint128).max / 2) + 1;
        withdrawalRequestStatuses[0].isFinalized = false;
        withdrawalRequestStatuses[0].isClaimed = false;
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.NotLocked;

        vm.expectRevert(stdError.arithmeticError);

        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);
    }

    function testFuzz_accountUnstETHLock_AccountingError_TotalUnfinalizedSharesOverflow(
        address holder,
        uint96 holderUnstETHLockedSharesAmount
    ) external {
        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(type(uint128).max / 2 + 1);

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        WithdrawalRequestStatus[] memory withdrawalRequestStatuses = new WithdrawalRequestStatus[](1);
        uint256[] memory unstETHIds = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(0);
        withdrawalRequestStatuses[0].amountOfShares = uint128(type(uint128).max / 2) + 1;
        withdrawalRequestStatuses[0].isFinalized = false;
        withdrawalRequestStatuses[0].isClaimed = false;
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.NotLocked;

        vm.expectRevert(stdError.arithmeticError);

        AssetsAccounting.accountUnstETHLock(_accountingState, holder, unstETHIds, withdrawalRequestStatuses);
    }

    // ---
    // accountUnstETHUnlock
    // ---

    // TODO: make a research on gas consumption when a lot of unstNFTs provided.
    function testFuzz_accountUnstETHUnlock_happyPath(
        address holder,
        uint64[] memory amountsOfShares,
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);
        vm.assume(holderUnstETHLockedSharesAmount > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalUnfinalizedSharesAmount > 500 * uint128(type(uint64).max));

        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);
        uint256 expectedTotalSharesUnlockedAmount = 0;

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingState.unstETHRecords[unstETHIds[i]].lockedBy = holder;
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Locked;
            _accountingState.unstETHRecords[unstETHIds[i]].shares = SharesValues.from(amountsOfShares[i]);
            _accountingState.unstETHRecords[unstETHIds[i]].index = IndicesOneBased.fromOneBasedValue(i + 1);
            _accountingState.assets[holder].unstETHIds.push(unstETHIds[i]);
            expectedTotalSharesUnlockedAmount += amountsOfShares[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHUnlocked(
            holder, unstETHIds, SharesValues.from(expectedTotalSharesUnlockedAmount), ETHValues.ZERO
        );

        AssetsAccounting.accountUnstETHUnlock(_accountingState, holder, unstETHIds);

        checkAccountingStateTotalCounters(
            SharesValues.ZERO,
            ETHValues.ZERO,
            initialTotalUnfinalizedShares - SharesValues.from(expectedTotalSharesUnlockedAmount),
            initialTotalFinalizedETH
        );
        assert(_accountingState.assets[holder].stETHLockedShares == SharesValues.ZERO);
        assert(
            _accountingState.assets[holder].unstETHLockedShares
                == holderUnstETHLockedShares - SharesValues.from(expectedTotalSharesUnlockedAmount)
        );
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp == Timestamps.ZERO);
        assert(_accountingState.assets[holder].unstETHIds.length == 0);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assert(_accountingState.unstETHRecords[unstETHIds[i]].shares == SharesValues.ZERO);
        }
    }

    function testFuzz_accountUnstETHUnlock_WhenFinalizedUnstETHUnlocked(
        address holder,
        uint64[] memory amountsOfShares,
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(amountsOfShares.length > 0);
        vm.assume(amountsOfShares.length <= 500);
        vm.assume(holderUnstETHLockedSharesAmount > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalFinalizedETHAmount > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalUnfinalizedSharesAmount > 500 * uint128(type(uint64).max));

        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);
        uint256 expectedTotalSharesUnlockedAmount = 0;

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](amountsOfShares.length);

        for (uint256 i = 0; i < amountsOfShares.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingState.unstETHRecords[unstETHIds[i]].lockedBy = holder;
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Finalized;
            _accountingState.unstETHRecords[unstETHIds[i]].shares = SharesValues.from(amountsOfShares[i]);
            _accountingState.unstETHRecords[unstETHIds[i]].claimableAmount = ETHValues.from(amountsOfShares[i]);
            _accountingState.unstETHRecords[unstETHIds[i]].index = IndicesOneBased.fromOneBasedValue(i + 1);
            _accountingState.assets[holder].unstETHIds.push(unstETHIds[i]);
            expectedTotalSharesUnlockedAmount += amountsOfShares[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHUnlocked(
            holder,
            unstETHIds,
            SharesValues.from(expectedTotalSharesUnlockedAmount),
            ETHValues.from(expectedTotalSharesUnlockedAmount)
        );

        AssetsAccounting.accountUnstETHUnlock(_accountingState, holder, unstETHIds);

        checkAccountingStateTotalCounters(
            SharesValues.ZERO,
            ETHValues.ZERO,
            initialTotalUnfinalizedShares,
            initialTotalFinalizedETH - ETHValues.from(expectedTotalSharesUnlockedAmount)
        );
        assert(_accountingState.assets[holder].stETHLockedShares == SharesValues.ZERO);
        assert(
            _accountingState.assets[holder].unstETHLockedShares
                == holderUnstETHLockedShares - SharesValues.from(expectedTotalSharesUnlockedAmount)
        );
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp == Timestamps.ZERO);
        assert(_accountingState.assets[holder].unstETHIds.length == 0);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assert(_accountingState.unstETHRecords[unstETHIds[i]].shares == SharesValues.ZERO);
        }
    }

    function testFuzz_accountUnstETHUnlock_RevertWhen_UnknownUnstETHIdProvided(address holder) external {
        vm.assume(holder != address(0x0));

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);

        vm.expectRevert(
            abi.encodeWithSelector(AssetsAccounting.InvalidUnstETHHolder.selector, unstETHIds[0], holder, address(0x0))
        );

        AssetsAccounting.accountUnstETHUnlock(_accountingState, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertWhen_UnstETHRecordDoesNotBelongToCurrent(
        address holder,
        address current
    ) external {
        vm.assume(holder != current);

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingState.unstETHRecords[unstETHIds[0]].lockedBy = holder;

        vm.expectRevert(
            abi.encodeWithSelector(AssetsAccounting.InvalidUnstETHHolder.selector, unstETHIds[0], current, holder)
        );

        AssetsAccounting.accountUnstETHUnlock(_accountingState, current, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertWhen_UnstETHRecordStatusInvalid(address holder) external {
        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingState.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.NotLocked;

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidUnstETHStatus.selector, unstETHIds[0], UnstETHRecordStatus.NotLocked
            )
        );

        AssetsAccounting.accountUnstETHUnlock(_accountingState, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertWhen_UnstETHRecordIndexInvalid_OOB(address holder) external {
        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingState.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingState.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(1234);
        _accountingState.unstETHRecords[unstETHIds[0]].index = IndicesOneBased.fromOneBasedValue(10);
        _accountingState.assets[holder].unstETHIds.push(unstETHIds[0]);

        vm.expectRevert(stdError.indexOOBError);

        AssetsAccounting.accountUnstETHUnlock(_accountingState, holder, unstETHIds);
    }

    // TODO: is it expected behavior?
    function testFuzz_accountUnstETHUnlock_WhenNoUnstETHIdsProvided(
        address holder,
        uint96 holderUnstETHLockedSharesAmount,
        uint96 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(holderUnstETHLockedSharesAmount > 500 * uint128(type(uint64).max));
        vm.assume(initialTotalUnfinalizedSharesAmount > 500 * uint128(type(uint64).max));

        SharesValue holderUnstETHLockedShares = SharesValues.from(holderUnstETHLockedSharesAmount);
        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.assets[holder].unstETHLockedShares = holderUnstETHLockedShares;
        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHUnlocked(holder, unstETHIds, SharesValues.ZERO, ETHValues.ZERO);

        AssetsAccounting.accountUnstETHUnlock(_accountingState, holder, unstETHIds);

        checkAccountingStateTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, initialTotalFinalizedETH
        );
        assert(_accountingState.assets[holder].stETHLockedShares == SharesValues.ZERO);
        assert(_accountingState.assets[holder].unstETHLockedShares == holderUnstETHLockedShares);
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp == Timestamps.ZERO);
        assert(_accountingState.assets[holder].unstETHIds.length == 0);
    }

    function testFuzz_accountUnstETHUnlock_RevertOn_AccountingError_HolderUnstETHLockedSharesUnderflow(address holder)
        external
    {
        _accountingState.assets[holder].unstETHLockedShares = SharesValues.from(5);

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingState.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingState.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(10);
        _accountingState.unstETHRecords[unstETHIds[0]].index = IndicesOneBased.fromOneBasedValue(1);
        _accountingState.assets[holder].unstETHIds.push(unstETHIds[0]);

        vm.expectRevert(stdError.arithmeticError);

        AssetsAccounting.accountUnstETHUnlock(_accountingState, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertOn_AccountingError_TotalFinalizedETHUnderflow(address holder)
        external
    {
        _accountingState.assets[holder].unstETHLockedShares = SharesValues.from(10);
        _accountingState.unstETHTotals.finalizedETH = ETHValues.from(5);

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingState.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Finalized;
        _accountingState.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(5);
        _accountingState.unstETHRecords[unstETHIds[0]].index = IndicesOneBased.fromOneBasedValue(1);
        _accountingState.unstETHRecords[unstETHIds[0]].claimableAmount = ETHValues.from(10);
        _accountingState.assets[holder].unstETHIds.push(unstETHIds[0]);

        vm.expectRevert(ETHValueUnderflow.selector);

        AssetsAccounting.accountUnstETHUnlock(_accountingState, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHUnlock_RevertOn_AccountingError_TotalUnfinalizedSharesUnderflow(address holder)
        external
    {
        _accountingState.assets[holder].unstETHLockedShares = SharesValues.from(10);
        _accountingState.unstETHTotals.unfinalizedShares = SharesValues.from(5);

        uint256[] memory unstETHIds = new uint256[](1);
        unstETHIds[0] = genRandomUnstEthId(1234);
        _accountingState.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingState.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(10);
        _accountingState.unstETHRecords[unstETHIds[0]].index = IndicesOneBased.fromOneBasedValue(1);
        _accountingState.assets[holder].unstETHIds.push(unstETHIds[0]);

        vm.expectRevert(stdError.arithmeticError);

        AssetsAccounting.accountUnstETHUnlock(_accountingState, holder, unstETHIds);
    }

    // ---
    // accountUnstETHFinalized
    // ---

    // TODO: make a research on gas consumption when a lot of unstNFTs provided.
    function testFuzz_accountUnstETHFinalized_happyPath(
        uint64[] memory claimableAmounts,
        uint96 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(claimableAmounts.length > 0);
        vm.assume(claimableAmounts.length <= 500);
        vm.assume(initialTotalUnfinalizedSharesAmount > 500 * uint128(type(uint64).max));

        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);
        uint256 expectedTotalSharesFinalized = 0;
        uint256 expectedTotalAmountFinalized = 0;

        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](claimableAmounts.length);
        uint256[] memory claimableAmountsPrepared = new uint256[](claimableAmounts.length);

        for (uint256 i = 0; i < claimableAmounts.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Locked;
            uint256 sharesAmount = 5 * uint256(claimableAmounts[i]);
            _accountingState.unstETHRecords[unstETHIds[i]].shares = SharesValues.from(sharesAmount);
            expectedTotalSharesFinalized += sharesAmount;
            expectedTotalAmountFinalized += claimableAmounts[i];
            claimableAmountsPrepared[i] = claimableAmounts[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(
            unstETHIds, SharesValues.from(expectedTotalSharesFinalized), ETHValues.from(expectedTotalAmountFinalized)
        );

        AssetsAccounting.accountUnstETHFinalized(_accountingState, unstETHIds, claimableAmountsPrepared);

        checkAccountingStateTotalCounters(
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

        AssetsAccounting.accountUnstETHFinalized(_accountingState, unstETHIds, claimableAmountsPrepared);
    }

    function testFuzz_accountUnstETHFinalized_When_NoClaimableAmountsProvided(
        uint96 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(initialTotalUnfinalizedSharesAmount > 500 * uint128(type(uint64).max));

        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](0);
        uint256[] memory claimableAmountsPrepared = new uint256[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(unstETHIds, SharesValues.from(0), ETHValues.from(0));

        AssetsAccounting.accountUnstETHFinalized(_accountingState, unstETHIds, claimableAmountsPrepared);

        checkAccountingStateTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, initialTotalFinalizedETH
        );
    }

    function testFuzz_accountUnstETHFinalized_When_UnstETHRecordNotFound(
        uint64 claimableAmount,
        uint96 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(initialTotalUnfinalizedSharesAmount > 500 * uint128(type(uint64).max));

        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        claimableAmountsPrepared[0] = claimableAmount;

        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(unstETHIds, SharesValues.from(0), ETHValues.from(0));

        AssetsAccounting.accountUnstETHFinalized(_accountingState, unstETHIds, claimableAmountsPrepared);

        checkAccountingStateTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, initialTotalFinalizedETH
        );
    }

    function testFuzz_accountUnstETHFinalized_When_ClaimableAmountIsZero(
        uint96 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(initialTotalUnfinalizedSharesAmount > 500 * uint128(type(uint64).max));

        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingState.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(123);
        claimableAmountsPrepared[0] = 0;

        vm.expectEmit();
        emit AssetsAccounting.UnstETHFinalized(unstETHIds, SharesValues.from(0), ETHValues.from(0));

        AssetsAccounting.accountUnstETHFinalized(_accountingState, unstETHIds, claimableAmountsPrepared);

        checkAccountingStateTotalCounters(
            SharesValues.ZERO, ETHValues.ZERO, initialTotalUnfinalizedShares, initialTotalFinalizedETH
        );
    }

    function testFuzz_accountUnstETHFinalized_RevertOn_ClaimableAmountOverflow(
        uint96 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(initialTotalUnfinalizedSharesAmount > 500 * uint128(type(uint64).max));

        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingState.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(123);
        claimableAmountsPrepared[0] = uint256(type(uint128).max) + 1;

        vm.expectRevert(ETHValueOverflow.selector);

        AssetsAccounting.accountUnstETHFinalized(_accountingState, unstETHIds, claimableAmountsPrepared);
    }

    function testFuzz_accountUnstETHFinalized_RevertOn_TotalFinalizedETHOverflow(
        uint128 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(initialTotalFinalizedETHAmount > type(uint96).max);

        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingState.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(123);
        claimableAmountsPrepared[0] = uint256(type(uint128).max - 2);

        vm.expectRevert(stdError.arithmeticError);

        AssetsAccounting.accountUnstETHFinalized(_accountingState, unstETHIds, claimableAmountsPrepared);
    }

    function testFuzz_accountUnstETHFinalized_RevertOn_TotalUnfinalizedSharesUnderflow(
        uint96 initialTotalFinalizedETHAmount,
        uint96 initialTotalUnfinalizedSharesAmount
    ) external {
        vm.assume(initialTotalUnfinalizedSharesAmount < type(uint64).max);

        ETHValue initialTotalFinalizedETH = ETHValues.from(initialTotalFinalizedETHAmount);
        SharesValue initialTotalUnfinalizedShares = SharesValues.from(initialTotalUnfinalizedSharesAmount);

        _accountingState.unstETHTotals.finalizedETH = initialTotalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = initialTotalUnfinalizedShares;

        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(9876);
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        _accountingState.unstETHRecords[unstETHIds[0]].shares = SharesValues.from(type(uint64).max);
        claimableAmountsPrepared[0] = 1;

        vm.expectRevert(stdError.arithmeticError);

        AssetsAccounting.accountUnstETHFinalized(_accountingState, unstETHIds, claimableAmountsPrepared);
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
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Locked;
            expectedTotalAmountClaimed += claimableAmounts[i];
            claimableAmountsPrepared[i] = claimableAmounts[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHClaimed(unstETHIds, ETHValues.from(expectedTotalAmountClaimed));

        AssetsAccounting.accountUnstETHClaimed(_accountingState, unstETHIds, claimableAmountsPrepared);

        checkAccountingStateTotalCounters(SharesValues.ZERO, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assert(
                _accountingState.unstETHRecords[unstETHIds[i]].claimableAmount == ETHValues.from(claimableAmounts[i])
            );
            assert(_accountingState.unstETHRecords[unstETHIds[i]].status == UnstETHRecordStatus.Claimed);
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
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Locked;
            claimableAmountsPrepared[i] = claimableAmounts[i];
        }

        vm.expectRevert(stdError.indexOOBError);

        AssetsAccounting.accountUnstETHClaimed(_accountingState, unstETHIds, claimableAmountsPrepared);
    }

    function test_accountUnstETHClaimed_WhenNoUnstETHIdsProvided() external {
        uint256 expectedTotalAmountClaimed = 0;

        uint256[] memory unstETHIds = new uint256[](0);
        uint256[] memory claimableAmountsPrepared = new uint256[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHClaimed(unstETHIds, ETHValues.from(expectedTotalAmountClaimed));

        AssetsAccounting.accountUnstETHClaimed(_accountingState, unstETHIds, claimableAmountsPrepared);

        checkAccountingStateTotalCounters(SharesValues.ZERO, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
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

        AssetsAccounting.accountUnstETHClaimed(_accountingState, unstETHIds, claimableAmountsPrepared);
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
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Finalized;
            _accountingState.unstETHRecords[unstETHIds[i]].claimableAmount =
                ETHValues.from(uint256(claimableAmounts[i]) + 1);
            claimableAmountsPrepared[i] = claimableAmounts[i];
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                AssetsAccounting.InvalidClaimableAmount.selector,
                unstETHIds[0],
                claimableAmounts[0],
                uint256(claimableAmounts[0]) + 1
            )
        );

        AssetsAccounting.accountUnstETHClaimed(_accountingState, unstETHIds, claimableAmountsPrepared);
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
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Finalized;
            _accountingState.unstETHRecords[unstETHIds[i]].claimableAmount = ETHValues.from(claimableAmounts[i]);
            claimableAmountsPrepared[i] = claimableAmounts[i];
            expectedTotalAmountClaimed += claimableAmounts[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHClaimed(unstETHIds, ETHValues.from(expectedTotalAmountClaimed));

        AssetsAccounting.accountUnstETHClaimed(_accountingState, unstETHIds, claimableAmountsPrepared);

        checkAccountingStateTotalCounters(SharesValues.ZERO, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assert(
                _accountingState.unstETHRecords[unstETHIds[i]].claimableAmount == ETHValues.from(claimableAmounts[i])
            );
            assert(_accountingState.unstETHRecords[unstETHIds[i]].status == UnstETHRecordStatus.Claimed);
        }
    }

    function test_accountUnstETHClaimed_RevertWhen_ClaimableAmountsOverflow() external {
        uint256[] memory unstETHIds = new uint256[](1);
        uint256[] memory claimableAmountsPrepared = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(1);
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Locked;
        claimableAmountsPrepared[0] = uint256(type(uint128).max) + 1;

        vm.expectRevert(ETHValueOverflow.selector);

        AssetsAccounting.accountUnstETHClaimed(_accountingState, unstETHIds, claimableAmountsPrepared);
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
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Claimed;
            _accountingState.unstETHRecords[unstETHIds[i]].lockedBy = holder;
            _accountingState.unstETHRecords[unstETHIds[i]].claimableAmount = ETHValues.from(claimableAmounts[i]);
            expectedAmountWithdrawn += claimableAmounts[i];
        }

        vm.expectEmit();
        emit AssetsAccounting.UnstETHWithdrawn(unstETHIds, ETHValues.from(expectedAmountWithdrawn));

        ETHValue amountWithdrawn = AssetsAccounting.accountUnstETHWithdraw(_accountingState, holder, unstETHIds);

        assert(amountWithdrawn == ETHValues.from(expectedAmountWithdrawn));

        checkAccountingStateTotalCounters(SharesValues.ZERO, ETHValues.ZERO, SharesValues.ZERO, ETHValues.ZERO);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assert(
                _accountingState.unstETHRecords[unstETHIds[i]].claimableAmount == ETHValues.from(claimableAmounts[i])
            );
            assert(_accountingState.unstETHRecords[unstETHIds[i]].status == UnstETHRecordStatus.Withdrawn);
            assert(_accountingState.unstETHRecords[unstETHIds[i]].lockedBy == holder);
        }
    }

    function testFuzz_accountUnstETHWithdraw_WhenNoUnstETHIdsProvided(address holder) external {
        uint256[] memory unstETHIds = new uint256[](0);

        vm.expectEmit();
        emit AssetsAccounting.UnstETHWithdrawn(unstETHIds, ETHValues.ZERO);

        ETHValue amountWithdrawn = AssetsAccounting.accountUnstETHWithdraw(_accountingState, holder, unstETHIds);

        assert(amountWithdrawn == ETHValues.ZERO);
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

        AssetsAccounting.accountUnstETHWithdraw(_accountingState, holder, unstETHIds);
    }

    function testFuzz_accountUnstETHWithdraw_RevertWhen_UnstETHRecordDoesNotBelongToCurrent(
        address holder,
        address current
    ) external {
        vm.assume(holder != current);

        uint256[] memory unstETHIds = new uint256[](1);

        unstETHIds[0] = genRandomUnstEthId(567);
        _accountingState.unstETHRecords[unstETHIds[0]].status = UnstETHRecordStatus.Claimed;
        _accountingState.unstETHRecords[unstETHIds[0]].lockedBy = holder;
        _accountingState.unstETHRecords[unstETHIds[0]].claimableAmount = ETHValues.from(123);

        vm.expectRevert(
            abi.encodeWithSelector(AssetsAccounting.InvalidUnstETHHolder.selector, unstETHIds[0], current, holder)
        );

        AssetsAccounting.accountUnstETHWithdraw(_accountingState, current, unstETHIds);
    }

    function testFuzz_accountUnstETHWithdraw_RevertOn_WithdrawnAmountOverflow(address holder) external {
        uint256[] memory unstETHIds = new uint256[](2);

        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            unstETHIds[i] = genRandomUnstEthId(i);
            _accountingState.unstETHRecords[unstETHIds[i]].status = UnstETHRecordStatus.Claimed;
            _accountingState.unstETHRecords[unstETHIds[i]].lockedBy = holder;
            _accountingState.unstETHRecords[unstETHIds[i]].claimableAmount =
                ETHValues.from(uint256(type(uint128).max) / 2 + 1);
        }

        vm.expectRevert(stdError.arithmeticError);

        AssetsAccounting.accountUnstETHWithdraw(_accountingState, holder, unstETHIds);
    }

    // ---
    // getLockedAssetsTotals
    // ---

    function testFuzz_getLockedAssetsTotals_happyPath(
        uint96 totalFinalizedETHAmount,
        uint96 totalLockedSharesAmount,
        uint96 totalUnfinalizedSharesAmount
    ) external {
        ETHValue totalFinalizedETH = ETHValues.from(totalFinalizedETHAmount);
        SharesValue totalUnfinalizedShares = SharesValues.from(totalUnfinalizedSharesAmount);
        SharesValue totalLockedShares = SharesValues.from(totalLockedSharesAmount);

        _accountingState.unstETHTotals.finalizedETH = totalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = totalUnfinalizedShares;
        _accountingState.stETHTotals.lockedShares = totalLockedShares;

        (SharesValue unfinalizedShares, ETHValue finalizedETH) =
            AssetsAccounting.getLockedAssetsTotals(_accountingState);

        assert(unfinalizedShares == totalLockedShares + totalUnfinalizedShares);
        assert(finalizedETH == totalFinalizedETH);
    }

    function test_getLockedAssetsTotals_RevertOn_UnfinalizedSharesOverflow() external {
        ETHValue totalFinalizedETH = ETHValues.from(1);
        SharesValue totalUnfinalizedShares = SharesValues.from(type(uint128).max - 1);
        SharesValue totalLockedShares = SharesValues.from(type(uint128).max - 1);

        _accountingState.unstETHTotals.finalizedETH = totalFinalizedETH;
        _accountingState.unstETHTotals.unfinalizedShares = totalUnfinalizedShares;
        _accountingState.stETHTotals.lockedShares = totalLockedShares;

        vm.expectRevert(stdError.arithmeticError);
        AssetsAccounting.getLockedAssetsTotals(_accountingState);
    }

    // ---
    // checkMinAssetsLockDurationPassed
    // ---

    function testFuzz_checkMinAssetsLockDurationPassed_happyPath(address holder) external {
        Duration minAssetsLockDuration = Durations.from(0);
        _accountingState.assets[holder].lastAssetsLockTimestamp = Timestamps.from(Timestamps.now().toSeconds() - 1);

        AssetsAccounting.checkMinAssetsLockDurationPassed(_accountingState, holder, minAssetsLockDuration);
    }

    function testFuzz_checkMinAssetsLockDurationPassed_RevertOn_MinAssetsLockDurationNotPassed(address holder)
        external
    {
        Duration minAssetsLockDuration = Durations.from(1);
        _accountingState.assets[holder].lastAssetsLockTimestamp = Timestamps.from(Timestamps.now().toSeconds() - 1);

        vm.expectRevert(
            abi.encodeWithSelector(AssetsAccounting.MinAssetsLockDurationNotPassed.selector, Timestamps.now())
        );

        AssetsAccounting.checkMinAssetsLockDurationPassed(_accountingState, holder, minAssetsLockDuration);
    }

    // ---
    // helpers
    // ---

    function genRandomUnstEthId(uint256 salt) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, salt))); // random id
    }

    function checkAccountingStateTotalCounters(
        SharesValue lockedShares,
        ETHValue claimedETH,
        SharesValue unfinalizedShares,
        ETHValue finalizedETH
    ) internal view {
        assert(_accountingState.stETHTotals.lockedShares == lockedShares);
        assert(_accountingState.stETHTotals.claimedETH == claimedETH);
        assert(_accountingState.unstETHTotals.unfinalizedShares == unfinalizedShares);
        assert(_accountingState.unstETHTotals.finalizedETH == finalizedETH);
    }
}
