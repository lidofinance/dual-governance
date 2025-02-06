// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamps, Timestamp} from "../types/Timestamp.sol";
import {ETHValue, ETHValues} from "../types/ETHValue.sol";
import {SharesValue, SharesValues} from "../types/SharesValue.sol";
import {IndexOneBased, IndicesOneBased} from "../types/IndexOneBased.sol";

import {WithdrawalRequestStatus} from "../interfaces/IWithdrawalQueue.sol";

/// @notice Tracks the stETH and unstETH tokens associated with users
/// @param stETHLockedShares Total number of stETH shares held by the user
/// @param unstETHLockedShares Total number of shares contained in the unstETH NFTs held by the user
/// @param lastAssetsLockTimestamp Timestamp of the most recent lock of stETH shares or unstETH NFTs
/// @param unstETHIds List of unstETH ids locked by the user
struct HolderAssets {
    /// @dev slot0: [0..39]
    Timestamp lastAssetsLockTimestamp;
    /// @dev slot0: [40..167]
    SharesValue stETHLockedShares;
    /// @dev slot1: [0..127]
    SharesValue unstETHLockedShares;
    /// @dev slot2: [0..255] - the length of the array + each item occupies 1 slot
    uint256[] unstETHIds;
}

/// @notice Tracks the unfinalized shares and finalized ETH amount of unstETH NFTs
/// @param unfinalizedShares Total number of unfinalized unstETH shares
/// @param finalizedETH Total amount of ETH claimable from finalized unstETH
struct UnstETHAccounting {
    /// @dev slot0: [0..127]
    SharesValue unfinalizedShares;
    /// @dev slot1: [128..255]
    ETHValue finalizedETH;
}

/// @notice Tracks the locked shares and claimed ETH amounts
/// @param lockedShares Total number of accounted stETH shares
/// @param claimedETH Total amount of ETH received from claiming the locked stETH shares
struct StETHAccounting {
    /// @dev slot0: [0..127]
    SharesValue lockedShares;
    /// @dev slot0: [128..255]
    ETHValue claimedETH;
}

/// @notice Represents the state of an accounted WithdrawalRequest
/// @param NotLocked Indicates the default value of the unstETH record, meaning it was not accounted as locked or
///        was unlocked by the account that previously locked it
/// @param Locked Indicates the unstETH record was accounted as locked
/// @param Finalized Indicates the unstETH record was marked as finalized
/// @param Claimed Indicates the unstETH record was claimed
/// @param Withdrawn Indicates the unstETH record was withdrawn after a successful claim
enum UnstETHRecordStatus {
    NotLocked,
    Locked,
    Finalized,
    Claimed,
    Withdrawn
}

/// @notice Stores information about an accounted unstETH NFT
/// @param state The current state of the unstETH record. Refer to `UnstETHRecordStatus` for details.
/// @param index The one-based index of the unstETH record in the `UnstETHAccounting.unstETHIds` array
/// @param lockedBy The address of the account that locked the unstETH
/// @param shares The amount of shares contained in the unstETH
/// @param claimableAmount The amount of claimable ETH contained in the unstETH. This value is 0
///        until the NFT is marked as finalized or claimed.
struct UnstETHRecord {
    /// @dev slot 0: [0..7]
    UnstETHRecordStatus status;
    /// @dev slot 0: [8..39]
    IndexOneBased index;
    /// @dev slot 0: [40..199]
    address lockedBy;
    /// @dev slot 1: [0..127]
    SharesValue shares;
    /// @dev slot 1: [128..255]
    ETHValue claimableAmount;
}

