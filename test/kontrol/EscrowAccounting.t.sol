pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/Configuration.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";

import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import "contracts/model/StETHModel.sol";
import "contracts/model/WithdrawalQueueModel.sol";
import "contracts/model/WstETHAdapted.sol";

import {EscrowInvariants} from "test/kontrol/EscrowInvariants.sol";

contract EscrowAccountingTest is EscrowInvariants {
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

        Escrow escrowMasterCopy = new Escrow(address(stEth), address(wstEth), address(withdrawalQueue), address(config));
        escrow = Escrow(payable(Clones.clone(address(escrowMasterCopy))));
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

    function testEscrowInvariantsHoldInitially() public {
        _setUpInitialState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        _escrowInvariants(Mode.Assert, escrow);
        _signallingEscrowInvariants(Mode.Assert, escrow);
        _escrowUserInvariants(Mode.Assert, escrow, sender);
    }

    function testRequestWithdrawals(uint256 stEthAmount) public {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);

        AccountingRecord memory pre = _saveAccountingRecord(sender, escrow);

        _escrowInvariants(Mode.Assume, escrow);
        _escrowUserInvariants(Mode.Assume, escrow, sender);

        // Only request one withdrawal for simplicity
        uint256[] memory stEthAmounts = new uint256[](1);
        stEthAmounts[0] = stEthAmount;

        vm.startPrank(sender);
        escrow.requestWithdrawals(stEthAmounts);
        vm.stopPrank();

        _escrowInvariants(Mode.Assert, escrow);
        _escrowUserInvariants(Mode.Assert, escrow, sender);

        AccountingRecord memory post = _saveAccountingRecord(sender, escrow);
        assert(post.userSharesLocked == pre.userSharesLocked - stEthAmount);
        assert(post.totalSharesLocked == pre.totalSharesLocked - stEthAmount);
        assert(post.userLastLockedTime == Timestamps.now());
        assert(post.userUnstEthLockedShares == pre.userUnstEthLockedShares + stEthAmount);
        assert(post.unfinalizedShares == pre.unfinalizedShares + stEthAmount);
    }

    function testRequestNextWithdrawalsBatch(uint256 maxBatchSize) public {
        _setUpGenericState();

        vm.assume(EscrowState(_getCurrentState(escrow)) == EscrowState.RageQuitEscrow);

        _escrowInvariants(Mode.Assume, escrow);

        escrow.requestNextWithdrawalsBatch(maxBatchSize);

        _escrowInvariants(Mode.Assert, escrow);
    }

    function testClaimNextWithdrawalsBatch() public {
        _setUpGenericState();

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        vm.assume(stEth.sharesOf(sender) < ethUpperBound);

        vm.assume(EscrowState(_getCurrentState(escrow)) == EscrowState.RageQuitEscrow);

        _escrowInvariants(Mode.Assume, escrow);
        _escrowUserInvariants(Mode.Assume, escrow, sender);

        // Only claim one unstETH for simplicity
        uint256 maxUnstETHIdsCount = 1;

        vm.startPrank(sender);
        escrow.claimNextWithdrawalsBatch(maxUnstETHIdsCount);
        vm.stopPrank();

        _escrowInvariants(Mode.Assert, escrow);
        _escrowUserInvariants(Mode.Assert, escrow, sender);
    }
}
