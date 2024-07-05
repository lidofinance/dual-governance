pragma solidity 0.8.23;

import "contracts/model/DualGovernanceModel.sol";
import "contracts/model/EmergencyProtectedTimelockModel.sol";
import "contracts/model/EscrowModel.sol";
import "contracts/model/StETHModel.sol";

import "test/kontrol/StorageSetup.sol";

contract EscrowAccountingTest is StorageSetup {
    StETHModel stEth;
    EscrowModel escrow;

    function _setUpInitialState() public {
        stEth = new StETHModel();
        address dualGovernanceAddress = address(uint160(uint256(keccak256("dualGovernance")))); // arbitrary DG address
        escrow = new EscrowModel(dualGovernanceAddress, address(stEth));

        // ?STORAGE
        // ?WORD: totalPooledEther
        // ?WORD0: totalShares
        // ?WORD1: shares[escrow]
        _stEthStorageSetup(stEth, escrow);
    }

    function _setUpGenericState() public {
        stEth = new StETHModel();
        escrow = new EscrowModel(address(0), address(0));

        // ?STORAGE
        // ?WORD: totalPooledEther
        // ?WORD0: totalShares
        // ?WORD1: shares[escrow]
        _stEthStorageSetup(stEth, escrow);

        address dualGovernanceAddress = address(uint160(kevm.freshUInt(20))); // ?WORD2
        uint8 currentState = uint8(kevm.freshUInt(1)); // ?WORD3
        vm.assume(currentState < 2);

        // ?STORAGE0
        // ?WORD4: totalSharesLocked
        // ?WORD5: totalClaimedEthAmount
        // ?WORD6: rageQuitExtensionDelayPeriodEnd
        _escrowStorageSetup(escrow, DualGovernanceModel(dualGovernanceAddress), stEth, currentState);
    }

    function testRageQuitSupport() public {
        _setUpGenericState();

        uint256 totalSharesLocked = escrow.totalSharesLocked();
        uint256 totalFundsLocked = stEth.getPooledEthByShares(totalSharesLocked);
        uint256 expectedRageQuitSupport = totalFundsLocked * 1e18 / stEth.totalSupply();

        assert(escrow.getRageQuitSupport() == expectedRageQuitSupport);
    }

    function _escrowInvariants(Mode mode) internal view {
        _establish(mode, escrow.totalSharesLocked() <= stEth.sharesOf(address(escrow)));
        uint256 totalPooledEther = stEth.getPooledEthByShares(escrow.totalSharesLocked());
        _establish(mode, totalPooledEther <= stEth.balanceOf(address(escrow)));
        _establish(mode, escrow.totalWithdrawalRequestAmount() <= totalPooledEther);
        _establish(mode, escrow.totalClaimedEthAmount() <= escrow.totalWithdrawalRequestAmount());
        _establish(mode, escrow.totalWithdrawnPostRageQuit() <= escrow.totalClaimedEthAmount());
    }

    function _signallingEscrowInvariants(Mode mode) internal view {
        if (escrow.currentState() == EscrowModel.State.SignallingEscrow) {
            _establish(mode, escrow.totalWithdrawalRequestAmount() == 0);
            _establish(mode, escrow.totalClaimedEthAmount() == 0);
            _establish(mode, escrow.totalWithdrawnPostRageQuit() == 0);
        }
    }

    function _escrowUserInvariants(Mode mode, address user) internal view {
        _establish(mode, escrow.shares(user) <= escrow.totalSharesLocked());
    }

    function testEscrowInvariantsHoldInitially() public {
        _setUpInitialState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        _escrowInvariants(Mode.Assert);
        _signallingEscrowInvariants(Mode.Assert);
        _escrowUserInvariants(Mode.Assert, sender);
    }

    struct AccountingRecord {
        EscrowModel.State escrowState;
        uint256 allowance;
        uint256 userBalance;
        uint256 escrowBalance;
        uint256 userShares;
        uint256 escrowShares;
        uint256 userSharesLocked;
        uint256 totalSharesLocked;
        uint256 totalEth;
        uint256 userLastLockedTime;
    }

    function _saveAccountingRecord(address user) internal view returns (AccountingRecord memory ar) {
        ar.escrowState = escrow.currentState();
        ar.allowance = stEth.allowance(user, address(escrow));
        ar.userBalance = stEth.balanceOf(user);
        ar.escrowBalance = stEth.balanceOf(address(escrow));
        ar.userShares = stEth.sharesOf(user);
        ar.escrowShares = stEth.sharesOf(address(escrow));
        ar.userSharesLocked = escrow.shares(user);
        ar.totalSharesLocked = escrow.totalSharesLocked();
        ar.totalEth = stEth.getPooledEthByShares(ar.totalSharesLocked);
        ar.userLastLockedTime = escrow.lastLockedTimes(user);
    }

    function _assumeFreshAddress(address account) internal {
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

    function _assumeNoOverflow(uint256 augend, uint256 addend) internal {
        unchecked {
            vm.assume(augend < augend + addend);
        }
    }

    function testLockStEth(uint256 amount) public {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);
        vm.assume(stEth.balanceOf(sender) < ethUpperBound);

        AccountingRecord memory pre = _saveAccountingRecord(sender);
        vm.assume(pre.escrowState == EscrowModel.State.SignallingEscrow);
        vm.assume(0 < amount);
        vm.assume(amount <= pre.userBalance);
        vm.assume(amount <= pre.allowance);

        uint256 amountInShares = stEth.getSharesByPooledEth(amount);
        _assumeNoOverflow(pre.userSharesLocked, amountInShares);
        _assumeNoOverflow(pre.totalSharesLocked, amountInShares);

        _escrowInvariants(Mode.Assume);
        _signallingEscrowInvariants(Mode.Assume);
        _escrowUserInvariants(Mode.Assume, sender);

        vm.startPrank(sender);
        escrow.lock(amount);
        vm.stopPrank();

        _escrowInvariants(Mode.Assert);
        _signallingEscrowInvariants(Mode.Assert);
        _escrowUserInvariants(Mode.Assert, sender);

        AccountingRecord memory post = _saveAccountingRecord(sender);
        assert(post.escrowState == EscrowModel.State.SignallingEscrow);
        assert(post.userShares == pre.userShares - amountInShares);
        assert(post.escrowShares == pre.escrowShares + amountInShares);
        assert(post.userSharesLocked == pre.userSharesLocked + amountInShares);
        assert(post.totalSharesLocked == pre.totalSharesLocked + amountInShares);
        assert(post.userLastLockedTime == block.timestamp);

        // Accounts for rounding errors in the conversion to and from shares
        assert(pre.userBalance - amount <= post.userBalance);
        assert(post.escrowBalance <= pre.escrowBalance + amount);
        assert(post.totalEth <= pre.totalEth + amount);

        uint256 errorTerm = stEth.getPooledEthByShares(1) + 1;
        assert(post.userBalance <= pre.userBalance - amount + errorTerm);
        assert(pre.escrowBalance + amount < errorTerm || pre.escrowBalance + amount - errorTerm <= post.escrowBalance);
        assert(pre.totalEth + amount < errorTerm || pre.totalEth + amount - errorTerm <= post.totalEth);
    }

    function testUnlockStEth() public {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);
        vm.assume(escrow.lastLockedTimes(sender) < timeUpperBound);

        AccountingRecord memory pre = _saveAccountingRecord(sender);
        vm.assume(pre.escrowState == EscrowModel.State.SignallingEscrow);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);
        vm.assume(block.timestamp >= pre.userLastLockedTime + escrow.SIGNALLING_ESCROW_MIN_LOCK_TIME());

        _escrowInvariants(Mode.Assume);
        _signallingEscrowInvariants(Mode.Assume);
        _escrowUserInvariants(Mode.Assume, sender);

        vm.startPrank(sender);
        escrow.unlock();
        vm.stopPrank();

        _escrowInvariants(Mode.Assert);
        _signallingEscrowInvariants(Mode.Assert);
        _escrowUserInvariants(Mode.Assert, sender);

        AccountingRecord memory post = _saveAccountingRecord(sender);
        assert(post.escrowState == EscrowModel.State.SignallingEscrow);
        assert(post.userShares == pre.userShares + pre.userSharesLocked);
        assert(post.userSharesLocked == 0);
        assert(post.totalSharesLocked == pre.totalSharesLocked - pre.userSharesLocked);
        assert(post.userLastLockedTime == pre.userLastLockedTime);

        // Accounts for rounding errors in the conversion to and from shares
        uint256 amount = stEth.getPooledEthByShares(pre.userSharesLocked);
        assert(pre.escrowBalance - amount <= post.escrowBalance);
        assert(pre.totalEth - amount <= post.totalEth);
        assert(post.userBalance <= post.userBalance + amount);

        uint256 errorTerm = stEth.getPooledEthByShares(1) + 1;
        assert(post.escrowBalance <= pre.escrowBalance - amount + errorTerm);
        assert(post.totalEth <= pre.totalEth - amount + errorTerm);
        assert(pre.userBalance + amount < errorTerm || pre.userBalance + amount - errorTerm <= post.userBalance);
    }
}
