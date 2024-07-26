pragma solidity 0.8.23;

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import "test/kontrol/EscrowAccounting.t.sol";

contract EscrowOperationsTest is EscrowAccountingTest {
    function _tryLockStETH(uint256 amount) internal returns (bool) {
        try escrow.lockStETH(amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _tryUnlockStETH() internal returns (bool) {
        try escrow.unlockStETH() {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * Test that a staker cannot unlock funds from the escrow until SignallingEscrowMinLockTime has passed since the last time that user has locked tokens.
     */
    function testCannotUnlockBeforeMinLockTime() external {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);
        vm.assume(_getLastAssetsLockTimestamp(escrow, sender) < timeUpperBound);

        AccountingRecord memory pre = this.saveAccountingRecord(sender, escrow);
        vm.assume(pre.escrowState == EscrowState.SignallingEscrow);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);

        Timestamp lockPeriod = addTo(config.SIGNALLING_ESCROW_MIN_LOCK_TIME(), pre.userLastLockedTime);

        if (Timestamps.now() < lockPeriod) {
            vm.prank(sender);
            vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.AssetsUnlockDelayNotPassed.selector, lockPeriod));
            escrow.unlockStETH();
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

        AccountingRecord memory pre = this.saveAccountingRecord(sender, escrow);
        vm.assume(0 < amount);
        vm.assume(amount <= pre.userBalance);
        vm.assume(amount <= pre.allowance);

        uint256 amountInShares = stEth.getSharesByPooledEth(amount);
        _assumeNoOverflow(pre.userSharesLocked, amountInShares);
        _assumeNoOverflow(pre.totalSharesLocked, amountInShares);

        this.escrowInvariants(Mode.Assume, escrow);
        this.signallingEscrowInvariants(Mode.Assume, escrow);
        this.escrowUserInvariants(Mode.Assume, escrow, sender);

        if (pre.escrowState == EscrowState.RageQuitEscrow) {
            vm.startPrank(sender);
            //vm.expectRevert("Cannot lock in current state.");
            bool lockSuccess = _tryLockStETH(amount);
            assertTrue(lockSuccess, "Cannot lock in current state.");
            vm.stopPrank;

            vm.startPrank(sender);
            //vm.expectRevert("Cannot unlock in current state.");
            bool unlockSuccess = _tryUnlockStETH();
            assertTrue(unlockSuccess, "Cannot unlock in current state.");
            vm.stopPrank;
        } else {
            vm.prank(sender);
            escrow.lockStETH(amount);

            AccountingRecord memory afterLock = this.saveAccountingRecord(sender, escrow);
            vm.assume(afterLock.userShares < ethUpperBound);
            //vm.assume(afterLock.userLastLockedTime < timeUpperBound);
            vm.assume(afterLock.userSharesLocked <= afterLock.totalSharesLocked);
            vm.assume(Timestamps.now() >= addTo(config.SIGNALLING_ESCROW_MIN_LOCK_TIME(), afterLock.userLastLockedTime));

            vm.prank(sender);
            escrow.unlockStETH();

            this.escrowInvariants(Mode.Assert, escrow);
            this.signallingEscrowInvariants(Mode.Assert, escrow);
            this.escrowUserInvariants(Mode.Assert, escrow, sender);

            AccountingRecord memory post = this.saveAccountingRecord(sender, escrow);
            assert(post.escrowState == EscrowState.SignallingEscrow);
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
    // TODO: Uncomment this test and adapt it to the client code
    /*
    function testCannotWithdrawBeforeEthClaimTimelockElapsed() external {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);
        vm.assume(stEth.balanceOf(sender) < ethUpperBound);

        AccountingRecord memory pre = this.saveAccountingRecord(sender, escrow);
        vm.assume(pre.escrowState == EscrowState.RageQuitEscrow);
        vm.assume(pre.userSharesLocked > 0);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);
        uint256 userEth = stEth.getPooledEthByShares(pre.userSharesLocked);
        vm.assume(userEth <= pre.totalEth);
        vm.assume(userEth <= address(escrow).balance);

        this.escrowInvariants(Mode.Assume, escrow);
        this.escrowUserInvariants(Mode.Assume, escrow, sender);

        vm.assume(escrow.lastWithdrawalRequestSubmitted());
        vm.assume(escrow.claimedWithdrawalRequests() == escrow.withdrawalRequestCount());
        vm.assume(escrow.getIsWithdrawalsClaimed());
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

            this.escrowInvariants(Mode.Assert);
            this.escrowUserInvariants(Mode.Assert, sender);

            AccountingRecord memory post = this.saveAccountingRecord(sender, escrow);
            assert(post.userSharesLocked == 0);
        }
    }
    */
}
