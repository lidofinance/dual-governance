// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {WithdrawalRequestStatus} from "../interfaces/IWithdrawalQueue.sol";

import {TimeUtils} from "../utils/time.sol";
import {ArrayUtils} from "../utils/arrays.sol";

enum WithdrawalRequestState {
    NotLocked,
    Locked,
    Finalized,
    Claimed,
    Withdrawn
}

struct WithdrawalRequest {
    address owner;
    uint96 claimableAmount;
    WithdrawalRequestState state;
    uint64 vetoerUnstETHIndexOneBased;
    uint128 shares;
}

struct LockedAssetsStats {
    uint128 stETHShares;
    uint128 wstETHShares;
    uint128 unstETHShares;
    uint128 sharesFinalized;
    uint128 amountFinalized;
    uint40 lastAssetsLockTimestamp;
}

struct LockedAssetsTotals {
    uint128 shares;
    uint128 sharesFinalized;
    uint128 amountFinalized;
    uint128 amountClaimed;
}

library AssetsAccounting {
    using SafeCast for uint256;

    event StETHLocked(address indexed vetoer, uint256 shares);
    event StETHUnlocked(address indexed vetoer, uint256 shares);
    event StETHWithdrawn(address indexed vetoer, uint256 stETHShares, uint256 ethAmount);

    event WstETHLocked(address indexed vetoer, uint256 shares);
    event WstETHUnlocked(address indexed vetoer, uint256 shares);
    event WstETHWithdrawn(address indexed vetoer, uint256 wstETHShares, uint256 ethAmount);

    event UnstETHLocked(address indexed vetoer, uint256[] ids, uint256 shares);
    event UnstETHUnlocked(
        address indexed vetoer,
        uint256[] ids,
        uint256 sharesDecrement,
        uint256 finalizedSharesDecrement,
        uint256 finalizedAmountDecrement
    );
    event UnstETHFinalized(uint256[] ids, uint256 finalizedSharesIncrement, uint256 finalizedAmountIncrement);
    event UnstETHClaimed(uint256[] ids, uint256 ethAmount);

    event WithdrawalBatchCreated(uint256[] ids);
    event WithdrawalBatchesClaimed(uint256 offset, uint256 count);
    event WithdrawalRequestWithdrawn(uint256 indexed id, uint256 ethAmount);

    error NoBatchesToClaim();
    error EmptyWithdrawalBatch();
    error WithdrawalBatchesFormed();
    error NotWithdrawalRequestOwner(uint256 id, address actual, address expected);
    error InvalidSharesLock(address vetoer, uint256 shares);
    error InvalidSharesUnlock(address vetoer, uint256 shares);
    error InvalidSharesWithdraw(address vetoer, uint256 shares);
    error WithdrawalRequestFinalized(uint256 id);
    error ClaimableAmountChanged(uint256 id, uint256 actual, uint256 expected);
    error WithdrawalRequestNotClaimable(uint256 id, WithdrawalRequestState state);
    error WithdrawalRequestWasNotLocked(uint256 id);
    error WithdrawalRequestAlreadyLocked(uint256 id);
    error InvalidUnstETHOwner(address actual, address expected);
    error InvalidWithdrawlRequestState(uint256 id, WithdrawalRequestState actual, WithdrawalRequestState expected);
    error InvalidWithdrawalBatchesOffset(uint256 actual, uint256 expected);
    error InvalidWithdrawalBatchesCount(uint256 actual, uint256 expected);
    error AssetsUnlockDelayNotPassed(uint256 unlockTimelockExpiresAt);

    struct State {
        LockedAssetsTotals totals;
        mapping(address vetoer => LockedAssetsStats) assets;
        mapping(uint256 unstETHId => WithdrawalRequest) requests;
        mapping(address vetoer => uint256[] unstETHIds) vetoersUnstETHIds;
        uint256[] withdrawalBatchIds;
        uint256 claimedBatchesCount;
        bool isAllWithdrawalBatchesFormed;
    }

    // ---
    // stETH Operations Accounting
    // ---

    function accountStETHLock(State storage self, address vetoer, uint256 shares) internal {
        _checkNonZeroSharesLock(vetoer, shares);
        uint128 sharesUint128 = shares.toUint128();
        self.assets[vetoer].stETHShares += sharesUint128;
        self.assets[vetoer].lastAssetsLockTimestamp = TimeUtils.timestamp();
        self.totals.shares += sharesUint128;
        emit StETHLocked(vetoer, shares);
    }

    function accountStETHUnlock(
        State storage self,
        uint256 assetsUnlockDelay,
        address vetoer
    ) internal returns (uint128 sharesUnlocked) {
        sharesUnlocked = self.assets[vetoer].stETHShares;
        _checkNonZeroSharesUnlock(vetoer, sharesUnlocked);
        _checkAssetsUnlockDelayPassed(self, assetsUnlockDelay, vetoer);
        self.assets[vetoer].stETHShares = 0;
        self.totals.shares -= sharesUnlocked;
        emit StETHUnlocked(vetoer, sharesUnlocked);
    }

    function accountStETHWithdraw(State storage self, address vetoer) internal returns (uint256 ethAmount) {
        uint256 stETHShares = self.assets[vetoer].stETHShares;
        _checkNonZeroSharesWithdraw(vetoer, stETHShares);
        self.assets[vetoer].stETHShares = 0;
        ethAmount = self.totals.amountClaimed * stETHShares / self.totals.shares;
        emit StETHWithdrawn(vetoer, stETHShares, ethAmount);
    }

    // ---
    // wstETH Operations Accounting
    // ---

    function accountWstETHLock(State storage self, address vetoer, uint256 shares) internal {
        _checkNonZeroSharesLock(vetoer, shares);
        uint128 sharesUint128 = shares.toUint128();
        self.assets[vetoer].wstETHShares += sharesUint128;
        self.assets[vetoer].lastAssetsLockTimestamp = TimeUtils.timestamp();
        self.totals.shares += sharesUint128;
        emit WstETHLocked(vetoer, shares);
    }

    function accountWstETHUnlock(
        State storage self,
        uint256 assetsUnlockDelay,
        address vetoer
    ) internal returns (uint128 sharesUnlocked) {
        sharesUnlocked = self.assets[vetoer].wstETHShares;
        _checkNonZeroSharesUnlock(vetoer, sharesUnlocked);
        _checkAssetsUnlockDelayPassed(self, assetsUnlockDelay, vetoer);
        self.totals.shares -= sharesUnlocked;
        self.assets[vetoer].wstETHShares = 0;
        emit WstETHUnlocked(vetoer, sharesUnlocked);
    }

    function accountWstETHWithdraw(State storage self, address vetoer) internal returns (uint256 ethAmount) {
        uint256 wstETHShares = self.assets[vetoer].wstETHShares;
        _checkNonZeroSharesWithdraw(vetoer, wstETHShares);
        self.assets[vetoer].wstETHShares = 0;
        ethAmount = self.totals.amountClaimed * wstETHShares / self.totals.shares;
        emit WstETHWithdrawn(vetoer, wstETHShares, ethAmount);
    }

    // ---
    // unstETH Operations Accounting
    // ---

    function accountUnstETHLock(
        State storage self,
        address vetoer,
        uint256[] memory unstETHIds,
        WithdrawalRequestStatus[] memory statuses
    ) internal {
        assert(unstETHIds.length == statuses.length);

        uint256 unstETHId;
        uint256 amountOfShares;
        uint256 totalUnstETHSharesLocked;
        WithdrawalRequest storage request;
        uint256 unstETHcount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHcount; ++i) {
            unstETHId = unstETHIds[i];
            request = self.requests[unstETHId];

            _checkWithdrawalRequestNotLocked(self, unstETHId);
            _checkWithdrawalRequestStatusNotFinalized(statuses[i], unstETHId);

            self.vetoersUnstETHIds[vetoer].push(unstETHId);

            request.owner = vetoer;
            request.state = WithdrawalRequestState.Locked;
            request.vetoerUnstETHIndexOneBased = self.vetoersUnstETHIds[vetoer].length.toUint64();
            amountOfShares = statuses[i].amountOfShares;
            request.shares = amountOfShares.toUint128();
            assert(request.claimableAmount == 0);

            totalUnstETHSharesLocked += amountOfShares;
        }
        uint128 totalUnstETHSharesLockedUint128 = totalUnstETHSharesLocked.toUint128();
        self.assets[vetoer].unstETHShares += totalUnstETHSharesLockedUint128;
        self.assets[vetoer].lastAssetsLockTimestamp = TimeUtils.timestamp();
        self.totals.shares += totalUnstETHSharesLockedUint128;
        emit UnstETHLocked(vetoer, unstETHIds, totalUnstETHSharesLocked);
    }

    function accountUnstETHUnlock(
        State storage self,
        uint256 assetsUnlockDelay,
        address vetoer,
        uint256[] memory unstETHIds
    ) internal {
        _checkAssetsUnlockDelayPassed(self, assetsUnlockDelay, vetoer);

        uint256 totalUnstETHSharesToUnlock;
        uint256 totalFinalizedSharesToUnlock;
        uint256 totalFinalizedAmountToUnlock;
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            uint256 unstETHId = unstETHIds[i];
            WithdrawalRequest storage request = self.requests[unstETHId];

            _checkWithdrawalRequestOwner(request, vetoer);
            _checkWithdrawalRequestWasLocked(request, unstETHId);

            uint256 sharesToUnlock = request.shares;
            if (request.state == WithdrawalRequestState.Finalized) {
                totalFinalizedSharesToUnlock += sharesToUnlock;
                totalFinalizedAmountToUnlock += request.claimableAmount;
            }

            uint256[] storage vetoerUnstETHIds = self.vetoersUnstETHIds[vetoer];
            uint256 unstETHIdIndex = request.vetoerUnstETHIndexOneBased - 1;
            uint256 lastUnstETHIdIndex = vetoerUnstETHIds.length - 1;
            if (lastUnstETHIdIndex != unstETHIdIndex) {
                uint256 lastUnstETHId = vetoerUnstETHIds[lastUnstETHIdIndex];
                vetoerUnstETHIds[unstETHIdIndex] = lastUnstETHId;
                self.requests[lastUnstETHId].vetoerUnstETHIndexOneBased = (unstETHIdIndex + 1).toUint64();
            }
            vetoerUnstETHIds.pop();
            delete self.requests[unstETHId];
            totalUnstETHSharesToUnlock += sharesToUnlock;
        }

        self.assets[vetoer].unstETHShares -= totalUnstETHSharesToUnlock.toUint128();
        self.assets[vetoer].sharesFinalized -= totalFinalizedSharesToUnlock.toUint128();
        self.assets[vetoer].amountFinalized -= totalFinalizedAmountToUnlock.toUint128();

        self.totals.shares -= totalUnstETHSharesToUnlock.toUint128();
        self.totals.amountFinalized -= totalFinalizedSharesToUnlock.toUint128();
        self.totals.sharesFinalized -= totalFinalizedAmountToUnlock.toUint128();
        emit UnstETHUnlocked(
            vetoer, unstETHIds, totalUnstETHSharesToUnlock, totalFinalizedSharesToUnlock, totalFinalizedAmountToUnlock
        );
    }

    function accountUnstETHFinalized(
        State storage self,
        uint256[] memory unstETHIds,
        uint256[] memory claimableAmounts
    ) internal {
        uint256 claimableAmount;
        uint256 totalSharesFinalized;
        uint256 totalAmountFinalized;
        WithdrawalRequest storage request;

        assert(claimableAmounts.length == unstETHIds.length);

        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            request = self.requests[unstETHIds[i]];
            claimableAmount = claimableAmounts[i];
            if (claimableAmount == 0 || request.state != WithdrawalRequestState.Locked) {
                continue;
            }
            request.state = WithdrawalRequestState.Finalized;
            request.claimableAmount = claimableAmount.toUint96();
            totalSharesFinalized += request.shares;
            totalAmountFinalized += claimableAmount;
        }
        uint128 totalSharesFinalizedUint128 = totalSharesFinalized.toUint128();
        uint128 totalAmountFinalizedUint128 = totalAmountFinalized.toUint128();

        self.totals.sharesFinalized += totalSharesFinalizedUint128;
        self.totals.amountFinalized += totalAmountFinalizedUint128;
        emit UnstETHFinalized(unstETHIds, totalSharesFinalized, totalAmountFinalized);
    }

    function accountUnstETHClaimed(
        State storage self,
        uint256[] memory unstETHIds,
        uint256[] memory claimableAmounts
    ) internal returns (uint256 totalAmountClaimed) {
        uint256 unstETHId;
        uint256 claimableAmount;
        WithdrawalRequest storage request;
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            unstETHId = unstETHIds[i];
            claimableAmount = claimableAmounts[i];
            request = self.requests[unstETHId];

            if (request.state != WithdrawalRequestState.Locked && request.state != WithdrawalRequestState.Finalized) {
                revert WithdrawalRequestNotClaimable(unstETHId, request.state);
            }
            if (request.state == WithdrawalRequestState.Finalized && request.claimableAmount != claimableAmount) {
                revert ClaimableAmountChanged(unstETHId, claimableAmount, request.claimableAmount);
            } else {
                request.claimableAmount = claimableAmount.toUint96();
            }
            request.state = WithdrawalRequestState.Claimed;
            totalAmountClaimed += claimableAmount;
        }
        self.totals.amountClaimed += totalAmountClaimed.toUint128();
        emit UnstETHClaimed(unstETHIds, totalAmountClaimed);
    }

    function accountUnstETHWithdraw(
        State storage self,
        address vetoer,
        uint256[] calldata unstETHIds
    ) internal returns (uint256 ethAmount) {
        uint256 unstETHId;
        WithdrawalRequest storage request;
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            unstETHId = unstETHIds[i];
            request = self.requests[unstETHId];

            if (request.owner != vetoer) {
                revert NotWithdrawalRequestOwner(unstETHId, vetoer, request.owner);
            }
            if (request.state != WithdrawalRequestState.Claimed) {
                revert InvalidWithdrawlRequestState(unstETHId, request.state, WithdrawalRequestState.Claimed);
            }
            request.state = WithdrawalRequestState.Withdrawn;
            ethAmount += request.claimableAmount;
            emit WithdrawalRequestWithdrawn(unstETHId, ethAmount);
        }
    }

    // ---
    // Withdraw Batches
    // ---

    function formWithdrawalBatch(
        State storage self,
        uint256 minRequestAmount,
        uint256 maxRequestAmount,
        uint256 stETHBalance,
        uint256 requestAmountsCountLimit
    ) internal returns (uint256[] memory requestAmounts) {
        if (self.isAllWithdrawalBatchesFormed) {
            revert WithdrawalBatchesFormed();
        }
        if (requestAmountsCountLimit == 0) {
            revert EmptyWithdrawalBatch();
        }

        uint256 maxAmount = maxRequestAmount * requestAmountsCountLimit;
        if (stETHBalance >= maxAmount) {
            return ArrayUtils.seed(requestAmountsCountLimit, maxRequestAmount);
        }

        self.isAllWithdrawalBatchesFormed = true;

        uint256 requestsCount = stETHBalance / maxRequestAmount;
        uint256 lastRequestAmount = stETHBalance % maxRequestAmount;

        if (lastRequestAmount < minRequestAmount) {
            return ArrayUtils.seed(requestsCount, maxRequestAmount);
        }

        requestAmounts = ArrayUtils.seed(requestsCount + 1, maxRequestAmount);
        requestAmounts[requestsCount] = lastRequestAmount;
    }

    function accountWithdrawalBatch(State storage self, uint256[] memory unstETHIds) internal {
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            self.withdrawalBatchIds.push(unstETHIds[i]);
        }
        emit WithdrawalBatchCreated(unstETHIds);
    }

    function accountWithdrawalBatchClaimed(
        State storage self,
        uint256 offset,
        uint256 count
    ) internal returns (uint256[] memory unstETHIds) {
        if (count == 0) {
            return unstETHIds;
        }
        uint256 batchesCount = self.withdrawalBatchIds.length;
        uint256 claimedBatchesCount = self.claimedBatchesCount;
        if (claimedBatchesCount == batchesCount) {
            revert NoBatchesToClaim();
        }
        if (claimedBatchesCount != offset) {
            revert InvalidWithdrawalBatchesOffset(offset, claimedBatchesCount);
        }
        if (count > batchesCount - claimedBatchesCount) {
            revert InvalidWithdrawalBatchesCount(count, batchesCount - claimedBatchesCount);
        }

        unstETHIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            unstETHIds[i] = self.withdrawalBatchIds[claimedBatchesCount + i];
        }
        self.claimedBatchesCount += count;
        emit WithdrawalBatchesClaimed(offset, count);
    }

    function accountClaimedETH(State storage self, uint256 amount) internal {
        self.totals.amountClaimed += amount.toUint128();
    }

    // ---
    // Getters
    // ---

    function getLocked(State storage self) internal view returns (uint256 rebaseableShares, uint256 finalizedAmount) {
        rebaseableShares = self.totals.shares - self.totals.sharesFinalized;
        finalizedAmount = self.totals.amountFinalized;
    }

    function getIsWithdrawalsClaimed(State storage self) internal view returns (bool) {
        return self.claimedBatchesCount == self.withdrawalBatchIds.length;
    }

    function _checkWithdrawalRequestStatusOwner(WithdrawalRequestStatus memory status, address account) private pure {
        if (status.owner != account) {
            revert InvalidUnstETHOwner(account, status.owner);
        }
    }

    // ---
    // Private Methods
    // ---

    function _checkWithdrawalRequestOwner(WithdrawalRequest storage request, address account) private view {
        if (request.owner != account) {
            revert InvalidUnstETHOwner(account, request.owner);
        }
    }

    function _checkWithdrawalRequestStatusNotFinalized(
        WithdrawalRequestStatus memory status,
        uint256 id
    ) private pure {
        if (status.isFinalized) {
            revert WithdrawalRequestFinalized(id);
        }
        // it can't be claimed without finalization
        assert(!status.isClaimed);
    }

    function _checkWithdrawalRequestNotLocked(State storage self, uint256 unstETHId) private view {
        if (self.requests[unstETHId].vetoerUnstETHIndexOneBased != 0) {
            revert WithdrawalRequestAlreadyLocked(unstETHId);
        }
    }

    function _checkWithdrawalRequestWasLocked(WithdrawalRequest storage request, uint256 id) private view {
        if (request.vetoerUnstETHIndexOneBased == 0) {
            revert WithdrawalRequestWasNotLocked(id);
        }
    }

    function _checkNonZeroSharesLock(address vetoer, uint256 shares) private pure {
        if (shares == 0) {
            revert InvalidSharesLock(vetoer, 0);
        }
    }

    function _checkNonZeroSharesUnlock(address vetoer, uint256 shares) private pure {
        if (shares == 0) {
            revert InvalidSharesUnlock(vetoer, 0);
        }
    }

    function _checkNonZeroSharesWithdraw(address vetoer, uint256 shares) private pure {
        if (shares == 0) {
            revert InvalidSharesWithdraw(vetoer, 0);
        }
    }

    function _checkAssetsUnlockDelayPassed(
        State storage self,
        uint256 assetsUnlockDelay,
        address vetoer
    ) private view {
        if (block.timestamp <= self.assets[vetoer].lastAssetsLockTimestamp + assetsUnlockDelay) {
            revert AssetsUnlockDelayNotPassed(self.assets[vetoer].lastAssetsLockTimestamp + assetsUnlockDelay);
        }
    }
}