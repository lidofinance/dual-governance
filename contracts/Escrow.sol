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
import {WithdrawalsBatchesQueue} from "./libraries/WithdrawalsBatchesQueue.sol";
import {HolderAssets, StETHAccounting, UnstETHAccounting, AssetsAccounting} from "./libraries/AssetsAccounting.sol";

/// @notice Summary of the total locked assets in the Escrow.
/// @param stETHLockedShares The total number of stETH shares currently locked in the Escrow.
/// @param stETHClaimedETH The total amount of ETH claimed from the stETH shares locked in the Escrow.
/// @param unstETHUnfinalizedShares The total number of shares from unstETH NFTs that have not yet been marked as finalized.
/// @param unstETHFinalizedETH The total amount of ETH claimable from unstETH NFTs that have been marked as finalized.
struct LockedAssetsTotals {
    uint256 stETHLockedShares;
    uint256 stETHClaimedETH;
    uint256 unstETHUnfinalizedShares;
    uint256 unstETHFinalizedETH;
}

/// @notice Summary of the assets locked in the Escrow by a specific vetoer.
/// @param stETHLockedShares The total number of stETH shares currently locked in the Escrow by the vetoer.
/// @param unstETHLockedShares The total number of unstETH shares currently locked in the Escrow by the vetoer.
/// @param unstETHIdsCount The total number of unstETH NFTs locked in the Escrow by the vetoer.
/// @param lastAssetsLockTimestamp The timestamp of the last time the vetoer locked stETH, wstETH, or unstETH in the Escrow.
struct VetoerState {
    uint256 stETHLockedShares;
    uint256 unstETHLockedShares;
    uint256 unstETHIdsCount;
    uint256 lastAssetsLockTimestamp;
}

