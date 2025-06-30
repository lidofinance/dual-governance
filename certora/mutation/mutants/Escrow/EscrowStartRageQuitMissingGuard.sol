// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Duration} from "./types/Duration.sol";
import {Timestamp} from "./types/Timestamp.sol";
import {ETHValue, ETHValues} from "./types/ETHValue.sol";
import {SharesValue, SharesValues} from "./types/SharesValue.sol";
import {PercentD16, PercentsD16} from "./types/PercentD16.sol";

import {IEscrow} from "./interfaces/IEscrow.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IWithdrawalQueue, WithdrawalRequestStatus} from "./interfaces/IWithdrawalQueue.sol";
import {IDualGovernance} from "./interfaces/IDualGovernance.sol";

import {EscrowState} from "./libraries/EscrowState.sol";
import {WithdrawalsBatchesQueue} from "./libraries/WithdrawalBatchesQueue.sol";
import {HolderAssets, StETHAccounting, UnstETHAccounting, AssetsAccounting} from "./libraries/AssetsAccounting.sol";

/// @notice Summary of the total locked assets in the Escrow
/// @param stETHLockedShares Total number of stETH shares locked in the Escrow
/// @param stETHClaimedETH Total amount of ETH claimed from the stETH locked in the Escrow
/// @param unstETHUnfinalizedShares Total number of shares from unstETH NFTs that have not yet been
/// marked as finalized
/// @param unstETHFinalizedETH Total claimable amount of ETH from unstETH NFTs that have been marked
/// as finalized
struct LockedAssetsTotals {
    uint256 stETHLockedShares;
    uint256 stETHClaimedETH;
    uint256 unstETHUnfinalizedShares;
    uint256 unstETHFinalizedETH;
}

struct VetoerState {
    uint256 stETHLockedShares;
    uint256 unstETHLockedShares;
    uint256 unstETHIdsCount;
    uint256 lastAssetsLockTimestamp;
}

