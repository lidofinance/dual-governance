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
    uint128 shares;
    uint64 vetoerUnstETHIndexOneBased;
    WithdrawalRequestState state;
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
    event UnstETHWithdrawn(uint256[] ids, uint256 ethAmount);

    event WithdrawalBatchCreated(uint256[] ids);
    event WithdrawalBatchesClaimed(uint256 offset, uint256 count);

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
    error NotEnoughStETHToUnlock(uint256 requested, uint256 sharesBalance);

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

    function accountStETHUnlock(State storage self, address vetoer) internal returns (uint128 sharesUnlocked) {
        sharesUnlocked = accountStETHUnlock(self, vetoer, self.assets[vetoer].stETHShares);
    }

    function accountStETHUnlock(
        State storage self,
        address vetoer,
        uint256 shares
    ) internal returns (uint128 sharesUnlocked) {
        _checkStETHSharesUnlock(self, vetoer, shares);
        sharesUnlocked = shares.toUint128();
        self.totals.shares -= sharesUnlocked;
        self.assets[vetoer].stETHShares -= sharesUnlocked;
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

    function checkAssetsUnlockDelayPassed(State storage self, address vetoer, uint256 delay) internal view {
        _checkAssetsUnlockDelayPassed(self, delay, vetoer);
    }

    function accountWstETHLock(State storage self, address vetoer, uint256 shares) internal {
        _checkNonZeroSharesLock(vetoer, shares);
        uint128 sharesUint128 = shares.toUint128();
        self.assets[vetoer].wstETHShares += sharesUint128;
        self.assets[vetoer].lastAssetsLockTimestamp = TimeUtils.timestamp();
        self.totals.shares += sharesUint128;
        emit WstETHLocked(vetoer, shares);
    }

    function accountWstETHUnlock(State storage self, address vetoer) internal returns (uint128 sharesUnlocked) {
        sharesUnlocked = accountWstETHUnlock(self, vetoer, self.assets[vetoer].wstETHShares);
    }

    function accountWstETHUnlock(
        State storage self,
        address vetoer,
        uint256 shares
    ) internal returns (uint128 sharesUnlocked) {
        _checkNonZeroSharesUnlock(vetoer, shares);
        sharesUnlocked = shares.toUint128();
        self.totals.shares -= sharesUnlocked;
        self.assets[vetoer].wstETHShares -= sharesUnlocked;
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

        uint256 totalUnstETHSharesLocked;
        uint256 unstETHcount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHcount; ++i) {
            totalUnstETHSharesLocked += _addWithdrawalRequest(self, vetoer, unstETHIds[i], statuses[i]);
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

        uint256 totalUnstETHSharesUnlocked;
        uint256 totalFinalizedSharesUnlocked;
        uint256 totalFinalizedAmountUnlocked;

        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            (uint256 sharesUnlocked, uint256 finalizedSharesUnlocked, uint256 finalizedAmountUnlocked) =
                _removeWithdrawalRequest(self, vetoer, unstETHIds[i]);

            totalUnstETHSharesUnlocked += sharesUnlocked;
            totalFinalizedSharesUnlocked += finalizedSharesUnlocked;
            totalFinalizedAmountUnlocked += finalizedAmountUnlocked;
        }

        uint128 totalUnstETHSharesUnlockedUint128 = totalUnstETHSharesUnlocked.toUint128();
        uint128 totalFinalizedSharesUnlockedUint128 = totalFinalizedSharesUnlocked.toUint128();
        uint128 totalFinalizedAmountUnlockedUint128 = totalFinalizedAmountUnlocked.toUint128();

        self.assets[vetoer].unstETHShares -= totalUnstETHSharesUnlockedUint128;
        self.assets[vetoer].sharesFinalized -= totalFinalizedSharesUnlockedUint128;
        self.assets[vetoer].amountFinalized -= totalFinalizedAmountUnlockedUint128;

        self.totals.shares -= totalUnstETHSharesUnlockedUint128;
        self.totals.sharesFinalized -= totalFinalizedSharesUnlockedUint128;
        self.totals.amountFinalized -= totalFinalizedAmountUnlockedUint128;

        emit UnstETHUnlocked(
            vetoer, unstETHIds, totalUnstETHSharesUnlocked, totalFinalizedSharesUnlocked, totalFinalizedAmountUnlocked
        );
    }

    function accountUnstETHFinalized(
        State storage self,
        uint256[] memory unstETHIds,
        uint256[] memory claimableAmounts
    ) internal {
        assert(claimableAmounts.length == unstETHIds.length);

        uint256 totalSharesFinalized;
        uint256 totalAmountFinalized;

        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            (address owner, uint256 sharesFinalized, uint256 amountFinalized) =
                _finalizeWithdrawalRequest(self, unstETHIds[i], claimableAmounts[i]);

            self.assets[owner].sharesFinalized += sharesFinalized.toUint128();
            self.assets[owner].amountFinalized += amountFinalized.toUint128();

            totalSharesFinalized += sharesFinalized;
            totalAmountFinalized += amountFinalized;
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
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            totalAmountClaimed += _claimWithdrawalRequest(self, unstETHIds[i], claimableAmounts[i]);
        }
        self.totals.amountClaimed += totalAmountClaimed.toUint128();
        emit UnstETHClaimed(unstETHIds, totalAmountClaimed);
    }

    function accountUnstETHWithdraw(
        State storage self,
        address vetoer,
        uint256[] calldata unstETHIds
    ) internal returns (uint256 amountWithdrawn) {
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            amountWithdrawn += _withdrawWithdrawalRequest(self, vetoer, unstETHIds[i]);
        }
        emit UnstETHWithdrawn(unstETHIds, amountWithdrawn);
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

    function _addWithdrawalRequest(
        State storage self,
        address vetoer,
        uint256 unstETHId,
        WithdrawalRequestStatus memory status
    ) private returns (uint256 amountOfShares) {
        amountOfShares = status.amountOfShares;
        WithdrawalRequest storage request = self.requests[unstETHId];

        _checkWithdrawalRequestNotLocked(request, unstETHId);
        _checkWithdrawalRequestStatusNotFinalized(status, unstETHId);

        self.vetoersUnstETHIds[vetoer].push(unstETHId);

        request.owner = vetoer;
        request.state = WithdrawalRequestState.Locked;
        request.vetoerUnstETHIndexOneBased = self.vetoersUnstETHIds[vetoer].length.toUint64();
        request.shares = amountOfShares.toUint128();
        assert(request.claimableAmount == 0);
    }

    function _removeWithdrawalRequest(
        State storage self,
        address vetoer,
        uint256 unstETHId
    ) private returns (uint256 sharesUnlocked, uint256 finalizedSharesUnlocked, uint256 finalizedAmountUnlocked) {
        WithdrawalRequest storage request = self.requests[unstETHId];

        _checkWithdrawalRequestOwner(request, vetoer);
        _checkWithdrawalRequestWasLocked(request, unstETHId);

        sharesUnlocked = request.shares;
        if (request.state == WithdrawalRequestState.Finalized) {
            finalizedSharesUnlocked = sharesUnlocked;
            finalizedAmountUnlocked = request.claimableAmount;
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
    }

    function _finalizeWithdrawalRequest(
        State storage self,
        uint256 unstETHId,
        uint256 claimableAmount
    ) private returns (address owner, uint256 sharesFinalized, uint256 amountFinalized) {
        WithdrawalRequest storage request = self.requests[unstETHId];
        if (claimableAmount == 0 || request.state != WithdrawalRequestState.Locked) {
            return (request.owner, 0, 0);
        }
        owner = request.owner;
        request.state = WithdrawalRequestState.Finalized;
        request.claimableAmount = claimableAmount.toUint96();

        sharesFinalized = request.shares;
        amountFinalized = claimableAmount;
    }

    function _claimWithdrawalRequest(
        State storage self,
        uint256 unstETHId,
        uint256 claimableAmount
    ) private returns (uint256 amountClaimed) {
        WithdrawalRequest storage request = self.requests[unstETHId];

        if (request.state != WithdrawalRequestState.Locked && request.state != WithdrawalRequestState.Finalized) {
            revert WithdrawalRequestNotClaimable(unstETHId, request.state);
        }
        if (request.state == WithdrawalRequestState.Finalized && request.claimableAmount != claimableAmount) {
            revert ClaimableAmountChanged(unstETHId, claimableAmount, request.claimableAmount);
        } else {
            request.claimableAmount = claimableAmount.toUint96();
        }
        request.state = WithdrawalRequestState.Claimed;
        amountClaimed = claimableAmount;
    }

    function _withdrawWithdrawalRequest(
        State storage self,
        address vetoer,
        uint256 unstETHId
    ) private returns (uint256 amountWithdrawn) {
        WithdrawalRequest storage request = self.requests[unstETHId];

        if (request.owner != vetoer) {
            revert NotWithdrawalRequestOwner(unstETHId, vetoer, request.owner);
        }
        if (request.state != WithdrawalRequestState.Claimed) {
            revert InvalidWithdrawlRequestState(unstETHId, request.state, WithdrawalRequestState.Claimed);
        }
        request.state = WithdrawalRequestState.Withdrawn;
        amountWithdrawn = request.claimableAmount;
    }

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

    function _checkWithdrawalRequestNotLocked(WithdrawalRequest storage request, uint256 unstETHId) private view {
        if (request.vetoerUnstETHIndexOneBased != 0) {
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

    function _checkStETHSharesUnlock(State storage self, address vetoer, uint256 shares) private view {
        if (shares == 0) {
            revert InvalidSharesUnlock(vetoer, 0);
        }

        if (self.assets[vetoer].stETHShares < shares) {
            revert NotEnoughStETHToUnlock(shares, self.assets[vetoer].stETHShares);
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