/// @notice This contract is used to accumulate stETH, wstETH, unstETH, and withdrawn ETH from vetoers during the
///     veto signalling and rage quit processes.
/// @dev This contract is intended to be used behind a minimal proxy deployed by the DualGovernance contract.
contract Escrow is IEscrow {
    using EscrowState for EscrowState.Context;
    using AssetsAccounting for AssetsAccounting.Context;
    using WithdrawalsBatchesQueue for WithdrawalsBatchesQueue.Context;

    // ---
    // Errors
    // ---
    error EmptyUnstETHIds();
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
    // Constants
    // ---

    /// @dev The lower limit for stETH transfers when requesting a withdrawal batch
    ///     during the Rage Quit phase. For more details, see https://github.com/lidofinance/lido-dao/issues/442.
    ///     The current value is chosen to ensure functionality over an extended period, spanning several decades.
    uint256 private constant _MIN_TRANSFERRABLE_ST_ETH_AMOUNT = 8 wei;

    // ---
    // Sanity Check Parameters & Immutables
    // ---

    /// @notice The minimum number of withdrawal requests allowed to create during a single call of
    ///     the `Escrow.requestNextWithdrawalsBatch(batchSize)` method.
    uint256 public immutable MIN_WITHDRAWALS_BATCH_SIZE;

    // ---
    // Dependencies Immutables
    // ---

    /// @notice The address of the stETH token.
    IStETH public immutable ST_ETH;

    /// @notice The address of the wstETH token.
    IWstETH public immutable WST_ETH;

    /// @notice The address of Lido's Withdrawal Queue and the unstETH token.
    IWithdrawalQueue public immutable WITHDRAWAL_QUEUE;

    // ---
    // Implementation Immutables
    // ---

    /// @dev Reference to the address of the implementation contract, used to distinguish whether the call
    ///     is made to the proxy or directly to the implementation.
    address private immutable _SELF;

    /// @dev The address of the Dual Governance contract.
    IDualGovernance public immutable DUAL_GOVERNANCE;

    // ---
    // Aspects
    // ---

    /// @dev Provides the functionality to manage the state of the Escrow.
    EscrowState.Context internal _escrowState;

    /// @dev Handles the accounting of assets locked in the Escrow.
    AssetsAccounting.Context private _accounting;

    /// @dev Manages the queue of withdrawal request batches generated from the locked stETH and wstETH tokens.
    WithdrawalsBatchesQueue.Context private _batchesQueue;

    // ---
    // Construction & Initializing
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

    /// @notice Initializes the proxy instance with the specified minimum assets lock duration.
    /// @param minAssetsLockDuration The minimum duration that must pass from the last stETH, wstETH, or unstETH lock
    ///     by the vetoer before they are allowed to unlock assets from the Escrow.
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
    // Lock & Unlock stETH
    // ---

    /// @notice Locks the vetoer's specified `amount` of stETH in the Veto Signalling Escrow, thereby increasing
    ///     the rage quit support proportionally to the number of stETH shares locked.
    /// @param amount The amount of stETH to be locked.
    /// @return lockedStETHShares The number of stETH shares locked in the Escrow during the current invocation.
    function lockStETH(uint256 amount) external returns (uint256 lockedStETHShares) {
        DUAL_GOVERNANCE.activateNextState();
        _escrowState.checkSignallingEscrow();

        lockedStETHShares = ST_ETH.getSharesByPooledEth(amount);
        _accounting.accountStETHSharesLock(msg.sender, SharesValues.from(lockedStETHShares));
        ST_ETH.transferSharesFrom(msg.sender, address(this), lockedStETHShares);

        DUAL_GOVERNANCE.activateNextState();
    }

    /// @notice Unlocks all previously locked stETH and wstETH tokens, returning them in the form of stETH tokens.
    ///     This action decreases the rage quit support proportionally to the number of unlocked stETH shares.
    /// @return unlockedStETHShares The total number of stETH shares unlocked from the Escrow.
    function unlockStETH() external returns (uint256 unlockedStETHShares) {
        DUAL_GOVERNANCE.activateNextState();
        _escrowState.checkSignallingEscrow();
        _accounting.checkMinAssetsLockDurationPassed(msg.sender, _escrowState.minAssetsLockDuration);

        unlockedStETHShares = _accounting.accountStETHSharesUnlock(msg.sender).toUint256();
        ST_ETH.transferShares(msg.sender, unlockedStETHShares);

        DUAL_GOVERNANCE.activateNextState();
    }

    // ---
    // Lock & Unlock wstETH
    // ---

    /// @notice Locks the vetoer's specified `amount` of wstETH in the Veto Signalling Escrow, thereby increasing
    ///     the rage quit support proportionally to the number of locked wstETH shares.
    /// @param amount The amount of wstETH to be locked.
    /// @return lockedStETHShares The number of wstETH shares locked in the Escrow during the current invocation.
    function lockWstETH(uint256 amount) external returns (uint256 lockedStETHShares) {
        DUAL_GOVERNANCE.activateNextState();
        _escrowState.checkSignallingEscrow();

        WST_ETH.transferFrom(msg.sender, address(this), amount);
        lockedStETHShares = ST_ETH.getSharesByPooledEth(WST_ETH.unwrap(amount));
        _accounting.accountStETHSharesLock(msg.sender, SharesValues.from(lockedStETHShares));

        DUAL_GOVERNANCE.activateNextState();
    }

    /// @notice Unlocks all previously locked stETH and wstETH tokens, returning them in the form of wstETH tokens.
    ///     This action decreases the rage quit support proportionally to the number of unlocked wstETH shares.
    /// @return wstETHUnlocked The total number of wstETH shares unlocked from the Escrow.
    function unlockWstETH() external returns (uint256 wstETHUnlocked) {
        DUAL_GOVERNANCE.activateNextState();
        _escrowState.checkSignallingEscrow();
        _accounting.checkMinAssetsLockDurationPassed(msg.sender, _escrowState.minAssetsLockDuration);

        SharesValue unlockedStETHShares = _accounting.accountStETHSharesUnlock(msg.sender);
        wstETHUnlocked = WST_ETH.wrap(ST_ETH.getPooledEthByShares(unlockedStETHShares.toUint256()));
        WST_ETH.transfer(msg.sender, wstETHUnlocked);

        DUAL_GOVERNANCE.activateNextState();
    }

    // ---
    // Lock & Unlock unstETH
    // ---

    /// @notice Locks the specified unstETH NFTs, identified by their ids, in the Veto Signalling Escrow, thereby increasing
    ///     the rage quit support proportionally to the total number of stETH shares contained in the locked unstETH NFTs.
    /// @dev Locking finalized or already claimed unstETH NFTs is prohibited.
    /// @param unstETHIds An array of ids representing the unstETH NFTs to be locked.
    function lockUnstETH(uint256[] memory unstETHIds) external {
        if (unstETHIds.length == 0) {
            revert EmptyUnstETHIds();
        }
        DUAL_GOVERNANCE.activateNextState();
        _escrowState.checkSignallingEscrow();

        WithdrawalRequestStatus[] memory statuses = WITHDRAWAL_QUEUE.getWithdrawalStatus(unstETHIds);
        _accounting.accountUnstETHLock(msg.sender, unstETHIds, statuses);
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            WITHDRAWAL_QUEUE.transferFrom(msg.sender, address(this), unstETHIds[i]);
        }

        DUAL_GOVERNANCE.activateNextState();
    }

    /// @notice Unlocks the specified unstETH NFTs, identified by their ids, from the Veto Signalling Escrow
    ///     that were previously locked by the vetoer.
    /// @param unstETHIds An array of ids representing the unstETH NFTs to be unlocked.
    function unlockUnstETH(uint256[] memory unstETHIds) external {
        if (unstETHIds.length == 0) {
            revert EmptyUnstETHIds();
        }
        DUAL_GOVERNANCE.activateNextState();
        _escrowState.checkSignallingEscrow();
        _accounting.checkMinAssetsLockDurationPassed(msg.sender, _escrowState.minAssetsLockDuration);

        _accounting.accountUnstETHUnlock(msg.sender, unstETHIds);
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            WITHDRAWAL_QUEUE.transferFrom(address(this), msg.sender, unstETHIds[i]);
        }

        DUAL_GOVERNANCE.activateNextState();
    }

    /// @notice Marks the specified locked unstETH NFTs as finalized to update the rage quit support value
    ///     in the Veto Signalling Escrow.
    /// @dev Finalizing a withdrawal NFT results in the following state changes:
    ///        - The value of the finalized unstETH NFT is no longer influenced by stETH token rebases.
    ///        - The total supply of stETH is adjusted according to the value of the finalized unstETH NFT.
    ///     These changes impact the rage quit support value. This function updates the status of the specified
    ///     unstETH NFTs to ensure accurate rage quit support accounting in the Veto Signalling Escrow.
    /// @param unstETHIds An array of ids representing the unstETH NFTs to be marked as finalized.
    /// @param hints An array of hints required by the WithdrawalQueue to efficiently retrieve
    ///        the claimable amounts for the unstETH NFTs.
    function markUnstETHFinalized(uint256[] memory unstETHIds, uint256[] calldata hints) external {
        DUAL_GOVERNANCE.activateNextState();
        _escrowState.checkSignallingEscrow();

        uint256[] memory claimableAmounts = WITHDRAWAL_QUEUE.getClaimableEther(unstETHIds, hints);
        _accounting.accountUnstETHFinalized(unstETHIds, claimableAmounts);
        DUAL_GOVERNANCE.activateNextState();
    }

    // ---
    // Start Rage Quit
    // ---

    /// @notice Irreversibly converts the Signalling Escrow into the Rage Quit Escrow, allowing vetoers who have locked
    ///     their funds in the Signalling Escrow to withdraw them in the form of ETH after the Rage Quit process
    ///     is completed and the specified withdrawal delay has passed.
    /// @param rageQuitExtensionPeriodDuration The duration that starts after all withdrawal batches are formed, extending
    ///     the Rage Quit state in Dual Governance. This extension period ensures that users who have locked their unstETH
    ///     have sufficient time to claim it.
    /// @param rageQuitEthWithdrawalsDelay The waiting period that vetoers must observe after the Rage Quit process
    ///     is finalized before they can withdraw ETH from the Escrow.
    function startRageQuit(Duration rageQuitExtensionPeriodDuration, Duration rageQuitEthWithdrawalsDelay) external {
        _checkCallerIsDualGovernance();
        _escrowState.startRageQuit(rageQuitExtensionPeriodDuration, rageQuitEthWithdrawalsDelay);
        _batchesQueue.open(WITHDRAWAL_QUEUE.getLastRequestId());
    }

    // ---
    // Request Withdrawal Batches
    // ---

    /// @notice Creates unstETH NFTs from the stETH held in the Rage Quit Escrow via the WithdrawalQueue contract.
    ///     This function can be called multiple times until the Rage Quit Escrow no longer holds enough stETH
    ///     to create a withdrawal request.
    /// @param batchSize The number of withdrawal requests to process in this batch.
    function requestNextWithdrawalsBatch(uint256 batchSize) external {
        _escrowState.checkRageQuitEscrow();

        if (batchSize < MIN_WITHDRAWALS_BATCH_SIZE) {
            revert InvalidBatchSize(batchSize);
        }

        uint256 stETHRemaining = ST_ETH.balanceOf(address(this));
        uint256 minStETHWithdrawalRequestAmount = WITHDRAWAL_QUEUE.MIN_STETH_WITHDRAWAL_AMOUNT();
        uint256 maxStETHWithdrawalRequestAmount = WITHDRAWAL_QUEUE.MAX_STETH_WITHDRAWAL_AMOUNT();

        /// @dev The remaining stETH amount must be greater than the minimum threshold to create a withdrawal request.
        ///     Using only `minStETHWithdrawalRequestAmount` is insufficient because it is an external variable
        ///     that could be decreased independently. Introducing `minWithdrawableStETHAmount` provides
        ///     an internal safeguard, enforcing a minimum threshold within the contract.
        uint256 minWithdrawableStETHAmount = Math.max(_MIN_TRANSFERRABLE_ST_ETH_AMOUNT, minStETHWithdrawalRequestAmount);

        if (stETHRemaining < minWithdrawableStETHAmount) {
            return _batchesQueue.close();
        }

        uint256[] memory requestAmounts = WithdrawalsBatchesQueue.calcRequestAmounts({
            minRequestAmount: minStETHWithdrawalRequestAmount,
            maxRequestAmount: maxStETHWithdrawalRequestAmount,
            remainingAmount: Math.min(stETHRemaining, maxStETHWithdrawalRequestAmount * batchSize)
        });

        _batchesQueue.addUnstETHIds(WITHDRAWAL_QUEUE.requestWithdrawals(requestAmounts, address(this)));

        stETHRemaining = ST_ETH.balanceOf(address(this));

        if (stETHRemaining < minWithdrawableStETHAmount) {
            _batchesQueue.close();
        }
    }

    // ---
    // Claim Requested Withdrawal Batches
    // ---

    /// @notice Allows the claim of finalized withdrawal NFTs generated via the `Escrow.requestNextWithdrawalsBatch()` method.
    ///     The unstETH NFTs must be claimed sequentially, starting from the provided `fromUnstETHId`, which must be
    ///     the first unclaimed unstETH NFT.
    /// @param fromUnstETHId The id of the first unclaimed unstETH NFT in the batch to be claimed.
    /// @param hints An array of hints required by the `WithdrawalQueue` contract to efficiently process
    ///     the claiming of unstETH NFTs.
    function claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] calldata hints) external {
        _escrowState.checkRageQuitEscrow();
        _escrowState.checkBatchesClaimingInProgress();

        uint256[] memory unstETHIds = _batchesQueue.claimNextBatch(hints.length);

        _claimNextWithdrawalsBatch(fromUnstETHId, unstETHIds, hints);
    }

    /// @notice An overloaded version of `Escrow.claimNextWithdrawalsBatch(uint256, uint256[] calldata)` that calculates
    ///     hints for the WithdrawalQueue on-chain. This method provides a more convenient claiming process but is
    ///     less gas efficient compared to `Escrow.claimNextWithdrawalsBatch(uint256, uint256[] calldata)`.
    /// @param maxUnstETHIdsCount The maximum number of unstETH NFTs to claim in this batch.
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

    // ---
    // Start Rage Quit Extension Delay
    // ---

    /// @notice Initiates the Rage Quit Extension Period once all withdrawal batches have been claimed.
    ///     For cases where the `Escrow` instance holds only locked unstETH NFTs, this function ensures that the last
    ///     unstETH NFT registered in the `WithdrawalQueue` at the time of the `Escrow.startRageQuit()` call is finalized.
    ///     The Rage Quit Extension Period provides additional time for vetoers who locked their unstETH NFTs in the
    ///     Escrow to claim them.
    function startRageQuitExtensionPeriod() external {
        if (!_batchesQueue.isClosed()) {
            revert BatchesQueueIsNotClosed();
        }

        /// @dev This check is primarily required when only unstETH NFTs are locked in the Escrow
        ///     and there are no WithdrawalsBatches. In this scenario, the RageQuitExtensionPeriod can only begin
        ///     when the last locked unstETH id is finalized in the WithdrawalQueue.
        ///     When the WithdrawalsBatchesQueue is not empty, this invariant is maintained by the following:
        ///         - Any locked unstETH during the VetoSignalling phase has an id less than any unstETH NFT created
        ///           during the request for withdrawal batches.
        ///         - Claiming the withdrawal batches requires the finalization of the unstETH with the given id.
        ///         - The finalization of unstETH NFTs occurs in FIFO order.
        if (_batchesQueue.getLastClaimedOrBoundaryUnstETHId() > WITHDRAWAL_QUEUE.getLastFinalizedRequestId()) {
            revert UnfinalizedUnstETHIds();
        }

        if (!_batchesQueue.isAllBatchesClaimed()) {
            revert UnclaimedBatches();
        }

        _escrowState.startRageQuitExtensionPeriod();
    }

    // ---
    // Claim Locked unstETH NFTs
    // ---

    /// @notice Allows users to claim finalized unstETH NFTs locked in the Rage Quit Escrow contract.
    ///     To safeguard the ETH associated with withdrawal NFTs, this function should be invoked while the `Escrow`
    ///     is in the `RageQuitEscrow` state and before the `RageQuitExtensionPeriod` ends. Any ETH corresponding to
    ///     unclaimed withdrawal NFTs after this period will remain controlled by code potentially influenced by pending
    ///     and future DAO decisions.
    /// @param unstETHIds An array of ids representing the unstETH NFTs to be claimed.
    /// @param hints An array of hints required by the `WithdrawalQueue` contract to efficiently process
    ///     the claiming of unstETH NFTs.
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
    // Escrow Management
    // ---

    /// @notice Sets the minimum duration that must elapse after the last stETH, wstETH, or unstETH lock
    ///     by a vetoer before they are permitted to unlock their assets from the Escrow.
    /// @param newMinAssetsLockDuration The new minimum lock duration to be set.
    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external {
        _checkCallerIsDualGovernance();
        _escrowState.setMinAssetsLockDuration(newMinAssetsLockDuration);
    }

    // ---
    // Withdraw Logic
    // ---

    /// @notice Allows the caller (i.e., `msg.sender`) to withdraw all stETH and wstETH they have previously locked
    ///     into the contract (while it was in the Signalling state) as plain ETH, provided that
    ///     the Rage Quit process is completed and the Rage Quit Eth Withdrawals Delay has elapsed.
    function withdrawETH() external {
        _escrowState.checkRageQuitEscrow();
        _escrowState.checkEthWithdrawalsDelayPassed();
        ETHValue ethToWithdraw = _accounting.accountStETHSharesWithdraw(msg.sender);
        ethToWithdraw.sendTo(payable(msg.sender));
    }

    /// @notice Allows the caller (i.e., `msg.sender`) to withdraw the claimed ETH from the specified unstETH NFTs
    ///     that were locked by the caller in the contract while it was in the Signalling state.
    /// @param unstETHIds An array of ids representing the unstETH NFTs from which the caller wants to withdraw ETH.
    function withdrawETH(uint256[] calldata unstETHIds) external {
        if (unstETHIds.length == 0) {
            revert EmptyUnstETHIds();
        }
        _escrowState.checkRageQuitEscrow();
        _escrowState.checkEthWithdrawalsDelayPassed();
        ETHValue ethToWithdraw = _accounting.accountUnstETHWithdraw(msg.sender, unstETHIds);
        ethToWithdraw.sendTo(payable(msg.sender));
    }

    // ---
    // Getters
    // ---

    /// @notice Returns the total amounts of locked and claimed assets in the Escrow.
    /// @return totals A struct containing the total amounts of locked and claimed assets, including:
    ///     - `stETHClaimedETH`: The total amount of ETH claimed from locked stETH.
    ///     - `stETHLockedShares`: The total number of stETH shares currently locked in the Escrow.
    ///     - `unstETHUnfinalizedShares`: The total number of shares from unstETH NFTs that have not yet been finalized.
    ///     - `unstETHFinalizedETH`: The total amount of ETH from finalized unstETH NFTs.
    function getLockedAssetsTotals() external view returns (LockedAssetsTotals memory totals) {
        StETHAccounting memory stETHTotals = _accounting.stETHTotals;
        totals.stETHClaimedETH = stETHTotals.claimedETH.toUint256();
        totals.stETHLockedShares = stETHTotals.lockedShares.toUint256();

        UnstETHAccounting memory unstETHTotals = _accounting.unstETHTotals;
        totals.unstETHUnfinalizedShares = unstETHTotals.unfinalizedShares.toUint256();
        totals.unstETHFinalizedETH = unstETHTotals.finalizedETH.toUint256();
    }

    /// @notice Returns the state of locked assets for a specific vetoer.
    /// @param vetoer The address of the vetoer whose locked asset state is being queried.
    /// @return state A struct containing information about the vetoer's locked assets, including:
    ///     - `stETHLockedShares`: The total number of stETH shares locked by the vetoer.
    ///     - `unstETHLockedShares`: The total number of unstETH shares locked by the vetoer.
    ///     - `unstETHIdsCount`: The total number of unstETH NFTs locked by the vetoer.
    ///     - `lastAssetsLockTimestamp`: The timestamp of the last assets lock by the vetoer.
    function getVetoerState(address vetoer) external view returns (VetoerState memory state) {
        HolderAssets storage assets = _accounting.assets[vetoer];

        state.unstETHIdsCount = assets.unstETHIds.length;
        state.stETHLockedShares = assets.stETHLockedShares.toUint256();
        state.unstETHLockedShares = assets.unstETHLockedShares.toUint256();
        state.lastAssetsLockTimestamp = assets.lastAssetsLockTimestamp.toSeconds();
    }

    /// @notice Returns the total count of unstETH NFTs that have not been claimed yet.
    /// @return unclaimedUnstETHIdsCount The total number of unclaimed unstETH NFTs.
    function getUnclaimedUnstETHIdsCount() external view returns (uint256) {
        return _batchesQueue.getTotalUnclaimedUnstETHIdsCount();
    }

    /// @notice Retrieves the unstETH NFT ids of the next batch available for claiming.
    /// @param limit The maximum number of unstETH NFTs to return in the batch.
    /// @return unstETHIds An array of unstETH NFT IDs available for the next withdrawal batch.
    function getNextWithdrawalBatch(uint256 limit) external view returns (uint256[] memory unstETHIds) {
        return _batchesQueue.getNextWithdrawalsBatches(limit);
    }

    /// @notice Returns whether all withdrawal batches have been finalized.
    /// @return isWithdrawalsBatchesFinalized A boolean value indicating whether all withdrawal batches have been
    ///     finalized (`true`) or not (`false`).
    function isWithdrawalsBatchesFinalized() external view returns (bool) {
        return _batchesQueue.isClosed();
    }

    /// @notice Returns whether the Rage Quit Extension Period has started.
    /// @return isRageQuitExtensionPeriodStarted A boolean value indicating whether the Rage Quit Extension Period
    ///     has started (`true`) or not (`false`).
    function isRageQuitExtensionPeriodStarted() external view returns (bool) {
        return _escrowState.isRageQuitExtensionPeriodStarted();
    }

    /// @notice Returns the timestamp when the Rage Quit Extension Period started.
    /// @return rageQuitExtensionPeriodStartedAt The timestamp when the Rage Quit Extension Period began.
    function getRageQuitExtensionPeriodStartedAt() external view returns (Timestamp) {
        return _escrowState.rageQuitExtensionPeriodStartedAt;
    }

    /// @notice Returns the current Rage Quit support value as a percentage.
    /// @return rageQuitSupport The current Rage Quit support as a `PercentD16` value.
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

    /// @notice Returns whether the Rage Quit process has been finalized.
    /// @return A boolean value indicating whether the Rage Quit process has been finalized (`true`) or not (`false`).
    function isRageQuitFinalized() external view returns (bool) {
        return _escrowState.isRageQuitEscrow() && _escrowState.isRageQuitExtensionPeriodPassed();
    }

    // ---
    // Receive ETH
    // ---

    /// @notice Accepts ETH payments only from the `WithdrawalQueue` contract.
    receive() external payable {
        if (msg.sender != address(WITHDRAWAL_QUEUE)) {
            revert InvalidETHSender(msg.sender, address(WITHDRAWAL_QUEUE));
        }
    }

    // ---
    // Internal Methods
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

        _accounting.accountClaimedETH(ethBalanceAfter - ethBalanceBefore);
    }

    function _checkCallerIsDualGovernance() internal view {
        if (msg.sender != address(DUAL_GOVERNANCE)) {
            revert CallerIsNotDualGovernance(msg.sender);
        }
    }
}
