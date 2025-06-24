pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import {Escrow} from "contracts/Escrow.sol";

import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import "test/kontrol/model/StETHModel.sol";
import "test/kontrol/model/WithdrawalQueueModel.sol";
import "test/kontrol/model/WstETHAdapted.sol";

import {StorageSetup} from "test/kontrol/StorageSetup.sol";
import {DualGovernanceSetUp} from "test/kontrol/DualGovernanceSetUp.sol";
import {EscrowInvariants} from "test/kontrol/EscrowInvariants.sol";

import "kontrol-cheatcodes/KontrolCheats.sol";

contract EscrowLockUnlockTest is EscrowInvariants, DualGovernanceSetUp {
    function _calculateRageQuitSupportAfterLock(IEscrowBase escrow, uint256 amount) internal returns (uint256) {
        uint256 finalizedEth = _getFinalizedEth(escrow);
        uint256 lockedShares = _getTotalStEthLockedShares(escrow);
        uint256 unfinalizedShares = _getUnfinalizedShares(escrow);
        uint256 totalPooledEther = stEth.getTotalPooledEther();
        uint256 amountInShares = stEth.getSharesByPooledEth(amount);
        uint256 numerator = stEth.getPooledEthByShares(lockedShares + amountInShares + unfinalizedShares) + finalizedEth;
        uint256 denominator = totalPooledEther + finalizedEth;

        return 100 * 10 ** 16 * numerator / denominator;
    }

    function testLockStEthNormal(uint256 amount) public {
        vm.assume(dualGovernance.getPersistedState() == State.Normal);

        testLockStEthBase(amount);
    }

    function testLockStEthVetoSignalling_(uint256 amount) public {
        vm.assume(dualGovernance.getPersistedState() == State.VetoSignalling);

        testLockStEthBase(amount);
    }

    function testLockStEthVetoSignallingDeactivation(uint256 amount) public {
        vm.assume(dualGovernance.getPersistedState() == State.VetoSignallingDeactivation);

        testLockStEthBase(amount);
    }

    function testLockStEthVetoCooldown(uint256 amount) public {
        vm.assume(dualGovernance.getPersistedState() == State.VetoCooldown);

        testLockStEthBase(amount);
    }

    function testLockStEthRageQuit(uint256 amount) public {
        vm.assume(dualGovernance.getPersistedState() == State.RageQuit);

        testLockStEthBase(amount);
    }

    function testLockStEthBase(uint256 amount) public {
        address sender = _getArbitraryUserAddress();

        {
            uint256 senderShares = freshUInt256("StETH_senderShares");
            vm.assume(senderShares < ethUpperBound);
            stEth.setShares(sender, senderShares);
            vm.assume(stEth.balanceOf(sender) < ethUpperBound);

            uint256 senderAllowance = freshUInt256("StETH_senderAllowance");
            // This assumption means that senderAllowance != INFINITE_ALLOWANCE,
            // which doubles the execution effort without any added vaue
            vm.assume(senderAllowance < ethUpperBound);
            stEth.setAllowances(sender, address(signallingEscrow), senderAllowance);

            this.escrowUserSetup(signallingEscrow, sender);

            vm.assume(senderShares + stEth.sharesOf(address(signallingEscrow)) <= stEth.getTotalShares());

            vm.assume(0 < amount);
            vm.assume(amount <= stEth.balanceOf(sender));
            vm.assume(amount <= senderAllowance);
        }

        AccountingRecord memory pre = this.saveAccountingRecord(sender, signallingEscrow);

        uint256 amountInShares = stEth.getSharesByPooledEth(amount);
        vm.assume(0 < amountInShares);
        vm.assume(amountInShares < ethUpperBound);

        this.escrowInvariants(Mode.Assume, signallingEscrow);
        this.signallingEscrowInvariants(Mode.Assume, signallingEscrow);
        this.escrowUserInvariants(Mode.Assume, signallingEscrow, sender);

        {
            // Assume rage quit support won't overflow after amount is locked
            uint256 rageQuitSupportAfterLock = _calculateRageQuitSupportAfterLock(signallingEscrow, amount);
            vm.assume(rageQuitSupportAfterLock <= type(uint128).max);

            State initialState = dualGovernance.getPersistedState();

            // Information to help forget first state transition
            PercentD16 init_rageQuitSupport = signallingEscrow.getRageQuitSupport();
            Timestamp init_vetoSignallingActivatedAt = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));
            Timestamp init_vetoSignallingReactivationTime =
                Timestamp.wrap(_getVetoSignallingReactivationTime(dualGovernance));
            Timestamp init_enteredAt = Timestamp.wrap(_getEnteredAt(dualGovernance));
            Timestamp init_rageQuitExtensionPeriodStartedAt =
                Timestamp.wrap(_getRageQuitExtensionPeriodStartedAt(rageQuitEscrow));
            Duration init_rageQuitExtensionPeriodDuration =
                Duration.wrap(_getRageQuitExtensionPeriodDuration(rageQuitEscrow));

            State nextState = dualGovernance.getEffectiveState();
            vm.assume(initialState == State.RageQuit || nextState != State.RageQuit);

            vm.startPrank(sender);
            signallingEscrow.lockStETH(amount);
            vm.stopPrank();

            // Information to help forget second state transition
            PercentD16 next_rageQuitSupport = signallingEscrow.getRageQuitSupport();
            Timestamp next_vetoSignallingActivatedAt = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));
            Timestamp next_vetoSignallingReactivationTime =
                Timestamp.wrap(_getVetoSignallingReactivationTime(dualGovernance));
            Timestamp next_enteredAt = Timestamp.wrap(_getEnteredAt(dualGovernance));
            Timestamp next_rageQuitExtensionPeriodStartedAt =
                Timestamp.wrap(_getRageQuitExtensionPeriodStartedAt(rageQuitEscrow));
            Duration next_rageQuitExtensionPeriodDuration =
                Duration.wrap(_getRageQuitExtensionPeriodDuration(rageQuitEscrow));

            // Forget second state transition
            this.forgetStateTransition(
                nextState,
                next_rageQuitSupport,
                next_vetoSignallingActivatedAt,
                next_vetoSignallingReactivationTime,
                next_enteredAt,
                next_rageQuitExtensionPeriodStartedAt,
                next_rageQuitExtensionPeriodDuration
            );

            // Forget first state transition
            this.forgetStateTransition(
                initialState,
                init_rageQuitSupport,
                init_vetoSignallingActivatedAt,
                init_vetoSignallingReactivationTime,
                init_enteredAt,
                init_rageQuitExtensionPeriodStartedAt,
                init_rageQuitExtensionPeriodDuration
            );
        }

        this.escrowInvariants(Mode.Assert, signallingEscrow);
        this.signallingEscrowInvariants(Mode.Assert, signallingEscrow);
        this.escrowUserInvariants(Mode.Assert, signallingEscrow, sender);

        AccountingRecord memory post = this.saveAccountingRecord(sender, signallingEscrow);
        assert(post.userShares == pre.userShares - amountInShares);
        assert(post.escrowShares == pre.escrowShares + amountInShares);
        assert(post.userSharesLocked == pre.userSharesLocked + amountInShares);
        assert(post.totalSharesLocked == pre.totalSharesLocked + amountInShares);
        assert(post.userLastLockedTime == Timestamps.now());

        // Accounts for rounding errors in the conversion to and from shares
        uint256 errorTerm = stEth.getPooledEthByShares(1) + 1;

        assert(pre.userBalance - amount <= post.userBalance);
        assert(post.userBalance <= pre.userBalance - amount + errorTerm);

        assert(post.escrowBalance <= pre.escrowBalance + amount);
        assert(pre.escrowBalance + amount <= post.escrowBalance + errorTerm);

        assert(post.totalEth <= pre.totalEth + amount);
        assert(pre.totalEth + amount <= post.totalEth + errorTerm);
    }

    function testUnlockStEthNormal() public {
        vm.assume(dualGovernance.getPersistedState() == State.Normal);

        testUnlockStEthBase();
    }

    function testUnlockStEthVetoSignalling_() public {
        vm.assume(dualGovernance.getPersistedState() == State.VetoSignalling);

        testUnlockStEthBase();
    }

    function testUnlockStEthVetoSignallingDeactivation() public {
        vm.assume(dualGovernance.getPersistedState() == State.VetoSignallingDeactivation);

        testUnlockStEthBase();
    }

    function testUnlockStEthVetoCooldown() public {
        vm.assume(dualGovernance.getPersistedState() == State.VetoCooldown);

        testUnlockStEthBase();
    }

    function testUnlockStEthRageQuit() public {
        vm.assume(dualGovernance.getPersistedState() == State.RageQuit);

        testUnlockStEthBase();
    }

    function testUnlockStEthBase() public {
        address sender = _getArbitraryUserAddress();

        {
            uint256 senderShares = freshUInt256("StETH_senderShares");
            vm.assume(senderShares < ethUpperBound);
            stEth.setShares(sender, senderShares);
            vm.assume(stEth.balanceOf(sender) < ethUpperBound);

            this.escrowUserSetup(signallingEscrow, sender);
        }

        AccountingRecord memory pre = this.saveAccountingRecord(sender, signallingEscrow);
        vm.assume(0 < pre.userSharesLocked);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);
        vm.assume(
            Timestamps.now() > addTo(Duration.wrap(_getMinAssetsLockDuration(signallingEscrow)), pre.userLastLockedTime)
        );

        this.escrowInvariants(Mode.Assume, signallingEscrow);
        this.signallingEscrowInvariants(Mode.Assume, signallingEscrow);
        this.escrowUserInvariants(Mode.Assume, signallingEscrow, sender);

        {
            State initialState = dualGovernance.getPersistedState();

            // Information to help forget first state transition
            PercentD16 init_rageQuitSupport = signallingEscrow.getRageQuitSupport();
            Timestamp init_vetoSignallingActivatedAt = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));
            Timestamp init_vetoSignallingReactivationTime =
                Timestamp.wrap(_getVetoSignallingReactivationTime(dualGovernance));
            Timestamp init_enteredAt = Timestamp.wrap(_getEnteredAt(dualGovernance));
            Timestamp init_rageQuitExtensionPeriodStartedAt =
                Timestamp.wrap(_getRageQuitExtensionPeriodStartedAt(rageQuitEscrow));
            Duration init_rageQuitExtensionPeriodDuration =
                Duration.wrap(_getRageQuitExtensionPeriodDuration(rageQuitEscrow));

            State nextState = dualGovernance.getEffectiveState();
            vm.assume(initialState == State.RageQuit || nextState != State.RageQuit);

            vm.startPrank(sender);
            signallingEscrow.unlockStETH();
            vm.stopPrank();

            // Information to help forget second state transition
            PercentD16 next_rageQuitSupport = signallingEscrow.getRageQuitSupport();
            Timestamp next_vetoSignallingActivatedAt = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));
            Timestamp next_vetoSignallingReactivationTime =
                Timestamp.wrap(_getVetoSignallingReactivationTime(dualGovernance));
            Timestamp next_enteredAt = Timestamp.wrap(_getEnteredAt(dualGovernance));
            Timestamp next_rageQuitExtensionPeriodStartedAt =
                Timestamp.wrap(_getRageQuitExtensionPeriodStartedAt(rageQuitEscrow));
            Duration next_rageQuitExtensionPeriodDuration =
                Duration.wrap(_getRageQuitExtensionPeriodDuration(rageQuitEscrow));

            // Forget second state transition
            this.forgetStateTransition(
                nextState,
                next_rageQuitSupport,
                next_vetoSignallingActivatedAt,
                next_vetoSignallingReactivationTime,
                next_enteredAt,
                next_rageQuitExtensionPeriodStartedAt,
                next_rageQuitExtensionPeriodDuration
            );

            // Forget first state transition
            this.forgetStateTransition(
                initialState,
                init_rageQuitSupport,
                init_vetoSignallingActivatedAt,
                init_vetoSignallingReactivationTime,
                init_enteredAt,
                init_rageQuitExtensionPeriodStartedAt,
                init_rageQuitExtensionPeriodDuration
            );
        }

        this.escrowInvariants(Mode.Assert, signallingEscrow);
        this.signallingEscrowInvariants(Mode.Assert, signallingEscrow);
        this.escrowUserInvariants(Mode.Assert, signallingEscrow, sender);

        AccountingRecord memory post = this.saveAccountingRecord(sender, signallingEscrow);
        assert(post.userShares == pre.userShares + pre.userSharesLocked);
        assert(post.escrowShares == pre.escrowShares - pre.userSharesLocked);
        assert(post.userSharesLocked == 0);
        assert(post.totalSharesLocked == pre.totalSharesLocked - pre.userSharesLocked);
        assert(post.userLastLockedTime == pre.userLastLockedTime);

        // Accounts for rounding errors in the conversion to and from shares
        uint256 amount = stEth.getPooledEthByShares(pre.userSharesLocked);

        assert(pre.escrowBalance - amount <= post.escrowBalance + 1);
        assert(post.escrowBalance <= pre.escrowBalance - amount);

        assert(pre.totalEth - amount <= post.totalEth + 1);
        assert(post.totalEth <= pre.totalEth - amount);

        assert(pre.userBalance + amount <= post.userBalance);
        assert(post.userBalance <= pre.userBalance + amount + 1);
    }
}
