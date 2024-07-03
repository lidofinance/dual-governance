// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ArrayUtils} from "../utils/arrays.sol";

enum WithdrawalsBatchesQueueStatus {
    // The default status of the WithdrawalsBatchesQueue. In the closed state the only action allowed
    // to be called is open(), which transfers it into Opened state.
    Closed,
    // In the Opened state WithdrawalsBatchesQueue allows to add batches into the queue
    Opened,
    // When the WithdrawalsBatchesQueue enters Filled queue - it's not allowed to add batches and
    // only allowed to mark batches claimed
    Filled,
    // The final state of the WithdrawalsBatchesQueue. This state means that all withdrawal batches
    // were claimed
    Claimed
}

struct WithdrawalsBatch {
    uint16 size;
    uint240 fromUnstETHId;
}

library WithdrawalsBatchesQueue {
    using SafeCast for uint256;

    struct State {
        bool isFinalized;
        uint16 batchIndex;
        uint16 unstETHIndex;
        uint48 totalUnstETHCount;
        uint48 totalUnstETHClaimed;
        WithdrawalsBatch[] batches;
    }

    error AllBatchesAlreadyFormed();
    error InvalidUnstETHId(uint256 unstETHId);
    error NotFinalizable(uint256 stETHBalance);
    error ClaimingNotStarted();
    error ClaimingIsFinished();
    error EmptyWithdrawalsBatch();

    function calcRequestAmounts(
        uint256 minRequestAmount,
        uint256 requestAmount,
        uint256 amount
    ) internal pure returns (uint256[] memory requestAmounts) {
        uint256 requestsCount = amount / requestAmount;
        // last request amount will be equal to zero when it's multiple requestAmount
        // when it's in the range [0, minRequestAmount) - it will not be included in the result
        uint256 lastRequestAmount = amount - requestsCount * requestAmount;
        if (lastRequestAmount >= minRequestAmount) {
            requestsCount += 1;
        }
        requestAmounts = ArrayUtils.seed(requestsCount, requestAmount);
        if (lastRequestAmount >= minRequestAmount) {
            requestAmounts[requestsCount - 1] = lastRequestAmount;
        }
    }

    function add(State storage self, uint256[] memory unstETHIds) internal {
        uint256 newUnstETHIdsCount = unstETHIds.length;
        if (newUnstETHIdsCount == 0) {
            revert EmptyWithdrawalsBatch();
        }

        uint256 firstAddedUnstETHId = unstETHIds[0];
        if (self.batches.length == 0) {
            self.batches.push(
                WithdrawalsBatch({fromUnstETHId: firstAddedUnstETHId.toUint240(), size: newUnstETHIdsCount.toUint16()})
            );
            return;
        }

        WithdrawalsBatch memory lastBatch = self.batches[self.batches.length - 1];
        uint256 lastCreatedUnstETHId = lastBatch.fromUnstETHId + lastBatch.size;
        // when there is no gap between the lastly added unstETHId and the new one
        // then the batch may not be created, and added to the last one
        if (firstAddedUnstETHId == lastCreatedUnstETHId) {
            // but it may be done only when the batch max capacity is allowed to do it
            if (lastBatch.size + newUnstETHIdsCount <= type(uint16).max) {
                self.batches[self.batches.length - 1].size = (lastBatch.size + newUnstETHIdsCount).toUint16();
            }
        } else {
            self.batches.push(
                WithdrawalsBatch({fromUnstETHId: firstAddedUnstETHId.toUint240(), size: newUnstETHIdsCount.toUint16()})
            );
        }
        lastBatch = self.batches[self.batches.length - 1];
        self.totalUnstETHCount += newUnstETHIdsCount.toUint48();
    }

    function claimNextBatch(State storage self, uint256 maxUnstETHIdsCount) internal returns (uint256[] memory) {
        uint256 batchId = self.batchIndex;
        WithdrawalsBatch memory batch = self.batches[batchId];
        uint256 unstETHId = batch.fromUnstETHId + self.unstETHIndex;
        return claimNextBatch(self, unstETHId, maxUnstETHIdsCount);
    }

    function claimNextBatch(
        State storage self,
        uint256 unstETHId,
        uint256 maxUnstETHIdsCount
    ) internal returns (uint256[] memory result) {
        uint256 expectedUnstETHId = self.batches[self.batchIndex].fromUnstETHId + self.unstETHIndex;
        if (expectedUnstETHId != unstETHId) {
            revert InvalidUnstETHId(unstETHId);
        }

        uint256 unclaimedUnstETHIdsCount = self.totalUnstETHCount - self.totalUnstETHClaimed;
        uint256 unstETHIdsCountToClaim = Math.min(unclaimedUnstETHIdsCount, maxUnstETHIdsCount);

        uint256 batchIndex = self.batchIndex;
        uint256 unstETHIndex = self.unstETHIndex;
        result = new uint256[](unstETHIdsCountToClaim);
        self.totalUnstETHClaimed += unstETHIdsCountToClaim.toUint48();

        uint256 index = 0;
        while (unstETHIdsCountToClaim > 0) {
            WithdrawalsBatch memory batch = self.batches[batchIndex];
            uint256 unstETHIdsToClaimInBatch = Math.min(unstETHIdsCountToClaim, batch.size - unstETHIndex);
            for (uint256 i = 0; i < unstETHIdsToClaimInBatch; ++i) {
                result[i] = batch.fromUnstETHId + unstETHIndex + i;
            }
            index += unstETHIdsToClaimInBatch;
            unstETHIndex += unstETHIdsToClaimInBatch;
            unstETHIdsCountToClaim -= unstETHIdsToClaimInBatch;
            if (unstETHIndex == batch.size) {
                batchIndex += 1;
                unstETHIndex = 0;
            }
        }
        self.batchIndex = batchIndex.toUint16();
        self.unstETHIndex = unstETHIndex.toUint16();
    }

    function getNextWithdrawalsBatches(
        State storage self,
        uint256 limit
    ) internal view returns (uint256[] memory unstETHIds) {
        uint256 batchId = self.batchIndex;
        uint256 unstETHindex = self.unstETHIndex;
        WithdrawalsBatch memory batch = self.batches[batchId];
        uint256 unstETHId = batch.fromUnstETHId + self.unstETHIndex;
        uint256 unstETHIdsCount = Math.min(batch.size - unstETHindex, limit);

        unstETHIds = new uint256[](unstETHIdsCount);
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            unstETHIds[i] = unstETHId + i;
        }
    }

    function checkNotFinalized(State storage self) internal view {
        if (self.isFinalized) {
            revert AllBatchesAlreadyFormed();
        }
    }

    function finalize(State storage self) internal {
        self.isFinalized = true;
    }

    function isClaimingFinished(State storage self) internal view returns (bool) {
        return self.totalUnstETHClaimed == self.totalUnstETHCount;
    }

    function checkClaimingInProgress(State storage self) internal view {
        if (!self.isFinalized) {
            revert ClaimingNotStarted();
        }
        if (self.totalUnstETHCount > 0 && self.totalUnstETHCount == self.totalUnstETHClaimed) {
            revert ClaimingIsFinished();
        }
    }
}
