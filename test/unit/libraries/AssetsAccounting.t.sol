// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, Vm} from "forge-std/Test.sol";

import {AssetsAccounting, VetoerState, TotalsState} from "contracts/libraries/AssetsAccounting.sol";

contract AssetsAccountingUnitTests is Test {
    using AssetsAccounting for AssetsAccounting.State;

    address internal immutable _VETOER = makeAddr("VETOER");

    AssetsAccounting.State internal _assetsAccounting;

    // ---
    // accountStETHLock()
    // ---

    function test_accountStETHLock_reverts_on_invalid_vetoer() external {
        vm.expectRevert(_encodeInvalidVetoerError(address(0)));
        _assetsAccounting.accountStETHLock(address(0), 1);
    }

    function test_accountStETHLock_reverts_on_zero_shares_lock() external {
        vm.expectRevert(_encodeInvalidSharesLockError(_VETOER, 0));
        _assetsAccounting.accountStETHLock(_VETOER, 0);
    }

    function test_accountStETHLock_emits_stETHLocked_event() external {
        uint256 sharesToLock = 2 * 10 ** 18 + 42;

        vm.recordLogs();
        _assetsAccounting.accountStETHLock(_VETOER, sharesToLock);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], AssetsAccounting.StETHLocked.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(_VETOER))));
        assertEq(abi.decode(logs[0].data, (uint256)), sharesToLock);
    }

    function testFuzz_accountStETHLock_accounting(uint128 shares, address vetoer) external {
        vm.assume(shares > 0);
        vm.assume(vetoer != address(0));

        TotalsState memory totalsStateBefore = _assetsAccounting.getTotalsState();
        VetoerState memory vetoerStateBefore = _assetsAccounting.getVetoerState(vetoer);

        _assetsAccounting.accountStETHLock(vetoer, shares);

        TotalsState memory totalsStateAfter = _assetsAccounting.getTotalsState();
        VetoerState memory vetoerStateAfter = _assetsAccounting.getVetoerState(vetoer);

        assertEq(vetoerStateAfter.stETHShares, vetoerStateBefore.stETHShares + shares);
        assertEq(vetoerStateAfter.wstETHShares, vetoerStateBefore.wstETHShares);
        assertEq(vetoerStateAfter.unstETHShares, vetoerStateBefore.unstETHShares);

        assertEq(totalsStateAfter.shares, totalsStateBefore.shares + shares);
        assertEq(totalsStateAfter.amountClaimed, totalsStateBefore.amountClaimed);
        assertEq(totalsStateAfter.sharesFinalized, totalsStateBefore.sharesFinalized);
        assertEq(totalsStateAfter.amountFinalized, totalsStateBefore.amountFinalized);
    }

    function _encodeInvalidVetoerError(address vetoer) private view returns (bytes memory) {
        return abi.encodeWithSelector(AssetsAccounting.InvalidVetoer.selector, vetoer);
    }

    function _encodeInvalidSharesLockError(address vetoer, uint256 shares) private view returns (bytes memory) {
        return abi.encodeWithSelector(AssetsAccounting.InvalidSharesLock.selector, vetoer, shares);
    }
}
