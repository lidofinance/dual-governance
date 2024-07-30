// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ETHValue, ETHValues} from "contracts/types/ETHValue.sol";
import {SharesValue, SharesValues} from "contracts/types/SharesValue.sol";
import {AssetsAccounting, HolderAssets, StETHAccounting} from "contracts/libraries/AssetsAccounting.sol";

import {UnitTest, Duration, Durations, Timestamp, Timestamps} from "test/utils/unit-test.sol";

contract AssetsAccountingUnitTests is UnitTest {
    AssetsAccounting.State private _accountingState;

    // ---
    // accountStETHSharesLock()
    // ---

    function testFuzz_accountStETHSharesLock_happyPath(address holder, uint128 sharesAmount) external {
        SharesValue totalLockedShares = SharesValues.from(3);
        SharesValue holderLockedShares = SharesValues.from(1);

        vm.assume(sharesAmount > SharesValues.ZERO.toUint256());
        vm.assume(
            sharesAmount < type(uint128).max - Math.max(totalLockedShares.toUint256(), holderLockedShares.toUint256())
        );

        SharesValue shares = SharesValues.from(sharesAmount);

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesLocked(holder, shares);

        AssetsAccounting.accountStETHSharesLock(_accountingState, holder, shares);

        assert(_accountingState.stETHTotals.lockedShares == totalLockedShares + shares);
        assert(_accountingState.assets[holder].stETHLockedShares == holderLockedShares + shares);
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp <= Timestamps.now());

        _accountingState.assets[holder].stETHLockedShares = SharesValues.ZERO;
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
        SharesValue holderLockedShares = SharesValues.from(1);

        vm.assume(sharesAmount > SharesValues.ZERO.toUint256());
        vm.assume(
            sharesAmount < type(uint128).max - Math.max(totalLockedShares.toUint256(), holderLockedShares.toUint256())
        );

        SharesValue shares = SharesValues.from(sharesAmount);

        _accountingState.stETHTotals.lockedShares = totalLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesLocked(stranger, shares);

        AssetsAccounting.accountStETHSharesLock(_accountingState, stranger, shares);

        assert(_accountingState.stETHTotals.lockedShares == totalLockedShares + shares);
        assert(_accountingState.assets[stranger].stETHLockedShares == shares);
        assert(_accountingState.assets[stranger].lastAssetsLockTimestamp <= Timestamps.now());

        _accountingState.assets[stranger].stETHLockedShares = SharesValues.ZERO;
    }

    // ---
    // accountStETHSharesUnlock(State storage self, address holder, SharesValue shares)
    // ---

    function testFuzz_accountStETHSharesUnlock_happyPath(
        address holder,
        uint128 sharesAmount,
        uint128 _holderSharesAmount
    ) external {
        SharesValue totalLockedSharesWithoutHolder = SharesValues.from(3);
        vm.assume(sharesAmount > SharesValues.ZERO.toUint256());
        vm.assume(_holderSharesAmount < type(uint128).max - totalLockedSharesWithoutHolder.toUint256());
        vm.assume(sharesAmount <= _holderSharesAmount);

        SharesValue shares = SharesValues.from(sharesAmount);
        SharesValue holderLockedShares = SharesValues.from(_holderSharesAmount);
        SharesValue totalLockedShares = totalLockedSharesWithoutHolder + holderLockedShares;

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesUnlocked(holder, shares);

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder, shares);

        assert(_accountingState.stETHTotals.lockedShares == totalLockedShares - shares);
        assert(_accountingState.assets[holder].stETHLockedShares == holderLockedShares - shares);
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp == Timestamps.ZERO);

        _accountingState.assets[holder].stETHLockedShares = SharesValues.ZERO;
    }

    function testFuzz_accountStETHSharesUnlock_RevertOn_ZeroSharesProvided(address holder) external {
        SharesValue shares = SharesValues.ZERO;

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder, shares);
    }

    function testFuzz_accountStETHSharesUnlock_RevertWhen_HolderHaveLessSharesThanProvided(
        address holder,
        uint128 sharesAmount,
        uint128 _holderSharesAmount
    ) external {
        SharesValue totalLockedSharesWithoutHolder = SharesValues.from(3);
        vm.assume(sharesAmount > SharesValues.ZERO.toUint256());
        vm.assume(_holderSharesAmount < type(uint128).max - totalLockedSharesWithoutHolder.toUint256());
        vm.assume(sharesAmount > _holderSharesAmount);

        SharesValue shares = SharesValues.from(sharesAmount);
        SharesValue holderLockedShares = SharesValues.from(_holderSharesAmount);
        SharesValue totalLockedShares = totalLockedSharesWithoutHolder + holderLockedShares;

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder, shares);

        _accountingState.assets[holder].stETHLockedShares = SharesValues.ZERO;
    }

    // TODO: accounting error, maybe need to add check to contract code
    function testFuzz_accountStETHSharesUnlock_RevertOn_AccountingError_TotalLockedSharesCounterIsLessThanProvidedSharesAmount(
        address holder,
        uint128 sharesAmount,
        uint128 _totalSharesAmount
    ) external {
        vm.assume(sharesAmount > SharesValues.ZERO.toUint256());
        vm.assume(_totalSharesAmount < sharesAmount);

        SharesValue shares = SharesValues.from(sharesAmount);
        SharesValue holderLockedShares = SharesValues.from(sharesAmount);
        SharesValue totalLockedShares = SharesValues.from(_totalSharesAmount);

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectRevert();

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder, shares);

        _accountingState.assets[holder].stETHLockedShares = SharesValues.ZERO;
    }

    function testFuzz_accountStETHSharesUnlock_RevertWhen_NoSharesWereLockedBefore(
        address stranger,
        uint128 sharesAmount
    ) external {
        vm.assume(sharesAmount > SharesValues.ZERO.toUint256());

        SharesValue shares = SharesValues.from(sharesAmount);

        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, shares));

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, stranger, shares);
    }

    // ---
    // accountStETHSharesUnlock(State storage self, address holder)
    // ---

    function testFuzz_accountStETHSharesUnlock_simple_happyPath(address holder, uint128 _holderSharesAmount) external {
        SharesValue totalLockedSharesWithoutHolder = SharesValues.from(3);
        vm.assume(_holderSharesAmount > SharesValues.ZERO.toUint256());
        vm.assume(_holderSharesAmount < type(uint128).max - totalLockedSharesWithoutHolder.toUint256());

        SharesValue holderLockedShares = SharesValues.from(_holderSharesAmount);
        SharesValue totalLockedShares = totalLockedSharesWithoutHolder + holderLockedShares;

        _accountingState.stETHTotals.lockedShares = totalLockedShares;
        _accountingState.assets[holder].stETHLockedShares = holderLockedShares;

        vm.expectEmit();
        emit AssetsAccounting.StETHSharesUnlocked(holder, holderLockedShares);

        SharesValue unlockedShares = AssetsAccounting.accountStETHSharesUnlock(_accountingState, holder);

        assert(unlockedShares == holderLockedShares);
        assert(_accountingState.stETHTotals.lockedShares == totalLockedShares - holderLockedShares);
        assert(_accountingState.assets[holder].stETHLockedShares == holderLockedShares - holderLockedShares);
        assert(_accountingState.assets[holder].lastAssetsLockTimestamp == Timestamps.ZERO);

        _accountingState.assets[holder].stETHLockedShares = SharesValues.ZERO;
    }

    function testFuzz_accountStETHSharesUnlock_simple_RevertWhen_NoSharesWereLockedBefore(address stranger) external {
        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.InvalidSharesValue.selector, SharesValues.ZERO));

        AssetsAccounting.accountStETHSharesUnlock(_accountingState, stranger);
    }
}
