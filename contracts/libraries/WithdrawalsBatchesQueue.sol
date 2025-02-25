// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice The state of the WithdrawalBatchesQueue.
/// @param NotInitialized The initial (uninitialized) state of the WithdrawalBatchesQueue.
/// @param Opened In this state, the WithdrawalBatchesQueue allows the addition of new batches of unstETH ids.
/// @param Closed The terminal state of the queue where adding new batches is no longer permitted.
enum State {
    NotInitialized,
    Opened,
    Closed
}

/// @title Withdrawals Batches Queue Library
/// @notice A library for managing a queue of withdrawal batches.
library WithdrawalsBatchesQueue {
    // ---
    // Errors
    // ---

    error EmptyBatch();
    error InvalidUnstETHIdsSequence();
    error UnexpectedWithdrawalsBatchesQueueState(State state);

    // ---
    // Events
    // ---

    event WithdrawalsBatchesQueueClosed();
    event UnstETHIdsAdded(uint256[] unstETHIds);
    event UnstETHIdsClaimed(uint256[] unstETHIds);
    event WithdrawalsBatchesQueueOpened(uint256 boundaryUnstETHId);

    // ---
    // Data types
    // ---

    /// @notice Represents a sequential batch of unstETH ids.
    /// @param firstUnstETHId The id of the first unstETH in the batch.
    /// @param lastUnstETHId The id of the last unstETH in the batch.
    /// @dev If the batch contains only one item, `firstUnstETHId == lastUnstETHId`.
    struct SequentialBatch {
        /// @dev slot0: [0..255]
        uint256 firstUnstETHId;
        /// @dev slot1: [0..255]
        uint256 lastUnstETHId;
    }

    /// @notice Holds the meta-information about the queue and the claiming process.
    /// @param state The current state of the WithdrawalsBatchesQueue library.
    /// @param lastClaimedBatchIndex The index of the batch containing the id of the last claimed unstETH NFT.
    /// @param lastClaimedUnstETHIdIndex The index of the last claimed unstETH id in the batch with
    ///     index `lastClaimedBatchIndex`.
    /// @param totalUnstETHIdsCount The total number of unstETH ids in all batches.
    /// @param totalUnstETHIdsClaimed The total number of unstETH ids that have been marked as claimed.
    struct QueueInfo {
        /// @dev slot0: [0..7]
        State state;
        /// @dev slot0: [8..63]
        uint56 lastClaimedBatchIndex;
        /// @dev slot0: [64..127]
        uint64 lastClaimedUnstETHIdIndex;
        /// @dev slot0: [128..191]
        uint64 totalUnstETHIdsCount;
        /// @dev slot0: [192..255]
        uint64 totalUnstETHIdsClaimed;
    }

    /// @notice The context of the WithdrawalsBatchesQueue library.
    /// @param info The meta info of the queue.
    /// @param batches The list of the sequential withdrawal batches.
    struct Context {
        /// @dev slot0: [0..255]
        QueueInfo info;
        /// @dev slot1: [0..255] - array length + 2 slots for each item
        SequentialBatch[] batches;
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Opens the WithdrawalsBatchesQueue, allowing new batches to be added and initializing it with a
    ///     non-counted batch that serves as a lower boundary for all subsequently added unstETH ids.
    /// @param self The context of the Withdrawals Batches Queue library.
    /// @param boundaryUnstETHId The id of the unstETH NFT which is used as the boundary value for the withdrawal queue.
    ///     `boundaryUnstETHId` value is used as a lower bound for the adding unstETH ids.
    function open(Context storage self, uint256 boundaryUnstETHId) internal {
        _checkState(self, State.NotInitialized);

        self.info.state = State.Opened;

        /// @dev add the boundary unstETH element into the queue, which will be used as the last unstETH id
        ///     when the queue is empty. This element isn't used during the claiming of the batches created
        ///     via `addUnstETHIds()` method and always allocates single batch.
        self.batches.push(SequentialBatch({firstUnstETHId: boundaryUnstETHId, lastUnstETHId: boundaryUnstETHId}));
        emit WithdrawalsBatchesQueueOpened(boundaryUnstETHId);
    }

    /// @notice Adds a new batch of unstETH ids to the withdrawal queue.
    /// @param self The context of the Withdrawals Batches Queue library.
    /// @param unstETHIds An array of sequential unstETH ids to be added to the queue.
    function addUnstETHIds(Context storage self, uint256[] memory unstETHIds) internal {
        _checkState(self, State.Opened);

        uint256 unstETHIdsCount = unstETHIds.length;

        if (unstETHIdsCount == 0) {
            revert EmptyBatch();
        }

        /// @dev Ensure that unstETHIds are sequential before creating the batch
        for (uint256 i = 0; i < unstETHIdsCount - 1; ++i) {
            assert(unstETHIds[i + 1] == unstETHIds[i] + 1);
        }

        uint256 firstAddingUnstETHId = unstETHIds[0];
        uint256 lastAddingUnstETHId = unstETHIds[unstETHIdsCount - 1];

        uint256 lastBatchIndex = self.batches.length - 1;
        SequentialBatch memory lastWithdrawalsBatch = self.batches[lastBatchIndex];

        if (firstAddingUnstETHId <= lastWithdrawalsBatch.lastUnstETHId) {
            revert InvalidUnstETHIdsSequence();
        } else if (firstAddingUnstETHId == lastWithdrawalsBatch.lastUnstETHId + 1 && lastBatchIndex != 0) {
            /// @dev This condition applies only if not using the initial seed batch id
            self.batches[lastBatchIndex].lastUnstETHId = lastAddingUnstETHId;
        } else {
            self.batches.push(
                SequentialBatch({firstUnstETHId: firstAddingUnstETHId, lastUnstETHId: lastAddingUnstETHId})
            );
        }

        /// @dev Theoretically, overflow could occur if the total unstETH count exceeds `uint64` capacity,
        ///     BUT this should not happen in practice with a properly functioning system.
        self.info.totalUnstETHIdsCount += SafeCast.toUint64(unstETHIdsCount);
        emit UnstETHIdsAdded(unstETHIds);
    }

    /// @notice Retrieves and marks as claimed the next unclaimed sequence of unstETH ids in the withdrawal
    ///     batches queue, up to the specified maximum count.
    /// @param self The context of the Withdrawals Batches Queue library.
    /// @param maxUnstETHIdsCount The maximum number of unstETH ids to include in this claim batch.
    /// @return unstETHIds An array of unstETH ids that have been marked as claimed.
    function claimNextBatch(
        Context storage self,
        uint256 maxUnstETHIdsCount
    ) internal returns (uint256[] memory unstETHIds) {
        if (self.info.totalUnstETHIdsClaimed == self.info.totalUnstETHIdsCount) {
            revert EmptyBatch();
        }
        (unstETHIds, self.info) = _getNextClaimableUnstETHIds(self, maxUnstETHIdsCount);
        emit UnstETHIdsClaimed(unstETHIds);
    }

    /// @notice Closes the WithdrawalsBatchesQueue, preventing further batch additions.
    /// @param self The context of the Withdrawals Batches Queue library.
    function close(Context storage self) internal {
        _checkState(self, State.Opened);
        self.info.state = State.Closed;
        emit WithdrawalsBatchesQueueClosed();
    }

    // ---
    // Getters
    // ---

    /// @notice Calculates an array of request amounts based on the specified parameters.
    /// @param minRequestAmount The minimum permissible request amount. If the remaining amount for the last item
    ///     is less than this minimum, it will be excluded from the resulting array.
    /// @param maxRequestAmount The maximum request amount. Each item in the resulting array will equal this amount,
    ///     except possibly the last item, which may be smaller.
    /// @param remainingAmount The total remaining amount of stETH to be allocated into withdrawal requests.
    /// @return requestAmounts An array of calculated request amounts satisfying the given constraints.
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

        requestAmounts = new uint256[](requestsCount);
        for (uint256 i = 0; i < requestsCount; ++i) {
            requestAmounts[i] = maxRequestAmount;
        }

        if (lastRequestAmount >= minRequestAmount) {
            requestAmounts[requestsCount - 1] = lastRequestAmount;
        }
    }

    /// @notice Retrieves the next set of unstETH ids eligible for claiming, up to the specified limit.
    /// @param self The context of the Withdrawals Batches Queue library.
    /// @param limit The maximum number of unstETH ids to retrieve in this batch.
    /// @return unstETHIds An array of unstETH ids available for claiming.
    function getNextWithdrawalsBatches(
        Context storage self,
        uint256 limit
    ) internal view returns (uint256[] memory unstETHIds) {
        (unstETHIds,) = _getNextClaimableUnstETHIds(self, limit);
    }

    /// @notice Retrieves the total unclaimed unstETH ids count.
    /// @param self The context of the Withdrawals Batches Queue library.
    /// @return totalUnclaimedUnstETHIdsCount The total count of unclaimed unstETH ids.
    function getTotalUnclaimedUnstETHIdsCount(Context storage self) internal view returns (uint256) {
        return self.info.totalUnstETHIdsCount - self.info.totalUnstETHIdsClaimed;
    }

    /// @notice Returns the id of the boundary unstETH.
    /// @dev Reverts with an index OOB error if called when the `WithdrawalsBatchesQueue` is in the
    ///     `NotInitialized` state.
    /// @param self The context of the Withdrawals Batches Queue library.
    /// @return boundaryUnstETHId The id of the boundary unstETH.
    function getBoundaryUnstETHId(Context storage self) internal view returns (uint256) {
        return self.batches[0].firstUnstETHId;
    }

    /// @notice Returns if all unstETH ids in the queue have been claimed.
    /// @param self The context of the Withdrawals Batches Queue library.
    /// @return isAllBatchesClaimed Equals true if all unstETHs have been claimed, false otherwise.
    function isAllBatchesClaimed(Context storage self) internal view returns (bool) {
        QueueInfo memory info = self.info;
        return info.totalUnstETHIdsClaimed == info.totalUnstETHIdsCount;
    }

    /// @notice Returns whether the Withdrawals Batches Queue is closed.
    /// @param self The context of the Withdrawals Batches Queue library.
    /// @return isClosed_ `true` if the Withdrawals Batches Queue is closed, `false` otherwise.
    function isClosed(Context storage self) internal view returns (bool isClosed_) {
        isClosed_ = self.info.state == State.Closed;
    }

    // ---
    // Helper Methods
    // ---

    /// @dev Retrieves the next claimable unstETHIds from the Withdrawals Batches Queue.
    /// @param self The context of the Withdrawals Batches Queue library.
    /// @param maxUnstETHIdsCount The maximum number of unstETHIds to be retrieved.
    /// @return unstETHIds The array of next claimable unstETHIds.
    /// @return info The updated QueueInfo of the last claimed unstETHId.
    function _getNextClaimableUnstETHIds(
        Context storage self,
        uint256 maxUnstETHIdsCount
    ) private view returns (uint256[] memory unstETHIds, QueueInfo memory info) {
        info = self.info;
        uint256 unstETHIdsCount = Math.min(info.totalUnstETHIdsCount - info.totalUnstETHIdsClaimed, maxUnstETHIdsCount);

        unstETHIds = new uint256[](unstETHIdsCount);
        SequentialBatch memory currentBatch = self.batches[info.lastClaimedBatchIndex];

        uint256 unstETHIdsCountInTheBatch = currentBatch.lastUnstETHId - currentBatch.firstUnstETHId + 1;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            info.lastClaimedUnstETHIdIndex += 1;
            if (unstETHIdsCountInTheBatch == info.lastClaimedUnstETHIdIndex) {
                info.lastClaimedBatchIndex += 1;
                info.lastClaimedUnstETHIdIndex = 0;
                currentBatch = self.batches[info.lastClaimedBatchIndex];
                unstETHIdsCountInTheBatch = currentBatch.lastUnstETHId - currentBatch.firstUnstETHId + 1;
            }
            unstETHIds[i] = currentBatch.firstUnstETHId + info.lastClaimedUnstETHIdIndex;
        }
        info.totalUnstETHIdsClaimed += SafeCast.toUint64(unstETHIdsCount);
    }

    function _checkState(Context storage self, State expectedState) private view {
        if (self.info.state != expectedState) {
            revert UnexpectedWithdrawalsBatchesQueueState(self.info.state);
        }
    }
}