contract Escrow is IEscrow {
    using EscrowState for EscrowState.Context;
    using AssetsAccounting for AssetsAccounting.Context;
    using WithdrawalsBatchesQueue for WithdrawalsBatchesQueue.Context;

    // ---
    // Errors
    // ---

    error UnclaimedBatches();
    error UnexpectedUnstETHId();
    error UnfinalizedUnstETHIds();
    error NonProxyCallsForbidden();
    error BatchesQueueIsNotClosed();
    error InvalidBatchSize(uint256 size);
    error CallerIsNotDualGovernance(address caller);
    error InvalidHintsLength(uint256 actual, uint256 expected);
    error InvalidETHSender(address actual, address expected);

    // ---
    // Events
    // ---

    event ConfigProviderSet(address newConfigProvider);

    // ---
    // Sanity check params immutables
    // ---

    uint256 public immutable MIN_WITHDRAWALS_BATCH_SIZE;

    // ---
    // Dependencies immutables
    // ---

    IStETH public immutable ST_ETH;
    IWstETH public immutable WST_ETH;
    IWithdrawalQueue public immutable WITHDRAWAL_QUEUE;

    // ---
    // Implementation immutables

    address private immutable _SELF;
    IDualGovernance public immutable DUAL_GOVERNANCE;

    // ---
    // Aspects
    // ---

    EscrowState.Context internal _escrowState;
    AssetsAccounting.Context private _accounting;
    WithdrawalsBatchesQueue.Context private _batchesQueue;

    // ---
    // Construction & initializing
    // ---

    constructor(
        IStETH stETH,
        IWstETH wstETH,
        IWithdrawalQueue withdrawalQueue,
        IDualGovernance dualGovernance,
        uint256 minWithdrawalsBatchSize
    ) {
        _SELF = address(this);
        DUAL_GOVERNANCE = dualGovernance;

        ST_ETH = stETH;
        WST_ETH = wstETH;
        WITHDRAWAL_QUEUE = withdrawalQueue;

        MIN_WITHDRAWALS_BATCH_SIZE = minWithdrawalsBatchSize;
    }

    function initialize(Duration minAssetsLockDuration) external {
        if (address(this) == _SELF) {
            revert NonProxyCallsForbidden();
        }
        _checkCallerIsDualGovernance();

        _escrowState.initialize(minAssetsLockDuration);

        ST_ETH.approve(address(WST_ETH), type(uint256).max);
        ST_ETH.approve(address(WITHDRAWAL_QUEUE), type(uint256).max);
    }

    // ---
    // Lock & unlock stETH
    // ---

    function lockStETH(uint256 amount) external returns (uint256 lockedStETHShares) {
        _escrowState.checkSignallingEscrow();
        DUAL_GOVERNANCE.activateNextState();

        lockedStETHShares = ST_ETH.getSharesByPooledEth(amount);
        _accounting.accountStETHSharesLock(msg.sender, SharesValues.from(lockedStETHShares));
        ST_ETH.transferSharesFrom(msg.sender, address(this), lockedStETHShares);

        DUAL_GOVERNANCE.activateNextState();
    }

    function unlockStETH() external returns (uint256 unlockedStETHShares) {
        _escrowState.checkSignallingEscrow();

        DUAL_GOVERNANCE.activateNextState();
        _accounting.checkMinAssetsLockDurationPassed(msg.sender, _escrowState.minAssetsLockDuration);
        unlockedStETHShares = _accounting.accountStETHSharesUnlock(msg.sender).toUint256();
        ST_ETH.transferShares(msg.sender, unlockedStETHShares);

        DUAL_GOVERNANCE.activateNextState();
    }

    // ---
    // Lock & unlock wstETH
    // ---

    function lockWstETH(uint256 amount) external returns (uint256 lockedStETHShares) {
        _escrowState.checkSignallingEscrow();
        DUAL_GOVERNANCE.activateNextState();

        WST_ETH.transferFrom(msg.sender, address(this), amount);
        lockedStETHShares = ST_ETH.getSharesByPooledEth(WST_ETH.unwrap(amount));
        _accounting.accountStETHSharesLock(msg.sender, SharesValues.from(lockedStETHShares));

        DUAL_GOVERNANCE.activateNextState();
    }

    function unlockWstETH() external returns (uint256 unlockedStETHShares) {
        _escrowState.checkSignallingEscrow();
        DUAL_GOVERNANCE.activateNextState();

        _accounting.checkMinAssetsLockDurationPassed(msg.sender, _escrowState.minAssetsLockDuration);
        SharesValue wstETHUnlocked = _accounting.accountStETHSharesUnlock(msg.sender);
        unlockedStETHShares = WST_ETH.wrap(ST_ETH.getPooledEthByShares(wstETHUnlocked.toUint256()));
        WST_ETH.transfer(msg.sender, unlockedStETHShares);

        DUAL_GOVERNANCE.activateNextState();
    }

    // ---
    // Lock & unlock unstETH
    // ---
    function lockUnstETH(uint256[] memory unstETHIds) external {
        _escrowState.checkSignallingEscrow();
        DUAL_GOVERNANCE.activateNextState();

        WithdrawalRequestStatus[] memory statuses = WITHDRAWAL_QUEUE.getWithdrawalStatus(unstETHIds);
        _accounting.accountUnstETHLock(msg.sender, unstETHIds, statuses);
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            WITHDRAWAL_QUEUE.transferFrom(msg.sender, address(this), unstETHIds[i]);
        }

        DUAL_GOVERNANCE.activateNextState();
    }

    function unlockUnstETH(uint256[] memory unstETHIds) external {
        _escrowState.checkSignallingEscrow();
        DUAL_GOVERNANCE.activateNextState();

        _accounting.checkMinAssetsLockDurationPassed(msg.sender, _escrowState.minAssetsLockDuration);
        _accounting.accountUnstETHUnlock(msg.sender, unstETHIds);
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            WITHDRAWAL_QUEUE.transferFrom(address(this), msg.sender, unstETHIds[i]);
        }

        DUAL_GOVERNANCE.activateNextState();
    }

    function markUnstETHFinalized(uint256[] memory unstETHIds, uint256[] calldata hints) external {
        _escrowState.checkSignallingEscrow();

        uint256[] memory claimableAmounts = WITHDRAWAL_QUEUE.getClaimableEther(unstETHIds, hints);
        _accounting.accountUnstETHFinalized(unstETHIds, claimableAmounts);
    }

    // ---
    // Convert to NFT
    // ---

    function requestWithdrawals(uint256[] calldata stETHAmounts) external returns (uint256[] memory unstETHIds) {
        _escrowState.checkSignallingEscrow();

        unstETHIds = WITHDRAWAL_QUEUE.requestWithdrawals(stETHAmounts, address(this));
        WithdrawalRequestStatus[] memory statuses = WITHDRAWAL_QUEUE.getWithdrawalStatus(unstETHIds);

        uint256 sharesTotal = 0;
        for (uint256 i = 0; i < statuses.length; ++i) {
            sharesTotal += statuses[i].amountOfShares;
        }
        _accounting.accountStETHSharesUnlock(msg.sender, SharesValues.from(sharesTotal));
        _accounting.accountUnstETHLock(msg.sender, unstETHIds, statuses);
    }

    // ---
    // Start rage quit
    // ---

    function startRageQuit(Duration rageQuitExtensionDelay, Duration rageQuitWithdrawalsTimelock) external {
        // mutated
        //_checkCallerIsDualGovernance();
        _escrowState.startRageQuit(rageQuitExtensionDelay, rageQuitWithdrawalsTimelock);
        _batchesQueue.open(WITHDRAWAL_QUEUE.getLastRequestId());
    }

    // ---
    // Request withdrawal batches
    // ---

    function requestNextWithdrawalsBatch(uint256 batchSize) external {
        _escrowState.checkRageQuitEscrow();

        if (batchSize < MIN_WITHDRAWALS_BATCH_SIZE) {
            revert InvalidBatchSize(batchSize);
        }

        uint256 stETHRemaining = ST_ETH.balanceOf(address(this));
        uint256 minStETHWithdrawalRequestAmount = WITHDRAWAL_QUEUE.MIN_STETH_WITHDRAWAL_AMOUNT();
        uint256 maxStETHWithdrawalRequestAmount = WITHDRAWAL_QUEUE.MAX_STETH_WITHDRAWAL_AMOUNT();

        if (stETHRemaining < minStETHWithdrawalRequestAmount) {
            return _batchesQueue.close();
        }

        uint256[] memory requestAmounts = WithdrawalsBatchesQueue.calcRequestAmounts({
            minRequestAmount: minStETHWithdrawalRequestAmount,
            maxRequestAmount: maxStETHWithdrawalRequestAmount,
            remainingAmount: Math.min(stETHRemaining, maxStETHWithdrawalRequestAmount * batchSize)
        });

        _batchesQueue.addUnstETHIds(WITHDRAWAL_QUEUE.requestWithdrawals(requestAmounts, address(this)));
    }

    // ---
    // Claim requested withdrawal batches
    // ---

    function claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount) external {
        _escrowState.checkRageQuitEscrow();
        _escrowState.checkBatchesClaimingInProgress();

        uint256[] memory unstETHIds = _batchesQueue.claimNextBatch(maxUnstETHIdsCount);

        _claimNextWithdrawalsBatch(
            unstETHIds[0],
            unstETHIds,
            WITHDRAWAL_QUEUE.findCheckpointHints(unstETHIds, 1, WITHDRAWAL_QUEUE.getLastCheckpointIndex())
        );
    }

    function claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] calldata hints) external {
        _escrowState.checkRageQuitEscrow();
        _escrowState.checkBatchesClaimingInProgress();

        uint256[] memory unstETHIds = _batchesQueue.claimNextBatch(hints.length);

        _claimNextWithdrawalsBatch(fromUnstETHId, unstETHIds, hints);
    }

    // ---
    // Start rage quit extension delay
    // ---

    function startRageQuitExtensionDelay() external {
        if (!_batchesQueue.isClosed()) {
            revert BatchesQueueIsNotClosed();
        }

        /// @dev This check is primarily required when only unstETH NFTs are locked in the Escrow
        /// and there are no WithdrawalBatches. In this scenario, the RageQuitExtensionDelay can only begin
        /// when the last locked unstETH id is finalized in the WithdrawalQueue.
        /// When the WithdrawalBatchesQueue is not empty, this invariant is maintained by the following:
        /// - Any locked unstETH during the VetoSignalling phase has an id less than any unstETH NFT created
        ///   during the request for withdrawal batches.
        /// - Claiming the withdrawal batches requires the finalization of the unstETH with the given id.
        /// - The finalization of unstETH NFTs occurs in FIFO order.
        if (_batchesQueue.getLastClaimedOrBoundaryUnstETHId() > WITHDRAWAL_QUEUE.getLastFinalizedRequestId()) {
            revert UnfinalizedUnstETHIds();
        }

        if (!_batchesQueue.isAllBatchesClaimed()) {
            revert UnclaimedBatches();
        }

        _escrowState.startRageQuitExtensionDelay();
    }

    // ---
    // Claim locked unstETH NFTs
    // ---

    function claimUnstETH(uint256[] calldata unstETHIds, uint256[] calldata hints) external {
        _escrowState.checkRageQuitEscrow();
        uint256[] memory claimableAmounts = WITHDRAWAL_QUEUE.getClaimableEther(unstETHIds, hints);

        ETHValue ethBalanceBefore = ETHValues.fromAddressBalance(address(this));
        WITHDRAWAL_QUEUE.claimWithdrawals(unstETHIds, hints);
        ETHValue ethBalanceAfter = ETHValues.fromAddressBalance(address(this));

        ETHValue totalAmountClaimed = _accounting.accountUnstETHClaimed(unstETHIds, claimableAmounts);
        assert(totalAmountClaimed == ethBalanceAfter - ethBalanceBefore);
    }

    // ---
    // Escrow management
    // ---

    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external {
        _checkCallerIsDualGovernance();
        _escrowState.setMinAssetsLockDuration(newMinAssetsLockDuration);
    }

    // ---
    // Withdraw logic
    // ---

    function withdrawETH() external {
        _escrowState.checkRageQuitEscrow();
        _escrowState.checkWithdrawalsTimelockPassed();
        ETHValue ethToWithdraw = _accounting.accountStETHSharesWithdraw(msg.sender);
        ethToWithdraw.sendTo(payable(msg.sender));
    }

    function withdrawETH(uint256[] calldata unstETHIds) external {
        _escrowState.checkRageQuitEscrow();
        _escrowState.checkWithdrawalsTimelockPassed();
        ETHValue ethToWithdraw = _accounting.accountUnstETHWithdraw(msg.sender, unstETHIds);
        ethToWithdraw.sendTo(payable(msg.sender));
    }

    // ---
    // Getters
    // ---

    function getLockedAssetsTotals() external view returns (LockedAssetsTotals memory totals) {
        StETHAccounting memory stETHTotals = _accounting.stETHTotals;
        totals.stETHClaimedETH = stETHTotals.claimedETH.toUint256();
        totals.stETHLockedShares = stETHTotals.lockedShares.toUint256();

        UnstETHAccounting memory unstETHTotals = _accounting.unstETHTotals;
        totals.unstETHUnfinalizedShares = unstETHTotals.unfinalizedShares.toUint256();
        totals.unstETHFinalizedETH = unstETHTotals.finalizedETH.toUint256();
    }

    function getVetoerState(address vetoer) external view returns (VetoerState memory state) {
        HolderAssets storage assets = _accounting.assets[vetoer];

        state.unstETHIdsCount = assets.unstETHIds.length;
        state.stETHLockedShares = assets.stETHLockedShares.toUint256();
        state.unstETHLockedShares = assets.stETHLockedShares.toUint256();
        state.lastAssetsLockTimestamp = assets.lastAssetsLockTimestamp.toSeconds();
    }

    function getUnclaimedUnstETHIdsCount() external view returns (uint256) {
        return _batchesQueue.getTotalUnclaimedUnstETHIdsCount();
    }

    function getNextWithdrawalBatch(uint256 limit) external view returns (uint256[] memory unstETHIds) {
        return _batchesQueue.getNextWithdrawalsBatches(limit);
    }

    function isWithdrawalsBatchesFinalized() external view returns (bool) {
        return _batchesQueue.isClosed();
    }

    function isRageQuitExtensionDelayStarted() external view returns (bool) {
        return _escrowState.isRageQuitExtensionDelayStarted();
    }

    function getRageQuitExtensionDelayStartedAt() external view returns (Timestamp) {
        return _escrowState.rageQuitExtensionDelayStartedAt;
    }

    function getRageQuitSupport() external view returns (PercentD16) {
        StETHAccounting memory stETHTotals = _accounting.stETHTotals;
        UnstETHAccounting memory unstETHTotals = _accounting.unstETHTotals;

        uint256 finalizedETH = unstETHTotals.finalizedETH.toUint256();
        uint256 unfinalizedShares = (stETHTotals.lockedShares + unstETHTotals.unfinalizedShares).toUint256();

        return PercentsD16.fromFraction({
            numerator: ST_ETH.getPooledEthByShares(unfinalizedShares) + finalizedETH,
            denominator: ST_ETH.totalSupply() + finalizedETH
        });
    }

    function isRageQuitFinalized() external view returns (bool) {
        return _escrowState.isRageQuitEscrow() && _escrowState.isRageQuitExtensionDelayPassed();
    }

    // ---
    // Receive ETH
    // ---

    receive() external payable {
        if (msg.sender != address(WITHDRAWAL_QUEUE)) {
            revert InvalidETHSender(msg.sender, address(WITHDRAWAL_QUEUE));
        }
    }

    // ---
    // Internal methods
    // ---

    function _claimNextWithdrawalsBatch(
        uint256 fromUnstETHId,
        uint256[] memory unstETHIds,
        uint256[] memory hints
    ) internal {
        if (fromUnstETHId != unstETHIds[0]) {
            revert UnexpectedUnstETHId();
        }

        if (hints.length != unstETHIds.length) {
            revert InvalidHintsLength(hints.length, unstETHIds.length);
        }

        ETHValue ethBalanceBefore = ETHValues.fromAddressBalance(address(this));
        WITHDRAWAL_QUEUE.claimWithdrawals(unstETHIds, hints);
        ETHValue ethBalanceAfter = ETHValues.fromAddressBalance(address(this));

        _accounting.accountClaimedStETH(ethBalanceAfter - ethBalanceBefore);
    }

    function _checkCallerIsDualGovernance() internal view {
        if (msg.sender != address(DUAL_GOVERNANCE)) {
            revert CallerIsNotDualGovernance(msg.sender);
        }
    }
}
