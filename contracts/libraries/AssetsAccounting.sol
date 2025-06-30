// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {ETHValue, ETHValues} from "../types/ETHValue.sol";
import {Timestamps, Timestamp} from "../types/Timestamp.sol";
import {SharesValue, SharesValues} from "../types/SharesValue.sol";
import {IndexOneBased, IndicesOneBased} from "../types/IndexOneBased.sol";

import {IWithdrawalQueue} from "../interfaces/IWithdrawalQueue.sol";
import {ISignallingEscrow} from "../interfaces/ISignallingEscrow.sol";

/// @notice Tracks the stETH and unstETH tokens associated with users.
/// @param stETHLockedShares Total number of stETH shares held by the user.
/// @param unstETHLockedShares Total number of shares contained in the unstETH NFTs held by the user.
/// @param lastAssetsLockTimestamp Timestamp of the most recent lock of stETH shares or unstETH NFTs.
/// @param unstETHIds List of unstETH ids locked by the user.
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
    /// @dev slot0: [128..255]
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

/// @notice Represents the state of an accounted unstETH NFT.
/// @param NotLocked Indicates the default value of the unstETH record, meaning it was not accounted as locked or
///     was unlocked by the account that previously locked it.
/// @param Locked Indicates the unstETH record was accounted as locked.
/// @param Finalized Indicates the unstETH record was marked as finalized.
/// @param Claimed Indicates the unstETH record was claimed.
/// @param Withdrawn Indicates the unstETH record was withdrawn after a successful claim.
enum UnstETHRecordStatus {
    NotLocked,
    Locked,
    Finalized,
    Claimed,
    Withdrawn
}

/// @notice Stores information about an accounted unstETH NFT.
/// @param status The current status of the unstETH NFT. Refer to `UnstETHRecordStatus` for details.
/// @param index The one-based index of the unstETH NFT in the `HolderAssets.unstETHIds` array.
/// @param lockedBy The address of the account that locked the unstETH.
/// @param shares The number of shares contained in the unstETH.
/// @param claimableAmount The amount of claimable ETH contained in the unstETH. This value is 0
///     until the NFT is marked as finalized or claimed.
struct UnstETHRecord {
    /// @dev slot0: [0..7]
    UnstETHRecordStatus status;
    /// @dev slot0: [8..39]
    IndexOneBased index;
    /// @dev slot0: [40..199]
    address lockedBy;
    /// @dev slot1: [0..127]
    SharesValue shares;
    /// @dev slot1: [128..255]
    ETHValue claimableAmount;
}

