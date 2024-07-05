// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ETHValue, ETHValues} from "../types/ETHValue.sol";
import {SharesValue, SharesValues} from "../types/SharesValue.sol";
import {IndexOneBased, IndicesOneBased} from "../types/IndexOneBased.sol";

import {WithdrawalRequestStatus} from "../interfaces/IWithdrawalQueue.sol";

import {Duration} from "../types/Duration.sol";
import {Timestamps, Timestamp} from "../types/Timestamp.sol";

struct HolderAssets {
    // The total shares amount of stETH/wstETH accounted to the holder
    SharesValue stETHLockedShares;
    // The total shares amount of unstETH NFTs accounted to the holder
    SharesValue unstETHLockedShares;
    // The timestamp when the last time was accounted lock of shares or unstETHs
    Timestamp lastAssetsLockTimestamp;
    // The ids of the unstETH NFTs accounted to the holder
    uint256[] unstETHIds;
}

struct UnstETHAccounting {
    // The cumulative amount of unfinalized unstETH shares locked in the Escrow
    SharesValue unfinalizedShares;
    // The total amount of ETH claimable from the finalized unstETH locked in the Escrow
    ETHValue finalizedETH;
}

struct StETHAccounting {
    // The total amount of shares of locked stETH and wstETH tokens
    SharesValue lockedShares;
    // The total amount of ETH received during the claiming of the locked stETH
    ETHValue claimedETH;
}

enum UnstETHRecordStatus {
    NotLocked,
    Locked,
    Finalized,
    Claimed,
    Withdrawn
}

struct UnstETHRecord {
    // The one based index of the unstETH record in the UnstETHAccounting.unstETHIds list
    IndexOneBased index;
    // The address of the holder who locked unstETH
    address lockedBy;
    // The current status of the unstETH
    UnstETHRecordStatus status;
    // The amount of shares contained in the unstETH
    SharesValue shares;
    // The amount of ETH contained in the unstETH (this value equals to 0 until NFT is mark as finalized or claimed)
    ETHValue claimableAmount;
}

library AssetsAccounting {
    struct State {
        StETHAccounting stETHTotals;
        UnstETHAccounting unstETHTotals;
        mapping(address account => HolderAssets) assets;
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
    error AssetsUnlockDelayNotPassed(Timestamp unlockTimelockExpiresAt);
    error InvalidClaimableAmount(uint256 unstETHId, ETHValue expected, ETHValue actual);

    // ---
    // stETH shares operations accounting
    // ---

    function accountStETHSharesLock(State storage self, address holder, SharesValue shares) internal {
        _checkNonZeroShares(shares);
        self.stETHTotals.lockedShares = self.stETHTotals.lockedShares + shares;
        HolderAssets storage assets = self.assets[holder];
        assets.stETHLockedShares = assets.stETHLockedShares + shares;
        assets.lastAssetsLockTimestamp = Timestamps.now();
        emit StETHSharesLocked(holder, shares);
    }

    function accountStETHSharesUnlock(State storage self, address holder) internal returns (SharesValue shares) {
        shares = self.assets[holder].stETHLockedShares;
        accountStETHSharesUnlock(self, holder, shares);
    }

    function accountStETHSharesUnlock(State storage self, address holder, SharesValue shares) internal {
        _checkNonZeroShares(shares);

        HolderAssets storage assets = self.assets[holder];
        if (assets.stETHLockedShares < shares) {
            revert InvalidSharesValue(shares);
        }

        self.stETHTotals.lockedShares = self.stETHTotals.lockedShares - shares;
        assets.stETHLockedShares = assets.stETHLockedShares - shares;
        emit StETHSharesUnlocked(holder, shares);
    }

    function accountStETHSharesWithdraw(State storage self, address holder) internal returns (ETHValue ethWithdrawn) {
        HolderAssets storage assets = self.assets[holder];
        SharesValue stETHSharesToWithdraw = assets.stETHLockedShares;

        _checkNonZeroShares(stETHSharesToWithdraw);

        assets.stETHLockedShares = SharesValues.ZERO;
        ethWithdrawn =
            SharesValues.calcETHValue(self.stETHTotals.claimedETH, stETHSharesToWithdraw, self.stETHTotals.lockedShares);

        emit ETHWithdrawn(holder, stETHSharesToWithdraw, ethWithdrawn);
    }

    function accountClaimedStETH(State storage self, ETHValue amount) internal {
        self.stETHTotals.claimedETH = self.stETHTotals.claimedETH + amount;
        emit ETHClaimed(amount);
    }

    // ---
    // unstETH operations accounting
    // ---

    function accountUnstETHLock(
        State storage self,
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

    function accountUnstETHUnlock(State storage self, address holder, uint256[] memory unstETHIds) internal {
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

    function accountUnstETHFinalized(
        State storage self,
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
        State storage self,
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
        State storage self,
        address holder,
        uint256[] calldata unstETHIds
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

    function getLockedAssetsTotals(State storage self)
        internal
        view
        returns (SharesValue ufinalizedShares, ETHValue finalizedETH)
    {
        finalizedETH = self.unstETHTotals.finalizedETH;
        ufinalizedShares = self.stETHTotals.lockedShares + self.unstETHTotals.unfinalizedShares;
    }

    function checkAssetsUnlockDelayPassed(
        State storage self,
        address holder,
        Duration assetsUnlockDelay
    ) internal view {
        Timestamp assetsUnlockAllowedAfter = assetsUnlockDelay.addTo(self.assets[holder].lastAssetsLockTimestamp);
        if (Timestamps.now() <= assetsUnlockAllowedAfter) {
            revert AssetsUnlockDelayNotPassed(assetsUnlockAllowedAfter);
        }
    }

    // ---
    // Helper methods
    // ---

    function _addUnstETHRecord(
        State storage self,
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
            index: IndicesOneBased.from(assets.unstETHIds.length),
            shares: shares,
            claimableAmount: ETHValues.ZERO
        });
    }

    function _removeUnstETHRecord(
        State storage self,
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
        IndexOneBased lastUnstETHIdIndex = IndicesOneBased.from(assets.unstETHIds.length);

        if (lastUnstETHIdIndex != unstETHIdIndex) {
            uint256 lastUnstETHId = assets.unstETHIds[lastUnstETHIdIndex.value()];
            assets.unstETHIds[unstETHIdIndex.value()] = lastUnstETHId;
            self.unstETHRecords[lastUnstETHId].index = unstETHIdIndex;
        }
        assets.unstETHIds.pop();
        delete self.unstETHRecords[unstETHId];
    }

    function _finalizeUnstETHRecord(
        State storage self,
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

    function _claimUnstETHRecord(State storage self, uint256 unstETHId, ETHValue claimableAmount) private {
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
        State storage self,
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
