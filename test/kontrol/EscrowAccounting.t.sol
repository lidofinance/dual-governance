pragma solidity 0.8.23;

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

contract EscrowAccountingTest is StorageSetup {
    Configuration config;
    StETHModel stEth;
    WstETHAdapted wstEth;
    WithdrawalQueueModel withdrawalQueue;
    Escrow escrow;

    function _setUpInitialState() public {
        vm.chainId(1); // Set block.chainid so it's not symbolic

        stEth = new StETHModel();
        wstEth = new WstETHAdapted(IStETH(stEth));
        withdrawalQueue = new WithdrawalQueueModel();

        // Placeholder addresses
        address adminExecutor = address(uint160(uint256(keccak256("adminExecutor"))));
        address emergencyGovernance = address(uint160(uint256(keccak256("emergencyGovernance"))));
        address dualGovernanceAddress = address(uint160(uint256(keccak256("dualGovernance"))));

        config = new Configuration(adminExecutor, emergencyGovernance, new address[](0));

        escrow = new Escrow(address(stEth), address(wstEth), address(withdrawalQueue), address(config));
        escrow.initialize(dualGovernanceAddress);

        // ?STORAGE
        // ?WORD: totalPooledEther
        // ?WORD0: totalShares
        // ?WORD1: shares[escrow]
        _stEthStorageSetup(stEth, escrow);
    }

    function _setUpGenericState() public {
        _setUpInitialState();

        address dualGovernanceAddress = address(uint160(kevm.freshUInt(20))); // ?WORD2
        uint8 currentState = uint8(kevm.freshUInt(1)); // ?WORD3
        vm.assume(currentState < 3);

        // ?STORAGE0
        // ?WORD4: lockedShares
        // ?WORD5: claimedETH
        // ?WORD6: unfinalizedShares
        // ?WORD7: finalizedETH
        // ?WORD8: batchesQueue
        // ?WORD9: rageQuitExtensionDelay
        // ?WORD10: rageQuitWithdrawalsTimelock
        // ?WORD11: rageQuitTimelockStartedAt
        _escrowStorageSetup(escrow, DualGovernance(dualGovernanceAddress), EscrowState(currentState));
    }

    function testRageQuitSupport() public {
        _setUpGenericState();

        uint256 totalSharesLocked = escrow.getLockedAssetsTotals().stETHLockedShares;
        uint256 totalFundsLocked = stEth.getPooledEthByShares(totalSharesLocked);
        uint256 expectedRageQuitSupport = totalFundsLocked * 1e18 / stEth.totalSupply();

        assert(escrow.getRageQuitSupport() == expectedRageQuitSupport);
    }

    function _escrowInvariants(Mode mode) internal view {
        LockedAssetsTotals memory totals = escrow.getLockedAssetsTotals();
        _establish(mode, totals.stETHLockedShares <= stEth.sharesOf(address(escrow)));
        // TODO: Adapt to updated code
        //_establish(mode, totals.sharesFinalized <= totals.stETHLockedShares);
        uint256 totalPooledEther = stEth.getPooledEthByShares(totals.stETHLockedShares);
        _establish(mode, totalPooledEther <= stEth.balanceOf(address(escrow)));
        // TODO: Adapt to updated code
        //_establish(mode, totals.amountFinalized == stEth.getPooledEthByShares(totals.sharesFinalized));
        //_establish(mode, totals.amountFinalized <= totalPooledEther);
        //_establish(mode, totals.amountClaimed <= totals.amountFinalized);
        EscrowState currentState = _getCurrentState(escrow);
        _establish(mode, 0 < uint8(currentState));
        _establish(mode, uint8(currentState) < 3);
    }

    function _signallingEscrowInvariants(Mode mode) internal view {
        // TODO: Adapt to updated code
        /*
        if (_getCurrentState(escrow) == EscrowState.SignallingEscrow) {
            LockedAssetsTotals memory totals = escrow.getLockedAssetsTotals();
            _establish(mode, totals.sharesFinalized == 0);
            _establish(mode, totals.amountFinalized == 0);
            _establish(mode, totals.amountClaimed == 0);
        }
        */
    }

    function _escrowUserInvariants(Mode mode, address user) internal view {
        _establish(
            mode, escrow.getVetoerState(user).stETHLockedShares <= escrow.getLockedAssetsTotals().stETHLockedShares
        );
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
        EscrowState escrowState;
        uint256 allowance;
        uint256 userBalance;
        uint256 escrowBalance;
        uint256 userShares;
        uint256 escrowShares;
        uint256 userSharesLocked;
        uint256 totalSharesLocked;
        uint256 totalEth;
        uint256 userUnstEthLockedShares;
        uint256 unfinalizedShares;
        Timestamp userLastLockedTime;
    }

    function _saveAccountingRecord(address user) internal view returns (AccountingRecord memory ar) {
        ar.escrowState = _getCurrentState(escrow);
        ar.allowance = stEth.allowance(user, address(escrow));
        ar.userBalance = stEth.balanceOf(user);
        ar.escrowBalance = stEth.balanceOf(address(escrow));
        ar.userShares = stEth.sharesOf(user);
        ar.escrowShares = stEth.sharesOf(address(escrow));
        ar.userSharesLocked = escrow.getVetoerState(user).stETHLockedShares;
        ar.totalSharesLocked = escrow.getLockedAssetsTotals().stETHLockedShares;
        ar.totalEth = stEth.getPooledEthByShares(ar.totalSharesLocked);
        ar.userUnstEthLockedShares = escrow.getVetoerState(user).unstETHLockedShares;
        ar.unfinalizedShares = escrow.getLockedAssetsTotals().unstETHUnfinalizedShares;
        uint256 lastAssetsLockTimestamp = _getLastAssetsLockTimestamp(escrow, user);
        require(lastAssetsLockTimestamp < timeUpperBound);
        ar.userLastLockedTime = Timestamp.wrap(uint40(lastAssetsLockTimestamp));
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
        vm.assume(pre.escrowState == EscrowState.SignallingEscrow);
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
        escrow.lockStETH(amount);
        vm.stopPrank();

        _escrowInvariants(Mode.Assert);
        _signallingEscrowInvariants(Mode.Assert);
        _escrowUserInvariants(Mode.Assert, sender);

        AccountingRecord memory post = _saveAccountingRecord(sender);
        assert(post.escrowState == EscrowState.SignallingEscrow);
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
        assert(pre.escrowBalance + amount < errorTerm || pre.escrowBalance + amount - errorTerm <= post.escrowBalance);
        assert(pre.totalEth + amount < errorTerm || pre.totalEth + amount - errorTerm <= post.totalEth);
    }

    function testUnlockStEth() public {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);
        vm.assume(_getLastAssetsLockTimestamp(escrow, sender) < timeUpperBound);

        AccountingRecord memory pre = _saveAccountingRecord(sender);
        vm.assume(pre.escrowState == EscrowState.SignallingEscrow);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);
        vm.assume(Timestamps.now() >= addTo(config.SIGNALLING_ESCROW_MIN_LOCK_TIME(), pre.userLastLockedTime));

        _escrowInvariants(Mode.Assume);
        _signallingEscrowInvariants(Mode.Assume);
        _escrowUserInvariants(Mode.Assume, sender);

        vm.startPrank(sender);
        escrow.unlockStETH();
        vm.stopPrank();

        _escrowInvariants(Mode.Assert);
        _signallingEscrowInvariants(Mode.Assert);
        _escrowUserInvariants(Mode.Assert, sender);

        AccountingRecord memory post = _saveAccountingRecord(sender);
        assert(post.escrowState == EscrowState.SignallingEscrow);
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

    function testRequestWithdrawals(uint256 stEthAmount) public {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);

        AccountingRecord memory pre = _saveAccountingRecord(sender);

        _escrowInvariants(Mode.Assume);
        _escrowUserInvariants(Mode.Assume, sender);

        // Only request one withdrawal for simplicity
        uint256[] memory stEthAmounts = new uint256[](1);
        stEthAmounts[0] = stEthAmount;

        vm.startPrank(sender);
        escrow.requestWithdrawals(stEthAmounts);
        vm.stopPrank();

        _escrowInvariants(Mode.Assert);
        _escrowUserInvariants(Mode.Assert, sender);

        AccountingRecord memory post = _saveAccountingRecord(sender);
        assert(post.userSharesLocked == pre.userSharesLocked - stEthAmount);
        assert(post.totalSharesLocked == pre.totalSharesLocked - stEthAmount);
        assert(post.userLastLockedTime == Timestamps.now());
        assert(post.userUnstEthLockedShares == pre.userUnstEthLockedShares + stEthAmount);
        assert(post.unfinalizedShares == pre.unfinalizedShares + stEthAmount);
    }

    function testRequestNextWithdrawalsBatch(uint256 maxBatchSize) public {
        _setUpGenericState();

        vm.assume(_getCurrentState(escrow) == EscrowState.RageQuitEscrow);

        _escrowInvariants(Mode.Assume);

        escrow.requestNextWithdrawalsBatch(maxBatchSize);

        _escrowInvariants(Mode.Assert);
    }

    function testClaimNextWithdrawalsBatch() public {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);

        vm.assume(_getCurrentState(escrow) == EscrowState.RageQuitEscrow);

        _escrowInvariants(Mode.Assume);
        _escrowUserInvariants(Mode.Assume, sender);

        // Only claim one unstETH for simplicity
        uint256 maxUnstETHIdsCount = 1;

        vm.startPrank(sender);
        escrow.claimNextWithdrawalsBatch(maxUnstETHIdsCount);
        vm.stopPrank();

        _escrowInvariants(Mode.Assert);
        _escrowUserInvariants(Mode.Assert, sender);
    }
}