/// @title Assets Accounting Library
/// @notice Provides accounting functionality for tracking users' stETH and unstETH tokens locked
///     in the Escrow contract.
library AssetsAccounting {
    // ---
    // Data Types
    // ---

    /// @notice The context of the Assets Accounting library.
    /// @param stETHTotals Tracks the total number of stETH shares and claimed ETH locked by users.
    /// @param unstETHTotals Tracks the total number of unstETH shares and finalized ETH locked by users.
    /// @param assets Mapping to store information about the assets locked by each user.
    /// @param unstETHRecords Mapping to track the state of the locked unstETH ids.
    struct Context {
        /// @dev slot0: [0..255]
        StETHAccounting stETHTotals;
        /// @dev slot1: [0..255]
        UnstETHAccounting unstETHTotals;
        /// @dev slot2: [0..255] empty slot for mapping tracking in the storage
        mapping(address account => HolderAssets) assets;
        /// @dev slot3: [0..255] empty slot for mapping tracking in the storage
        mapping(uint256 unstETHId => UnstETHRecord) unstETHRecords;
    }

    // ---
    // Events
    // ---

    event ETHWithdrawn(address indexed holder, SharesValue shares, ETHValue value);
    event StETHSharesLocked(address indexed holder, SharesValue shares);
    event StETHSharesUnlocked(address indexed holder, SharesValue shares);
    event UnstETHFinalized(uint256[] ids, SharesValue[] finalizedShares, ETHValue[] finalizedAmount);
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
    error InvalidUnstETHHolder(uint256 unstETHId, address holder);
    error MinAssetsLockDurationNotPassed(Timestamp lockDurationExpiresAt);
    error InvalidClaimableAmount(uint256 unstETHId, ETHValue claimableAmount);

    // ---
    // stETH Operations Accounting
    // ---

    /// @notice Records the locking of stETH shares on behalf of the holder, increasing both the total number of
    ///     locked stETH shares and the number of shares locked by the holder.
    /// @param self The context of the Assets Accounting library.
    /// @param holder The address of the account holding the locked shares.
    /// @param shares The number of stETH shares to be locked.
    function accountStETHSharesLock(Context storage self, address holder, SharesValue shares) internal {
        _checkNonZeroShares(shares);
        self.stETHTotals.lockedShares = self.stETHTotals.lockedShares + shares;
        HolderAssets storage assets = self.assets[holder];
        assets.stETHLockedShares = assets.stETHLockedShares + shares;
        assets.lastAssetsLockTimestamp = Timestamps.now();
        emit StETHSharesLocked(holder, shares);
    }

    /// @notice Tracks the unlocking of all stETH shares for a holder, updating both the total locked stETH shares
    ///     and the holder's balance of locked shares.
    /// @param self The context of the Assets Accounting library.
    /// @param holder The address of the holder whose locked shares are being tracked as unlocked.
    /// @return shares The number of stETH shares that have been tracked as unlocked.
    function accountStETHSharesUnlock(Context storage self, address holder) internal returns (SharesValue shares) {
        shares = self.assets[holder].stETHLockedShares;
        accountStETHSharesUnlock(self, holder, shares);
    }

    /// @notice Records the unlocking of the specified number of stETH shares on behalf of the holder, reducing both the
    ///     total number of locked stETH shares and the number of shares locked by the holder.
    /// @param self The context of the Assets Accounting library.
    /// @param holder The address of the account holding the shares to be unlocked.
    /// @param shares The number of stETH shares to be unlocked.
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

    /// @notice Records the withdrawal of all stETH shares locked by the holder and calculates the corresponding
    ///     ETH to be withdrawn.
    /// @param self The context of the Assets Accounting library.
    /// @param holder The address of the holder withdrawing stETH shares.
    /// @return ethWithdrawn The amount of ETH corresponding to the withdrawn stETH shares.
    function accountStETHSharesWithdraw(
        Context storage self,
        address holder
    ) internal returns (ETHValue ethWithdrawn) {
        HolderAssets storage assets = self.assets[holder];
        SharesValue stETHSharesToWithdraw = assets.stETHLockedShares;

        _checkNonZeroShares(stETHSharesToWithdraw);

        assets.stETHLockedShares = SharesValues.ZERO;
        ethWithdrawn = ETHValues.from(
            self.stETHTotals.claimedETH.toUint256() * stETHSharesToWithdraw.toUint256()
                / self.stETHTotals.lockedShares.toUint256()
        );

        emit ETHWithdrawn(holder, stETHSharesToWithdraw, ethWithdrawn);
    }

    /// @notice Records the specified amount of ETH as claimed, increasing the total claimed ETH amount.
    /// @param self The context of the Assets Accounting library.
    /// @param amount The amount of ETH being claimed.
    function accountClaimedETH(Context storage self, ETHValue amount) internal {
        self.stETHTotals.claimedETH = self.stETHTotals.claimedETH + amount;
        emit ETHClaimed(amount);
    }

    // ---
    // unstETH Operations Accounting
    // ---

    /// @notice Records the locking of unstETH NFTs for the given holder, updating both the total and the holder's
    ///     number of locked unstETH shares.
    /// @param self The context of the Assets Accounting library.
    /// @param holder The address of the account holding the locked unstETH NFTs.
    /// @param unstETHIds An array of unstETH NFT ids to be locked.
    /// @param statuses An array of `WithdrawalRequestStatus` structs containing information about each unstETH NFT,
    ///     returned by the WithdrawalQueue, corresponding to the `unstETHIds`.
    function accountUnstETHLock(
        Context storage self,
        address holder,
        uint256[] memory unstETHIds,
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses
    ) internal {
        assert(unstETHIds.length == statuses.length);

        SharesValue totalUnstETHLocked;
        uint256 unstETHcount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHcount; ++i) {
            totalUnstETHLocked = totalUnstETHLocked + _addUnstETHRecord(self, holder, unstETHIds[i], statuses[i]);
        }

        HolderAssets storage assets = self.assets[holder];

        assets.lastAssetsLockTimestamp = Timestamps.now();
        assets.unstETHLockedShares = assets.unstETHLockedShares + totalUnstETHLocked;
        self.unstETHTotals.unfinalizedShares = self.unstETHTotals.unfinalizedShares + totalUnstETHLocked;

        emit UnstETHLocked(holder, unstETHIds, totalUnstETHLocked);
    }

    /// @notice Records the unlocking of unstETH NFTs for the given holder, updating both the total and the holder's
    ///     number of locked unstETH shares.
    /// @param self The context of the Assets Accounting library.
    /// @param holder The address of the account that previously locked the unstETH NFTs with the given ids.
    /// @param unstETHIds An array of unstETH NFT ids to be unlocked.
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
        self.assets[holder].unstETHLockedShares = self.assets[holder].unstETHLockedShares - totalSharesUnlocked;
        self.unstETHTotals.finalizedETH = self.unstETHTotals.finalizedETH - totalFinalizedAmountUnlocked;
        self.unstETHTotals.unfinalizedShares =
            self.unstETHTotals.unfinalizedShares - (totalSharesUnlocked - totalFinalizedSharesUnlocked);

        emit UnstETHUnlocked(holder, unstETHIds, totalSharesUnlocked, totalFinalizedAmountUnlocked);
    }

    /// @notice Marks the previously locked unstETH NFTs with the given ids as finalized, increasing the total finalized
    ///     ETH amount for unstETHs and decreasing the total number of unfinalized shares.
    /// @dev If the claimable amount for an NFT is zero, or if the NFT has already been marked as finalized or was not
    ///     accounted for as locked, those NFTs will be skipped.
    /// @param self The context of the Assets Accounting library.
    /// @param unstETHIds An array of unstETH NFT ids to be marked as finalized.
    /// @param claimableAmounts An array of claimable ETH amounts for each unstETH NFT.
    function accountUnstETHFinalized(
        Context storage self,
        uint256[] memory unstETHIds,
        uint256[] memory claimableAmounts
    ) internal {
        assert(claimableAmounts.length == unstETHIds.length);

        ETHValue totalAmountFinalized;
        SharesValue totalSharesFinalized;

        uint256 unstETHIdsCount = unstETHIds.length;

        SharesValue[] memory finalizedShares = new SharesValue[](unstETHIdsCount);
        ETHValue[] memory finalizedAmounts = new ETHValue[](unstETHIdsCount);

        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            (finalizedShares[i], finalizedAmounts[i]) = _finalizeUnstETHRecord(self, unstETHIds[i], claimableAmounts[i]);
            totalSharesFinalized = totalSharesFinalized + finalizedShares[i];
            totalAmountFinalized = totalAmountFinalized + finalizedAmounts[i];
        }

        self.unstETHTotals.finalizedETH = self.unstETHTotals.finalizedETH + totalAmountFinalized;
        self.unstETHTotals.unfinalizedShares = self.unstETHTotals.unfinalizedShares - totalSharesFinalized;
        emit UnstETHFinalized(unstETHIds, finalizedShares, finalizedAmounts);
    }

    /// @notice Marks the previously locked unstETH NFTs with the given ids as claimed and sets the corresponding amount
    ///     of claimable ETH for each unstETH NFT.
    /// @param self The context of the Assets Accounting library.
    /// @param unstETHIds An array of unstETH NFT ids to be marked as claimed.
    /// @param claimableAmounts An array of claimable ETH amounts for each unstETH NFT.
    /// @return totalAmountClaimed The total amount of ETH claimed from the unstETH NFTs.
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

    /// @notice Marks the previously locked and claimed unstETH NFTs with the given ids as withdrawn by the holder.
    /// @dev If any of the unstETH NFTs have already been withdrawn or were locked by a different holder, the method will revert.
    /// @param self The context of the Assets Accounting library.
    /// @param holder The address of the account that previously locked the unstETH NFTs with the given ids.
    /// @param unstETHIds An array of unstETH NFT ids for which the ETH is being withdrawn.
    /// @return amountWithdrawn The total amount of ETH withdrawn from the unstETH NFTs.
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

    /// @notice Retrieves details of locked unstETH record for the given id.
    /// @param unstETHId The id for the locked unstETH record to retrieve.
    /// @return unstETHDetails A `LockedUnstETHDetails` struct containing the details for provided unstETH id.
    function getLockedUnstETHDetails(
        Context storage self,
        uint256 unstETHId
    ) internal view returns (ISignallingEscrow.LockedUnstETHDetails memory unstETHDetails) {
        UnstETHRecord memory unstETHRecord = self.unstETHRecords[unstETHId];

        if (unstETHRecord.status == UnstETHRecordStatus.NotLocked) {
            revert InvalidUnstETHStatus(unstETHId, UnstETHRecordStatus.NotLocked);
        }

        unstETHDetails.id = unstETHId;
        unstETHDetails.status = unstETHRecord.status;
        unstETHDetails.lockedBy = unstETHRecord.lockedBy;
        unstETHDetails.shares = unstETHRecord.shares;
        unstETHDetails.claimableAmount = unstETHRecord.claimableAmount;
    }

    // ---
    // Checks
    // ---

    /// @notice Checks whether the minimum required lock duration has passed since the last call to
    ///     `accountStETHSharesLock` or `accountUnstETHLock` for the specified holder.
    /// @dev If the required lock duration has not yet passed, the function reverts with an error.
    /// @param self The context of the Assets Accounting library.
    /// @param holder The address of the account that holds the locked assets.
    /// @param minAssetsLockDuration The minimum duration for which the assets must remain locked before
    ///     unlocking is allowed.
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
    // Helper Methods
    // ---

    function _addUnstETHRecord(
        Context storage self,
        address holder,
        uint256 unstETHId,
        IWithdrawalQueue.WithdrawalRequestStatus memory status
    ) private returns (SharesValue shares) {
        if (status.isFinalized) {
            revert InvalidUnstETHStatus(unstETHId, UnstETHRecordStatus.Finalized);
        }
        // This condition should never be true for unfinalized requests, as they cannot be claimed yet
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
            revert InvalidUnstETHHolder(unstETHId, holder);
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
    }

    function _claimUnstETHRecord(Context storage self, uint256 unstETHId, ETHValue claimableAmount) private {
        UnstETHRecord storage unstETHRecord = self.unstETHRecords[unstETHId];
        if (unstETHRecord.status != UnstETHRecordStatus.Locked && unstETHRecord.status != UnstETHRecordStatus.Finalized)
        {
            revert InvalidUnstETHStatus(unstETHId, unstETHRecord.status);
        }
        if (unstETHRecord.status == UnstETHRecordStatus.Finalized) {
            // If the unstETH was marked as finalized earlier, its claimable amount must remain unchanged.
            if (unstETHRecord.claimableAmount != claimableAmount) {
                revert InvalidClaimableAmount(unstETHId, claimableAmount);
            }
        } else {
            unstETHRecord.claimableAmount = claimableAmount;
        }
        unstETHRecord.status = UnstETHRecordStatus.Claimed;
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
            revert InvalidUnstETHHolder(unstETHId, holder);
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
