pragma solidity 0.8.26;

import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import {Escrow} from "contracts/Escrow.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {State as EscrowSt} from "contracts/libraries/EscrowState.sol";

import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";
import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {SharesValue} from "contracts/types/SharesValue.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import "test/kontrol/model/StETHModel.sol";
import "test/kontrol/model/WithdrawalQueueModel.sol";
import "test/kontrol/model/WstETHAdapted.sol";

import {StorageSetup} from "test/kontrol/StorageSetup.sol";

contract EscrowInvariants is StorageSetup {
    function escrowInvariants(Mode mode, Escrow escrow) external view {
        // Number of unstETHs claimed is <= the total number of unstETHs
        uint64 unstEthIdsCount = _getTotalUnstEthIdsCount(escrow);
        uint64 unstEthIdsClaimed = _getTotalUnstEthIdsClaimed(escrow);
        _establish(mode, unstEthIdsClaimed <= unstEthIdsCount);

        // Escrow state is either SignallingEscrow or RageQuitEscrow
        EscrowSt currentState = EscrowSt(_getCurrentState(escrow));
        _establish(mode, 1 <= uint8(currentState));
        _establish(mode, uint8(currentState) <= 2);

        // WithdrawalQueue has infinite allowance
        StETHModel stEth = StETHModel(address(escrow.ST_ETH()));
        address withdrawalQueue = address(escrow.WITHDRAWAL_QUEUE());
        uint256 allowance = stEth.allowance(address(escrow), withdrawalQueue);
        _establish(mode, allowance == type(uint256).max);
    }

    function signallingEscrowInvariants(Mode mode, Escrow escrow) external view {
        // Accounting for locked stETH is backed by the escrow's stETH balance
        // (only applies to signalling escrow, since in the rage quit escrow
        // requestNextWithdrawalsBatch reduces the balance without reducing
        // the accounted shares)
        StETHModel stEth = StETHModel(address(escrow.ST_ETH()));
        uint128 totalLockedShares = _getTotalStEthLockedShares(escrow);
        _establish(mode, totalLockedShares <= stEth.sharesOf(address(escrow)));
        uint256 totalLockedEther = stEth.getPooledEthByShares(totalLockedShares);
        _establish(mode, totalLockedEther <= stEth.balanceOf(address(escrow)));
    }

    function escrowUserInvariants(Mode mode, Escrow escrow, address user) external view {
        SharesValue userLockedSharesWrapped = escrow.getVetoerDetails(user).stETHLockedShares;
        // Unwrapping because <= is not implemented for SharesValue type
        uint128 userLockedShares = SharesValue.unwrap(userLockedSharesWrapped);
        uint128 totalLockedShares = _getTotalStEthLockedShares(escrow);

        _establish(mode, userLockedShares <= totalLockedShares);
    }

    function claimedBatchesInvariants(Mode mode, Escrow escrow) external view {
        // Index of the last claimed batch is <= the total number of batches
        // (<= because they can both be 0 at first)
        uint56 lastClaimedBatchIndex = _getLastClaimedBatchIndex(escrow);
        uint256 batchesLength = _getBatchesLength(escrow);
        _establish(mode, lastClaimedBatchIndex <= batchesLength);

        // UnstETH ids in the last claimed batch are in order
        uint256 firstUnstEthId = _getFirstUnstEthId(escrow, lastClaimedBatchIndex);
        uint256 lastUnstEthId = _getLastUnstEthId(escrow, lastClaimedBatchIndex);
        _establish(mode, firstUnstEthId <= lastUnstEthId);
    }
}
