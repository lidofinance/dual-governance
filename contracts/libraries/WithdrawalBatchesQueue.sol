// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ArrayUtils} from "../utils/arrays.sol";
import {SequentialBatch, SequentialBatches} from "../types/SequentialBatches.sol";

enum Status {
    Empty, // The default status of the WithdrawalsBatchesQueue. In the closed state the only action allowed
    // to be called is open(), which transfers it into Opened state.
    Opened, // In the Opened state WithdrawalsBatchesQueue allows to add batches into the queue
    Closed // When the WithdrawalsBatchesQueue enters Filled queue - it's not allowed to add batches and
        // only allowed to mark batches claimed

}

/// @title WithdrawalsBatchesQueue
/// @dev A library for managing a queue of withdrawal batches.
library WithdrawalsBatchesQueue {
    using SafeCast for uint256;

    struct QueueIndex {
        uint32 batchIndex;
        uint16 valueIndex;
    }

    struct State {
        Status status;
        QueueIndex lastClaimedUnstETHIdIndex;
        uint48 totalUnstETHCount;
        uint48 totalUnstETHClaimed;
        SequentialBatch[] batches;
    }

    event UnstETHIdsAdded(uint256[] unstETHIds);
    event UnstETHIdsClaimed(uint256[] unstETHIds);

    error InvalidWithdrawalsBatchesQueueStatus(Status actual, Status expected);

    /// @dev Calculates the request amounts based on the given parameters.
    /// @param minRequestAmount The minimum request amount.
    /// @param maxRequestAmount The maximum request amount.
    /// @param remainingAmount The remaining amount to be requested.
    /// @return requestAmounts An array of request amounts.
    function calcRequestAmounts(
        uint256 minRequestAmount,
        uint256 maxRequestAmount,
        uint256 remainingAmount
    ) internal pure returns (uint256[] memory requestAmounts) {
        uint256 requestsCount = remainingAmount / maxRequestAmount;
        // last request amount will be equal to zero when it's multiple requestAmount
        // when it's in the range [0, minRequestAmount) - it will not be included in the result
        uint256 lastRequestAmount = remainingAmount - requestsCount * maxRequestAmount;
        if (lastRequestAmount >= minRequestAmount) {
            requestsCount += 1;
        }
        requestAmounts = ArrayUtils.seed(requestsCount, maxRequestAmount);
        if (lastRequestAmount >= minRequestAmount) {
            requestAmounts[requestsCount - 1] = lastRequestAmount;
        }
    }

    /// @dev Opens the WithdrawalsBatchesQueue, allowing batches to be added. Adds an empty batch as a stub.
    /// @param self The WithdrawalsBatchesQueue state.
    function open(State storage self) internal {
        _checkStatus(self, Status.Empty);
        // insert empty batch as a stub for first item
        self.batches.push(SequentialBatches.create({seed: 0, count: 1}));
        self.status = Status.Opened;
    }

    /// @dev Closes the WithdrawalsBatchesQueue, preventing further batch additions.
    /// @param self The WithdrawalsBatchesQueue state.
    function close(State storage self) internal {
        _checkStatus(self, Status.Opened);
        self.status = Status.Closed;
    }

    /// @dev Checks if the WithdrawalsBatchesQueue is closed.
    /// @param self The WithdrawalsBatchesQueue state.
    /// @return true if the WithdrawalsBatchesQueue is closed, false otherwise.
    function isClosed(State storage self) internal view returns (bool) {
        return self.status == Status.Closed;
    }

    /// @dev Checks if all unstETHIds in the WithdrawalsBatchesQueue have been claimed.
    /// @param self The WithdrawalsBatchesQueue state.
    /// @return true if all unstETHs have been claimed, false otherwise.
    function isAllUnstETHClaimed(State storage self) internal view returns (bool) {
        return self.totalUnstETHClaimed == self.totalUnstETHCount;
    }

    /// @dev Checks if the WithdrawalsBatchesQueue is in the Opened state.
    /// @param self The WithdrawalsBatchesQueue state.
    function checkOpened(State storage self) internal view {
        _checkStatus(self, Status.Opened);
    }

    /// @dev Adds new unstETHIds to the WithdrawalsBatchesQueue.
    /// @param self The WithdrawalsBatchesQueue state.
    /// @param unstETHIds The array of unstETH that have been added.
    function add(State storage self, uint256[] memory unstETHIds) internal {
        uint256 unstETHIdsCount = unstETHIds.length;
        if (unstETHIdsCount == 0) {
            return;
        }

        // before creating the batch, assert that the unstETHIds is sequential
        for (uint256 i = 0; i < unstETHIdsCount - 1; ++i) {
            assert(unstETHIds[i + 1] == unstETHIds[i] + 1);
        }

        uint256 lastBatchIndex = self.batches.length - 1;
        SequentialBatch lastWithdrawalsBatch = self.batches[lastBatchIndex];
        SequentialBatch newWithdrawalsBatch = SequentialBatches.create({seed: unstETHIds[0], count: unstETHIdsCount});

        if (SequentialBatches.canMerge(lastWithdrawalsBatch, newWithdrawalsBatch)) {
            self.batches[lastBatchIndex] = SequentialBatches.merge(lastWithdrawalsBatch, newWithdrawalsBatch);
        } else {
            self.batches.push(newWithdrawalsBatch);
        }

        self.totalUnstETHCount += newWithdrawalsBatch.size().toUint48();
        emit UnstETHIdsAdded(unstETHIds);
    }

    /// @dev Forms the next batch of unstETHs for claiming.
    /// @param self The WithdrawalsBatchesQueue state.
    /// @param maxUnstETHIdsCount The maximum number of unstETHIds to be claimed.
    /// @return unstETHIds The array of claimed unstETHIds.
    function claimNextBatch(
        State storage self,
        uint256 maxUnstETHIdsCount
    ) internal returns (uint256[] memory unstETHIds) {
        (unstETHIds, self.lastClaimedUnstETHIdIndex) = _getNextClaimableUnstETHIds(self, maxUnstETHIdsCount);
        self.totalUnstETHClaimed += unstETHIds.length.toUint48();
        emit UnstETHIdsClaimed(unstETHIds);
    }

    /// @dev Retrieves the next batch of unstETHIds that can be claimed from the WithdrawalsBatchesQueue.
    /// @param self The WithdrawalsBatchesQueue state.
    /// @param limit The maximum number of unstETHIds to be retrieved.
    /// @return unstETHIds The array of next claimable unstETHIds.
    function getNextWithdrawalsBatches(
        State storage self,
        uint256 limit
    ) internal view returns (uint256[] memory unstETHIds) {
        (unstETHIds,) = _getNextClaimableUnstETHIds(self, limit);
    }

    /// @dev Retrieves the next claimable unstETHIds from the WithdrawalsBatchesQueue.
    /// @param self The WithdrawalsBatchesQueue state.
    /// @param maxUnstETHIdsCount The maximum number of unstETHIds to be retrieved.
    /// @return unstETHIds The array of next claimable unstETHIds.
    /// @return lastClaimedUnstETHIdIndex The updated QueueIndex of the last claimed unstETHId.
    function _getNextClaimableUnstETHIds(
        State storage self,
        uint256 maxUnstETHIdsCount
    ) private view returns (uint256[] memory unstETHIds, QueueIndex memory lastClaimedUnstETHIdIndex) {
        uint256 unstETHIdsCount = Math.min(self.totalUnstETHCount - self.totalUnstETHClaimed, maxUnstETHIdsCount);

        unstETHIds = new uint256[](unstETHIdsCount);
        lastClaimedUnstETHIdIndex = self.lastClaimedUnstETHIdIndex;
        SequentialBatch currentBatch = self.batches[lastClaimedUnstETHIdIndex.batchIndex];

        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            lastClaimedUnstETHIdIndex.valueIndex += 1;
            if (currentBatch.size() == lastClaimedUnstETHIdIndex.valueIndex) {
                lastClaimedUnstETHIdIndex.batchIndex += 1;
                lastClaimedUnstETHIdIndex.valueIndex = 0;
                currentBatch = self.batches[lastClaimedUnstETHIdIndex.batchIndex];
            }
            unstETHIds[i] = currentBatch.valueAt(lastClaimedUnstETHIdIndex.valueIndex);
        }
    }

    /// @dev Checks if the actual status of the WithdrawalsBatchesQueue is the expected status and reverts if not.
    /// @param self The WithdrawalsBatchesQueue state.
    /// @param expectedStatus The expected status of the WithdrawalsBatchesQueue.
    function _checkStatus(State storage self, Status expectedStatus) private view {
        if (self.status != expectedStatus) {
            revert InvalidWithdrawalsBatchesQueueStatus(self.status, expectedStatus);
        }
    }
}