/// @notice Provides functionality for accounting user stETH and unstETH tokens
///         locked in the Escrow contract
library AssetsAccounting {
    /// @notice The context of the AssetsAccounting library
    /// @param stETHTotals The total number of shares and the amount of stETH locked by users
    /// @param unstETHTotals The total number of shares and the amount of unstETH locked by users
    /// @param assets Mapping to store information about the assets locked by each user
    /// @param unstETHRecords Mapping to track the state of the locked unstETH ids
    struct Context {
        /// @dev slot0: [0..255]
        StETHAccounting stETHTotals;
        /// @dev slot1: [0..255]
        UnstETHAccounting unstETHTotals;
        /// @dev slot2: [0..255] empty slot for mapping track in the storage
        mapping(address account => HolderAssets) assets;
        /// @dev slot3: [0..255] empty slot for mapping track in the storage
        mapping(uint256 unstETHId => UnstETHRecord) unstETHRecords;
    }

    // ---
    // Events
    // ---

    event ETHWithdrawn(address indexed holder, SharesValue shares, ETHValue value);
    event StETHSharesLocked(address indexed holder, SharesValue shares);
    event StETHSharesUnlocked(address indexed holder, SharesValue shares);
    event UnstETHFinalized(uint256[] ids, SharesValue finalizedSharesIncrement, ETHValue finalizedAmountIncrement);
    event UnstETHUnlocked(
        address indexed holder, uint256[] ids, SharesValue finalizedSharesIncrement, ETHValue finalizedAmountIncrement
    );
    event UnstETHLocked(address indexed holder, uint256[] ids, SharesValue shares);
    event UnstETHClaimed(uint256[] unstETHIds, ETHValue totalAmountClaimed);
    event UnstETHWithdrawn(uint256[] unstETHIds, ETHValue amountWithdrawn);

    event ETHClaimed(ETHValue amount);

    // ---
    // Errors
    // ---

    error InvalidSharesValue(SharesValue value);
    error InvalidUnstETHStatus(uint256 unstETHId, UnstETHRecordStatus status);
    error InvalidUnstETHHolder(uint256 unstETHId, address actual, address expected);
    error MinAssetsLockDurationNotPassed(Timestamp unlockTimelockExpiresAt);
    error InvalidClaimableAmount(uint256 unstETHId, ETHValue expected, ETHValue actual);

    // ---
    // stETH shares operations accounting
    // ---

    function accountStETHSharesLock(Context storage self, address holder, SharesValue shares) internal {
        _checkNonZeroShares(shares);
        self.stETHTotals.lockedShares = self.stETHTotals.lockedShares + shares;
        HolderAssets storage assets = self.assets[holder];
        assets.stETHLockedShares = assets.stETHLockedShares + shares;
        assets.lastAssetsLockTimestamp = Timestamps.now();
        emit StETHSharesLocked(holder, shares);
    }

    function accountStETHSharesUnlock(Context storage self, address holder) internal returns (SharesValue shares) {
        shares = self.assets[holder].stETHLockedShares;
        accountStETHSharesUnlock(self, holder, shares);
    }

    function accountStETHSharesUnlock(Context storage self, address holder, SharesValue shares) internal {
        _checkNonZeroShares(shares);

        HolderAssets storage assets = self.assets[holder];
        if (assets.stETHLockedShares < shares) {
            revert InvalidSharesValue(shares);
        }

        self.stETHTotals.lockedShares = self.stETHTotals.lockedShares - shares;
        assets.stETHLockedShares = assets.stETHLockedShares - shares;
        emit StETHSharesUnlocked(holder, shares);
    }

    function accountStETHSharesWithdraw(
        Context storage self,
        address holder
    ) internal returns (ETHValue ethWithdrawn) {
        HolderAssets storage assets = self.assets[holder];
        SharesValue stETHSharesToWithdraw = assets.stETHLockedShares;

        _checkNonZeroShares(stETHSharesToWithdraw);

        assets.stETHLockedShares = SharesValues.ZERO;
        ethWithdrawn =
            SharesValues.calcETHValue(self.stETHTotals.claimedETH, stETHSharesToWithdraw, self.stETHTotals.lockedShares);

        emit ETHWithdrawn(holder, stETHSharesToWithdraw, ethWithdrawn);
    }

    function accountClaimedStETH(Context storage self, ETHValue amount) internal {
        self.stETHTotals.claimedETH = self.stETHTotals.claimedETH + amount;
        emit ETHClaimed(amount);
    }

    // ---
    // unstETH operations accounting
    // ---

    function accountUnstETHLock(
        Context storage self,
        address holder,
        uint256[] memory unstETHIds,
        WithdrawalRequestStatus[] memory statuses
    ) internal {
        assert(unstETHIds.length == statuses.length);

        SharesValue totalUnstETHLocked;
        uint256 unstETHcount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHcount; ++i) {
            totalUnstETHLocked = totalUnstETHLocked + _addUnstETHRecord(self, holder, unstETHIds[i], statuses[i]);
        }
        self.assets[holder].lastAssetsLockTimestamp = Timestamps.now();
        self.assets[holder].unstETHLockedShares = self.assets[holder].unstETHLockedShares + totalUnstETHLocked;
        self.unstETHTotals.unfinalizedShares = self.unstETHTotals.unfinalizedShares + totalUnstETHLocked;

        emit UnstETHLocked(holder, unstETHIds, totalUnstETHLocked);
    }

    function accountUnstETHUnlock(Context storage self, address holder, uint256[] memory unstETHIds) internal {
        SharesValue totalSharesUnlocked;
        SharesValue totalFinalizedSharesUnlocked;
        ETHValue totalFinalizedAmountUnlocked;

        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            (SharesValue sharesUnlocked, ETHValue finalizedAmountUnlocked) =
                _removeUnstETHRecord(self, holder, unstETHIds[i]);
            if (finalizedAmountUnlocked > ETHValues.ZERO) {
                totalFinalizedAmountUnlocked = totalFinalizedAmountUnlocked + finalizedAmountUnlocked;
                totalFinalizedSharesUnlocked = totalFinalizedSharesUnlocked + sharesUnlocked;
            }
            totalSharesUnlocked = totalSharesUnlocked + sharesUnlocked;
        }
        // mutated
        self.assets[holder].unstETHLockedShares = self.assets[holder].unstETHLockedShares - SharesValues.from(1);
        // self.assets[holder].unstETHLockedShares = self.assets[holder].unstETHLockedShares - totalSharesUnlocked;
        self.unstETHTotals.finalizedETH = self.unstETHTotals.finalizedETH - totalFinalizedAmountUnlocked;
        self.unstETHTotals.unfinalizedShares =
            self.unstETHTotals.unfinalizedShares - (totalSharesUnlocked - totalFinalizedSharesUnlocked);

        emit UnstETHUnlocked(holder, unstETHIds, totalSharesUnlocked, totalFinalizedAmountUnlocked);
    }

    function accountUnstETHFinalized(
        Context storage self,
        uint256[] memory unstETHIds,
        uint256[] memory claimableAmounts
    ) internal {
        assert(claimableAmounts.length == unstETHIds.length);

        ETHValue totalAmountFinalized;
        SharesValue totalSharesFinalized;

        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            (SharesValue sharesFinalized, ETHValue amountFinalized) =
                _finalizeUnstETHRecord(self, unstETHIds[i], claimableAmounts[i]);
            totalSharesFinalized = totalSharesFinalized + sharesFinalized;
            totalAmountFinalized = totalAmountFinalized + amountFinalized;
        }

        self.unstETHTotals.finalizedETH = self.unstETHTotals.finalizedETH + totalAmountFinalized;
        self.unstETHTotals.unfinalizedShares = self.unstETHTotals.unfinalizedShares - totalSharesFinalized;
        emit UnstETHFinalized(unstETHIds, totalSharesFinalized, totalAmountFinalized);
    }

    function accountUnstETHClaimed(
        Context storage self,
        uint256[] memory unstETHIds,
        uint256[] memory claimableAmounts
    ) internal returns (ETHValue totalAmountClaimed) {
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            ETHValue claimableAmount = ETHValues.from(claimableAmounts[i]);
            totalAmountClaimed = totalAmountClaimed + claimableAmount;
            _claimUnstETHRecord(self, unstETHIds[i], claimableAmount);
        }
        emit UnstETHClaimed(unstETHIds, totalAmountClaimed);
    }

    function accountUnstETHWithdraw(
        Context storage self,
        address holder,
        uint256[] memory unstETHIds
    ) internal returns (ETHValue amountWithdrawn) {
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            amountWithdrawn = amountWithdrawn + _withdrawUnstETHRecord(self, holder, unstETHIds[i]);
        }
        emit UnstETHWithdrawn(unstETHIds, amountWithdrawn);
    }

    // ---
    // Getters
    // ---

    function getLockedAssetsTotals(Context storage self)
        internal
        view
        returns (SharesValue unfinalizedShares, ETHValue finalizedETH)
    {
        finalizedETH = self.unstETHTotals.finalizedETH;
        unfinalizedShares = self.stETHTotals.lockedShares + self.unstETHTotals.unfinalizedShares;
    }

    function checkMinAssetsLockDurationPassed(
        Context storage self,
        address holder,
        Duration minAssetsLockDuration
    ) internal view {
        Timestamp assetsUnlockAllowedAfter = minAssetsLockDuration.addTo(self.assets[holder].lastAssetsLockTimestamp);
        if (Timestamps.now() <= assetsUnlockAllowedAfter) {
            revert MinAssetsLockDurationNotPassed(assetsUnlockAllowedAfter);
        }
    }

    // ---
    // Helper methods
    // ---

    function _addUnstETHRecord(
        Context storage self,
        address holder,
        uint256 unstETHId,
        WithdrawalRequestStatus memory status
    ) private returns (SharesValue shares) {
        if (status.isFinalized) {
            revert InvalidUnstETHStatus(unstETHId, UnstETHRecordStatus.Finalized);
        }
        // must never be true, for unfinalized requests
        assert(!status.isClaimed);

        if (self.unstETHRecords[unstETHId].status != UnstETHRecordStatus.NotLocked) {
            revert InvalidUnstETHStatus(unstETHId, self.unstETHRecords[unstETHId].status);
        }

        HolderAssets storage assets = self.assets[holder];
        assets.unstETHIds.push(unstETHId);

        shares = SharesValues.from(status.amountOfShares);
        self.unstETHRecords[unstETHId] = UnstETHRecord({
            lockedBy: holder,
            status: UnstETHRecordStatus.Locked,
            index: IndicesOneBased.fromOneBasedValue(assets.unstETHIds.length),
            shares: shares,
            claimableAmount: ETHValues.ZERO
        });
    }

    function _removeUnstETHRecord(
        Context storage self,
        address holder,
        uint256 unstETHId
    ) private returns (SharesValue sharesUnlocked, ETHValue finalizedAmountUnlocked) {
        UnstETHRecord storage unstETHRecord = self.unstETHRecords[unstETHId];

        if (unstETHRecord.lockedBy != holder) {
            revert InvalidUnstETHHolder(unstETHId, holder, unstETHRecord.lockedBy);
        }

        if (unstETHRecord.status == UnstETHRecordStatus.NotLocked) {
            revert InvalidUnstETHStatus(unstETHId, UnstETHRecordStatus.NotLocked);
        }

        sharesUnlocked = unstETHRecord.shares;
        if (unstETHRecord.status == UnstETHRecordStatus.Finalized) {
            finalizedAmountUnlocked = unstETHRecord.claimableAmount;
        }

        HolderAssets storage assets = self.assets[holder];
        IndexOneBased unstETHIdIndex = unstETHRecord.index;
        IndexOneBased lastUnstETHIdIndex = IndicesOneBased.fromOneBasedValue(assets.unstETHIds.length);

        if (lastUnstETHIdIndex != unstETHIdIndex) {
            uint256 lastUnstETHId = assets.unstETHIds[lastUnstETHIdIndex.toZeroBasedValue()];
            assets.unstETHIds[unstETHIdIndex.toZeroBasedValue()] = lastUnstETHId;
            self.unstETHRecords[lastUnstETHId].index = unstETHIdIndex;
        }
        assets.unstETHIds.pop();
        delete self.unstETHRecords[unstETHId];
    }

    function _finalizeUnstETHRecord(
        Context storage self,
        uint256 unstETHId,
        uint256 claimableAmount
    ) private returns (SharesValue sharesFinalized, ETHValue amountFinalized) {
        UnstETHRecord storage unstETHRecord = self.unstETHRecords[unstETHId];
        if (claimableAmount == 0 || unstETHRecord.status != UnstETHRecordStatus.Locked) {
            return (sharesFinalized, amountFinalized);
        }
        sharesFinalized = unstETHRecord.shares;
        amountFinalized = ETHValues.from(claimableAmount);

        unstETHRecord.status = UnstETHRecordStatus.Finalized;
        unstETHRecord.claimableAmount = amountFinalized;

        self.unstETHRecords[unstETHId] = unstETHRecord;
    }

    function _claimUnstETHRecord(Context storage self, uint256 unstETHId, ETHValue claimableAmount) private {
        UnstETHRecord storage unstETHRecord = self.unstETHRecords[unstETHId];
        if (unstETHRecord.status != UnstETHRecordStatus.Locked && unstETHRecord.status != UnstETHRecordStatus.Finalized)
        {
            revert InvalidUnstETHStatus(unstETHId, unstETHRecord.status);
        }
        if (unstETHRecord.status == UnstETHRecordStatus.Finalized) {
            // if the unstETH was marked finalized earlier, it's claimable amount must stay the same
            if (unstETHRecord.claimableAmount != claimableAmount) {
                revert InvalidClaimableAmount(unstETHId, claimableAmount, unstETHRecord.claimableAmount);
            }
        } else {
            unstETHRecord.claimableAmount = claimableAmount;
        }
        unstETHRecord.status = UnstETHRecordStatus.Claimed;
        self.unstETHRecords[unstETHId] = unstETHRecord;
    }

    function _withdrawUnstETHRecord(
        Context storage self,
        address holder,
        uint256 unstETHId
    ) private returns (ETHValue amountWithdrawn) {
        UnstETHRecord storage unstETHRecord = self.unstETHRecords[unstETHId];

        if (unstETHRecord.status != UnstETHRecordStatus.Claimed) {
            revert InvalidUnstETHStatus(unstETHId, unstETHRecord.status);
        }
        if (unstETHRecord.lockedBy != holder) {
            revert InvalidUnstETHHolder(unstETHId, holder, unstETHRecord.lockedBy);
        }
        unstETHRecord.status = UnstETHRecordStatus.Withdrawn;
        amountWithdrawn = unstETHRecord.claimableAmount;
    }

    function _checkNonZeroShares(SharesValue shares) private pure {
        if (shares == SharesValues.ZERO) {
            revert InvalidSharesValue(SharesValues.ZERO);
        }
    }
}
