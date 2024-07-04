pragma solidity 0.8.23;

import "test/kontrol/EscrowAccounting.t.sol";

contract EscrowOperationsTest is EscrowAccountingTest {
    /**
     * Test that a staker cannot unlock funds from the escrow until SignallingEscrowMinLockTime has passed since the last time that user has locked tokens.
     */
    function testCannotUnlockBeforeMinLockTime() external {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);
        vm.assume(escrow.lastLockedTimes(sender) < timeUpperBound);

        AccountingRecord memory pre = _saveAccountingRecord(sender);
        vm.assume(pre.escrowState == EscrowModel.State.SignallingEscrow);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);

        uint256 lockPeriod = pre.userLastLockedTime + escrow.SIGNALLING_ESCROW_MIN_LOCK_TIME();

        if (block.timestamp < lockPeriod) {
            vm.prank(sender);
            vm.expectRevert("Lock period not expired.");
            escrow.unlock();
        }
    }

    /**
     * Test that funds cannot be locked and unlocked if the escrow is in the RageQuitEscrow state.
     */
    function testCannotLockUnlockInRageQuitEscrowState(uint256 amount) external {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);
        vm.assume(stEth.balanceOf(sender) < ethUpperBound);

        AccountingRecord memory pre = _saveAccountingRecord(sender);
        vm.assume(0 < amount);
        vm.assume(amount <= pre.userBalance);
        vm.assume(amount <= pre.allowance);

        uint256 amountInShares = stEth.getSharesByPooledEth(amount);
        _assumeNoOverflow(pre.userSharesLocked, amountInShares);
        _assumeNoOverflow(pre.totalSharesLocked, amountInShares);

        _escrowInvariants(Mode.Assume);
        _signallingEscrowInvariants(Mode.Assume);
        _escrowUserInvariants(Mode.Assume, sender);

        if (pre.escrowState == EscrowModel.State.RageQuitEscrow) {
            vm.prank(sender);
            vm.expectRevert("Cannot lock in current state.");
            escrow.lock(amount);

            vm.prank(sender);
            vm.expectRevert("Cannot unlock in current state.");
            escrow.unlock();
        } else {
            vm.prank(sender);
            escrow.lock(amount);

            AccountingRecord memory afterLock = _saveAccountingRecord(sender);
            vm.assume(afterLock.userShares < ethUpperBound);
            vm.assume(afterLock.userLastLockedTime < timeUpperBound);
            vm.assume(afterLock.userSharesLocked <= afterLock.totalSharesLocked);
            vm.assume(block.timestamp >= afterLock.userLastLockedTime + escrow.SIGNALLING_ESCROW_MIN_LOCK_TIME());

            vm.prank(sender);
            escrow.unlock();

            _escrowInvariants(Mode.Assert);
            _signallingEscrowInvariants(Mode.Assert);
            _escrowUserInvariants(Mode.Assert, sender);

            AccountingRecord memory post = _saveAccountingRecord(sender);
            assert(post.escrowState == EscrowModel.State.SignallingEscrow);
            assert(post.userShares == pre.userShares);
            assert(post.escrowShares == pre.escrowShares);
            assert(post.userSharesLocked == 0);
            assert(post.totalSharesLocked == pre.totalSharesLocked);
            assert(post.userLastLockedTime == afterLock.userLastLockedTime);
        }
    }

    /**
     * Test that a user cannot withdraw funds from the escrow until the RageQuitEthClaimTimelock has elapsed after the RageQuitExtensionDelay period.
     */
    function testCannotWithdrawBeforeEthClaimTimelockElapsed() external {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);
        vm.assume(stEth.balanceOf(sender) < ethUpperBound);

        AccountingRecord memory pre = _saveAccountingRecord(sender);
        vm.assume(pre.escrowState == EscrowModel.State.RageQuitEscrow);
        vm.assume(pre.userSharesLocked > 0);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);
        uint256 userEth = stEth.getPooledEthByShares(pre.userSharesLocked);
        vm.assume(userEth <= pre.totalEth);
        vm.assume(userEth <= address(escrow).balance);

        _escrowInvariants(Mode.Assume);
        _escrowUserInvariants(Mode.Assume, sender);

        vm.assume(escrow.lastWithdrawalRequestSubmitted());
        vm.assume(escrow.claimedWithdrawalRequests() == escrow.withdrawalRequestCount());
        vm.assume(escrow.rageQuitExtensionDelayPeriodEnd() < block.timestamp);
        // Assumption for simplicity
        vm.assume(escrow.rageQuitSequenceNumber() < 2);

        uint256 timelockStart = escrow.rageQuitEthClaimTimelockStart();
        uint256 ethClaimTimelock = escrow.rageQuitEthClaimTimelock();
        vm.assume(timelockStart + ethClaimTimelock < timeUpperBound);

        if (block.timestamp <= timelockStart + ethClaimTimelock) {
            vm.prank(sender);
            vm.expectRevert("Rage quit ETH claim timelock has not elapsed.");
            escrow.withdraw();
        } else {
            vm.prank(sender);
            escrow.withdraw();

            _escrowInvariants(Mode.Assert);
            _escrowUserInvariants(Mode.Assert, sender);

            AccountingRecord memory post = _saveAccountingRecord(sender);
            assert(post.userSharesLocked == 0);
        }
    }
}
