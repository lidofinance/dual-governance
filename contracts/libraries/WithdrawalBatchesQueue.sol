// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice The state of the WithdrawalBatchesQueue
/// @param Empty The initial (uninitialized) state of the WithdrawalBatchesQueue
/// @param Opened In this state, the WithdrawalBatchesQueue allows the addition of new batches of unstETH ids
/// @param Closed The terminal state of the queue. In this state, the addition of new batches is forbidden
enum State {
    Absent,
    Opened,
    Closed
}

/// @title WithdrawalsBatchesQueue
/// @dev A library for managing a queue of withdrawal batches.
library WithdrawalsBatchesQueue {
    // ---
    // Errors
    // ---

    error EmptyBatch();
    error InvalidUnstETHIdsSequence();
    error NotAllBatchesClaimed(uint256 total, uint256 claimed);
    error InvalidWithdrawalsBatchesQueueState(State actual);
    error WithdrawalBatchesQueueIsInAbsentState();
    error WithdrawalBatchesQueueIsNotInOpenedState();
    error WithdrawalBatchesQueueIsNotInAbsentState();

    // ---
    // Events
    // ---

    event WithdrawalBatchesQueueClosed();
    event UnstETHIdsAdded(uint256[] unstETHIds);
    event UnstETHIdsClaimed(uint256[] unstETHIds);
    event WithdrawalBatchesQueueOpened(uint256 boundaryUnstETHId);

    // ---
    // Data types
    // ---

    /// @notice Represents a sequential batch of unstETH ids
    /// @param firstUnstETHId The id of the first unstETH in the batch
    /// @param lastUnstETHId The id of the last unstETH in the batch
    /// @dev If the batch contains only one item, firstUnstETHId == lastUnstETHId
    struct SequentialBatch {
        /// @dev slot0: [0..255]
        uint256 firstUnstETHId;
        /// @dev slot1: [0..255]
        uint256 lastUnstETHId;
    }

    /// @notice Holds the meta-information about the queue and the claiming process
    /// @param state The current state of the WithdrawalQueue
    /// @param lastClaimedBatchIndex The index of the batch containing the id of the last claimed unstETH NFT
    /// @param lastClaimedUnstETHIdIndex The index of the last claimed unstETH id in the batch with index `lastClaimedBatchIndex`
    /// @param totalUnstETHCount The total number of unstETH ids in the batches
    /// @param totalUnstETHClaimed The total number of unstETH ids that have been marked as claimed
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

    /// @notice The context of the WithdrawalsBatchesQueue library
    /// @param info The meta info of the queue
    /// @param batches The list of the withdrawal batches
    struct Context {
        /// @dev slot0: [0..255]
        QueueInfo info;
        /// @dev slot1: [0..255] - array length + 2 slots for each item
        SequentialBatch[] batches;
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Opens the WithdrawalsBatchesQueue, allowing batches to be added. Adds an empty batch as a stub.
    /// @param self The context of the WithdrawalsBatchesQueue
    /// @param boundaryUnstETHId The id of the unstETH NFT which is used as the boundary value for the withdrawal queue.
    /// `boundaryUnstETHId` value is used as a lower bound for the adding unstETH ids
    function open(Context storage self, uint256 boundaryUnstETHId) internal {
        if (self.info.state != State.Absent) {
            revert WithdrawalBatchesQueueIsNotInAbsentState();
        }

        self.info.state = State.Opened;

        /// @dev add the boundary UnstETH element into the queue, which will be used as the last unstETH id
        /// when the queue is empty. This element doesn't used during the claiming of the batches created
        /// via addUnstETHIds() method and always allocates single batch
        self.batches.push(SequentialBatch({firstUnstETHId: boundaryUnstETHId, lastUnstETHId: boundaryUnstETHId}));
        emit WithdrawalBatchesQueueOpened(boundaryUnstETHId);
    }

    /// @dev Adds new unstETHIds to the WithdrawalsBatchesQueue.
    /// @param self The WithdrawalsBatchesQueue context.
    /// @param unstETHIds The array of unstETH that have been added.
    function addUnstETHIds(Context storage self, uint256[] memory unstETHIds) internal {
        _checkInOpenedState(self);

        uint256 unstETHIdsCount = unstETHIds.length;

        if (unstETHIdsCount == 0) {
            revert EmptyBatch();
        }

        // before creating the batch, assert that the unstETHIds is sequential
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
            /// @dev this option is allowed only when used not the seed batch id
            self.batches[lastBatchIndex].lastUnstETHId = lastAddingUnstETHId;
        } else {
            self.batches.push(
                SequentialBatch({firstUnstETHId: firstAddingUnstETHId, lastUnstETHId: lastAddingUnstETHId})
            );
        }

        /// @dev theoretically here may happen math overflow, when the total unstETH count exceeds the capacity of
        /// the uint64 type, BUT in reality it's not possible if the system works properly
        self.info.totalUnstETHIdsCount += SafeCast.toUint64(unstETHIdsCount);
        emit UnstETHIdsAdded(unstETHIds);
    }

    /// @dev Forms the next batch of unstETHs for claiming.
    /// @param self The WithdrawalsBatchesQueue context.
    /// @param maxUnstETHIdsCount The maximum number of unstETHIds to be claimed.
    /// @return unstETHIds The array of claimed unstETHIds.
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

    /// @notice Closes the WithdrawalsBatchesQueue, preventing further batch additions
    /// @param self The context of the WithdrawalsBatchesQueue
    function close(Context storage self) internal {
        _checkInOpenedState(self);
        self.info.state = State.Closed;
        emit WithdrawalBatchesQueueClosed();
    }

    // ---
    // Getters
    // ---

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

        requestAmounts = new uint256[](requestsCount);
        for (uint256 i = 0; i < requestsCount; ++i) {
            requestAmounts[i] = maxRequestAmount;
        }

        if (lastRequestAmount >= minRequestAmount) {
            requestAmounts[requestsCount - 1] = lastRequestAmount;
        }
    }

    /// @dev Retrieves the next batch of unstETHIds that can be claimed from the WithdrawalsBatchesQueue.
    /// @param self The WithdrawalsBatchesQueue context.
    /// @param limit The maximum number of unstETHIds to be retrieved.
    /// @return unstETHIds The array of next claimable unstETHIds.
    function getNextWithdrawalsBatches(
        Context storage self,
        uint256 limit
    ) internal view returns (uint256[] memory unstETHIds) {
        (unstETHIds,) = _getNextClaimableUnstETHIds(self, limit);
    }

    /// @dev Retrieves the id of the boundary unstETH id. Reverts when the queue is in Absent context.
    /// @param self The WithdrawalsBatchesQueue context.
    /// @return boundaryUnstETHId The id of the boundary unstETH.
    function getBoundaryUnstETHId(Context storage self) internal view returns (uint256) {
        _checkNotInAbsentState(self);
        return self.batches[0].firstUnstETHId;
    }

    /// @dev Retrieves the total count of the unstETH ids added in the queue.
    /// @param self The WithdrawalsBatchesQueue context.
    /// @return totalUnstETHIdsCount The total count of the unstETH ids.
    function getTotalUnstETHIdsCount(Context storage self) internal view returns (uint256) {
        return self.info.totalUnstETHIdsCount;
    }

    /// @dev Retrieves the total unclaimed unstETH ids count.
    /// @param self The WithdrawalsBatchesQueue context.
    /// @return totalUnclaimedUnstETHIdsCount The total count of unclaimed unstETH ids
    function getTotalUnclaimedUnstETHIdsCount(Context storage self) internal view returns (uint256) {
        return self.info.totalUnstETHIdsCount - self.info.totalUnstETHIdsClaimed;
    }

    /// @dev Returns the id of the last claimed UnstETH. When the queue is empty, returns 0
    /// @param self The WithdrawalsBatchesQueue context.
    /// @return lastClaimedUnstETHId The id of the lastClaimedUnstETHId or 0 when the queue is empty
    function getLastClaimedOrBoundaryUnstETHId(Context storage self) internal view returns (uint256) {
        _checkNotInAbsentState(self);
        QueueInfo memory info = self.info;
        return self.batches[info.lastClaimedBatchIndex].firstUnstETHId + info.lastClaimedUnstETHIdIndex;
    }

    /// @dev Returns if all unstETH ids in the queue have been claimed
    /// @param self The WithdrawalsBatchesQueue context.
    /// @return isAllBatchesClaimed Equals true if all unstETHs have been claimed, false otherwise.
    function isAllBatchesClaimed(Context storage self) internal view returns (bool) {
        QueueInfo memory info = self.info;
        return info.totalUnstETHIdsClaimed == info.totalUnstETHIdsCount;
    }

    /// @dev Checks if the WithdrawalsBatchesQueue is closed.
    /// @param self The WithdrawalsBatchesQueue context.
    /// @return isClosed_ True if the WithdrawalsBatchesQueue is closed, false otherwise.
    function isClosed(Context storage self) internal view returns (bool isClosed_) {
        isClosed_ = self.info.state == State.Closed;
    }

    // ---
    // Helper Methods
    // ---

    /// @dev Retrieves the next claimable unstETHIds from the WithdrawalsBatchesQueue.
    /// @param self The WithdrawalsBatchesQueue context.
    /// @param maxUnstETHIdsCount The maximum number of unstETHIds to be retrieved.
    /// @return unstETHIds The array of next claimable unstETHIds.
    /// @return info The updated QueueIndex of the last claimed unstETHId.
    function _getNextClaimableUnstETHIds(
        Context storage self,
        uint256 maxUnstETHIdsCount
    ) private view returns (uint256[] memory unstETHIds, QueueInfo memory info) {
        info = self.info;
        uint256 unstETHIdsCount = Math.min(info.totalUnstETHIdsCount - info.totalUnstETHIdsClaimed, maxUnstETHIdsCount);

        unstETHIds = new uint256[](unstETHIdsCount);
        SequentialBatch memory currentBatch = self.batches[info.lastClaimedBatchIndex];

        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            info.lastClaimedUnstETHIdIndex += 1;
            uint256 unstETHIdsCountInTheBatch = currentBatch.lastUnstETHId - currentBatch.firstUnstETHId + 1;
            if (unstETHIdsCountInTheBatch == info.lastClaimedUnstETHIdIndex) {
                info.lastClaimedBatchIndex += 1;
                info.lastClaimedUnstETHIdIndex = 0;
                currentBatch = self.batches[info.lastClaimedBatchIndex];
            }
            unstETHIds[i] = currentBatch.firstUnstETHId + info.lastClaimedUnstETHIdIndex;
        }
        info.totalUnstETHIdsClaimed += SafeCast.toUint64(unstETHIdsCount);
    }

    /// @dev Checks the queue not in the Absent state.
    /// @param self The WithdrawalsBatchesQueue context.
    function _checkNotInAbsentState(Context storage self) private view {
        if (self.info.state == State.Absent) {
            revert WithdrawalBatchesQueueIsInAbsentState();
        }
    }

    /// @dev Checks the queue in the Opened state.
    /// @param self The WithdrawalsBatchesQueue context.
    function _checkInOpenedState(Context storage self) private view {
        if (self.info.state != State.Opened) {
            revert WithdrawalBatchesQueueIsNotInOpenedState();
        }
    }
}
