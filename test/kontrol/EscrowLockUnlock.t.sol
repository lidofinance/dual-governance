pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/Configuration.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";

import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import "contracts/model/StETHModel.sol";
import "contracts/model/WithdrawalQueueModel.sol";
import "contracts/model/WstETHAdapted.sol";

import {StorageSetup} from "test/kontrol/StorageSetup.sol";
import {DualGovernanceSetUp} from "test/kontrol/DualGovernanceSetUp.sol";
import {EscrowInvariants} from "test/kontrol/EscrowInvariants.sol";
import {ActivateNextStateMock} from "test/kontrol/ActivateNextState.t.sol";

contract EscrowLockUnlockTest is EscrowInvariants, DualGovernanceSetUp {
    function _assumeFreshAddress(address account) internal {
        IEscrow escrow = signallingEscrow;
        vm.assume(account != address(0));
        vm.assume(account != address(this));
        vm.assume(account != address(vm));
        vm.assume(account != address(kevm));
        vm.assume(account != address(stEth));
        vm.assume(account != address(escrow)); // Important assumption: could potentially violate invariants if violated

        // Keccak injectivity
        vm.assume(
            keccak256(abi.encodePacked(account, uint256(2))) != keccak256(abi.encodePacked(address(escrow), uint256(2)))
        );
    }

    function testLockStEth(uint256 amount) public {
        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));

        uint256 senderShares = kevm.freshUInt(32);
        vm.assume(senderShares < ethUpperBound);
        stEth.setShares(sender, senderShares);
        vm.assume(stEth.balanceOf(sender) < ethUpperBound);

        uint256 senderAllowance = kevm.freshUInt(32);
        // This assumption means that senderAllowance != INFINITE_ALLOWANCE,
        // which doubles the execution effort without any added vaue
        vm.assume(senderAllowance < ethUpperBound);
        // Hardcoded for "sender"
        _storeUInt256(
            address(stEth),
            74992941968319547325319283905569341819227548318746972755481050864341498730161,
            senderAllowance
        );

        uint128 senderLockedShares = uint128(kevm.freshUInt(16));
        uint128 senderUnlockedShares = uint128(kevm.freshUInt(16));
        bytes memory slotAbi = abi.encodePacked(uint128(senderUnlockedShares), uint128(senderLockedShares));
        bytes32 slot;
        assembly {
            slot := mload(add(slotAbi, 0x20))
        }
        _storeBytes32(
            address(signallingEscrow),
            93842437974268059396725027201531251382101332839645030345425397622830526343272,
            slot
        );

        uint256 senderLastAssetsLockTimestamp = kevm.freshUInt(32);
        vm.assume(senderLastAssetsLockTimestamp < timeUpperBound);
        _storeUInt256(
            address(signallingEscrow),
            93842437974268059396725027201531251382101332839645030345425397622830526343273,
            senderLastAssetsLockTimestamp
        );

        vm.assume(0 < amount);
        vm.assume(amount <= stEth.balanceOf(sender));
        vm.assume(amount <= senderAllowance);

        AccountingRecord memory pre = this.saveAccountingRecord(sender, signallingEscrow);

        uint256 amountInShares = stEth.getSharesByPooledEth(amount);
        _assumeNoOverflow(pre.userSharesLocked, amountInShares);
        _assumeNoOverflow(pre.totalSharesLocked, amountInShares);

        this.escrowInvariants(Mode.Assume, signallingEscrow);
        this.signallingEscrowInvariants(Mode.Assume, signallingEscrow);
        this.escrowUserInvariants(Mode.Assume, signallingEscrow, sender);

        vm.startPrank(sender);
        signallingEscrow.lockStETH(amount);
        vm.stopPrank();

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
        assert(pre.userBalance - amount <= post.userBalance);
        assert(post.escrowBalance <= pre.escrowBalance + amount);
        assert(post.totalEth <= pre.totalEth + amount);

        uint256 errorTerm = stEth.getPooledEthByShares(1) + 1;
        assert(post.userBalance <= pre.userBalance - amount + errorTerm);
        assert(pre.escrowBalance + amount <= post.escrowBalance + errorTerm);
        assert(pre.totalEth + amount <= post.totalEth + errorTerm);
    }

    // Isolating individual branches of testUnlockStEth

    function testUnlockStEth_1() public {
        State initialState = dualGovernance.getCurrentState();

        vm.assume(initialState != State.VetoSignalling);
        vm.assume(initialState != State.VetoSignallingDeactivation);

        testUnlockStEth();
    }

    function testUnlockStEth_2() public {
        State initialState = dualGovernance.getCurrentState();
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();

        vm.assume(initialState != State.Normal);
        vm.assume(initialState != State.VetoCooldown);
        vm.assume(initialState != State.RageQuit);
        vm.assume(rageQuitSupport <= config.SECOND_SEAL_RAGE_QUIT_SUPPORT());

        testUnlockStEth();
    }

    function testUnlockStEth_3() public {
        State initialState = dualGovernance.getCurrentState();
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
        Timestamp vetoSignallingActivationTime = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));

        vm.assume(initialState != State.Normal);
        vm.assume(initialState != State.VetoCooldown);
        vm.assume(initialState != State.RageQuit);
        vm.assume(rageQuitSupport > config.SECOND_SEAL_RAGE_QUIT_SUPPORT());
        vm.assume(Timestamps.now() <= config.DYNAMIC_TIMELOCK_MAX_DURATION().addTo(vetoSignallingActivationTime));

        testUnlockStEth();
    }

    //
    function testUnlockStEth() public {
        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        uint256 senderShares = kevm.freshUInt(32);
        vm.assume(senderShares < ethUpperBound);
        stEth.setShares(sender, senderShares);
        vm.assume(stEth.balanceOf(sender) < ethUpperBound);

        uint256 senderAllowance = kevm.freshUInt(32);
        // This assumption means that senderAllowance != INFINITE_ALLOWANCE,
        // which doubles the execution effort without any added vaue
        vm.assume(senderAllowance < ethUpperBound);
        // Hardcoded for "sender"
        _storeUInt256(
            address(stEth),
            74992941968319547325319283905569341819227548318746972755481050864341498730161,
            senderAllowance
        );

        uint128 senderLockedShares = uint128(kevm.freshUInt(16));
        vm.assume(senderLockedShares < ethUpperBound);
        uint128 senderUnlockedShares = uint128(kevm.freshUInt(16));
        bytes memory slotAbi = abi.encodePacked(uint128(senderUnlockedShares), uint128(senderLockedShares));
        bytes32 slot;
        assembly {
            slot := mload(add(slotAbi, 0x20))
        }
        _storeBytes32(
            address(signallingEscrow),
            93842437974268059396725027201531251382101332839645030345425397622830526343272,
            slot
        );

        uint256 senderLastAssetsLockTimestamp = kevm.freshUInt(32);
        vm.assume(senderLastAssetsLockTimestamp < timeUpperBound);
        _storeUInt256(
            address(signallingEscrow),
            93842437974268059396725027201531251382101332839645030345425397622830526343273,
            senderLastAssetsLockTimestamp
        );

        AccountingRecord memory pre = this.saveAccountingRecord(sender, signallingEscrow);
        vm.assume(0 < pre.userSharesLocked);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);
        vm.assume(Timestamps.now() > addTo(config.SIGNALLING_ESCROW_MIN_LOCK_TIME(), pre.userLastLockedTime));

        this.escrowInvariants(Mode.Assume, signallingEscrow);
        this.signallingEscrowInvariants(Mode.Assume, signallingEscrow);
        this.escrowUserInvariants(Mode.Assume, signallingEscrow, sender);

        bool transitionToRageQuit;

        {
            State initialState = dualGovernance.getCurrentState();
            uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
            Timestamp vetoSignallingActivationTime = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));

            transitionToRageQuit = (
                initialState == State.VetoSignalling || initialState == State.VetoSignallingDeactivation
            ) && rageQuitSupport > config.SECOND_SEAL_RAGE_QUIT_SUPPORT()
                && Timestamps.now() > config.DYNAMIC_TIMELOCK_MAX_DURATION().addTo(vetoSignallingActivationTime);
        }

        vm.assume(!transitionToRageQuit);

        ActivateNextStateMock mock = new ActivateNextStateMock(address(this), sender);
        kevm.mockFunction(
            address(dualGovernance), address(mock), abi.encodeWithSelector(mock.activateNextState.selector)
        );

        vm.startPrank(sender);
        signallingEscrow.unlockStETH();
        vm.stopPrank();

        this.escrowInvariants(Mode.Assert, signallingEscrow);
        this.signallingEscrowInvariants(Mode.Assert, signallingEscrow);
        this.escrowUserInvariants(Mode.Assert, signallingEscrow, sender);

        AccountingRecord memory post = this.saveAccountingRecord(sender, signallingEscrow);
        assert(post.userShares == pre.userShares + pre.userSharesLocked);
        assert(post.userSharesLocked == 0);
        assert(post.totalSharesLocked == pre.totalSharesLocked - pre.userSharesLocked);
        assert(post.userLastLockedTime == pre.userLastLockedTime);

        // Accounts for rounding errors in the conversion to and from shares
        uint256 amount = stEth.getPooledEthByShares(pre.userSharesLocked);

        // Rewritten to avoid branching
        //assert(pre.escrowBalance - amount < 1 || pre.escrowBalance - amount - 1 <= post.escrowBalance);
        assert(pre.escrowBalance - amount <= post.escrowBalance + 1);
        assert(post.escrowBalance <= pre.escrowBalance - amount);

        // Rewritten to avoid branching
        //assert(pre.totalEth - amount < 1 || pre.totalEth - amount - 1 <= post.totalEth);
        assert(pre.totalEth - amount <= post.totalEth + 1);
        assert(post.totalEth <= pre.totalEth - amount);

        assert(pre.userBalance + amount <= post.userBalance);
        assert(post.userBalance <= pre.userBalance + amount + 1);
    }
}
