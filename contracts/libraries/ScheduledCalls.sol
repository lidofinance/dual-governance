// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IExecutor} from "../interfaces/IExecutor.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

struct ExecutorCall {
    address target;
    uint96 value; // ~ 7.9 billion ETH
    bytes payload;
}

struct ScheduledCallsBatch {
    uint256 id;
    bool isCanceled;
    address executor;
    uint256 scheduledAt;
    uint256 executableAfter;
    ExecutorCall[] calls;
}

library ScheduledCallsBatches {
    using SafeCast for uint256;

    struct ScheduledCallsBatchPacked {
        // the reference in the batchIds array
        uint256 indexOneBased;
        uint32 delay;
        address executor;
        uint40 scheduledAt;
        ExecutorCall[] calls;
    }

    struct State {
        uint32 delay;
        // all scheduled batches with executableAfter less or equal than given cannot be executed
        uint40 canceledBeforeTimestamp;
        uint256[] batchIds;
        mapping(uint256 batchId => ScheduledCallsBatchPacked) batches;
    }

    event DelaySet(uint256 delay);
    event Scheduled(uint256 indexed batchId, uint256 delay, ExecutorCall[] calls);
    event Executed(uint256 indexed batchId, uint256 executedAt, bytes[] results);
    event Relayed(address indexed executor, ExecutorCall[] calls, bytes[] results);
    event UnscheduledAllBeforeTimestamp(uint256 timestamp);
    event CallsBatchRemoved(uint256 indexed batchId);

    error EmptyCallsArray();
    error RelayingDisabled();
    error SchedulingDisabled();
    error DelayNotExpired(uint256 batchId);
    error BatchNotScheduled(uint256 batchId);
    error CallsBatchCanceled(uint256 batchId);
    error BatchAlreadyScheduled(uint256 batchId);
    error CallsBatchNotCanceled(uint256 batchId);

    function schedule(State storage self, uint256 batchId, address executor, ExecutorCall[] calldata calls) internal {
        uint32 delay = self.delay;
        if (delay == 0) {
            revert SchedulingDisabled();
        }
        if (calls.length == 0) {
            revert EmptyCallsArray();
        }
        ScheduledCallsBatchPacked storage batch = self.batches[batchId];
        if (batch.indexOneBased != 0) {
            revert BatchAlreadyScheduled(batchId);
        }

        self.batchIds.push(batchId);
        uint256 indexOneBased = self.batchIds.length;

        batch.delay = delay;
        batch.executor = executor;
        batch.indexOneBased = indexOneBased;
        batch.scheduledAt = block.timestamp.toUint40();

        for (uint256 i = 0; i < calls.length; ++i) {
            batch.calls.push(ExecutorCall({value: calls[i].value, target: calls[i].target, payload: calls[i].payload}));
        }

        emit Scheduled(batchId, delay, calls);
    }

    function relay(
        State storage self,
        address executor,
        ExecutorCall[] calldata calls
    ) internal returns (bytes[] memory results) {
        if (self.delay > 0) {
            revert RelayingDisabled();
        }
        results = _executeCalls(executor, calls);
        emit Relayed(executor, calls, results);
    }

    function execute(State storage self, uint256 batchId) internal returns (bytes[] memory results) {
        ScheduledCallsBatchPacked memory batch = _remove(self, batchId);
        uint256 executableAfter = batch.scheduledAt + batch.delay;
        if (block.timestamp <= executableAfter) {
            revert DelayNotExpired(batchId);
        }
        // check that batch wasn't unscheduled
        if (executableAfter <= self.canceledBeforeTimestamp) {
            revert CallsBatchCanceled(batchId);
        }
        results = _executeCalls(batch.executor, batch.calls);
        emit Executed(batchId, block.timestamp, results);
    }

    function cancelAll(State storage self) internal {
        self.canceledBeforeTimestamp = block.timestamp.toUint40();
        emit UnscheduledAllBeforeTimestamp(block.timestamp);
    }

    function removeCanceled(State storage self, uint256 batchId) internal {
        ScheduledCallsBatchPacked memory removedBatch = _remove(self, batchId);
        if (removedBatch.scheduledAt > self.canceledBeforeTimestamp) {
            revert CallsBatchNotCanceled(batchId);
        }
        emit CallsBatchRemoved(batchId);
    }

    function setDelay(State storage self, uint256 delay) internal {
        if (self.delay != delay) {
            self.delay = delay.toUint32();
            emit DelaySet(delay);
        }
    }

    function get(State storage self, uint256 batchId) internal view returns (ScheduledCallsBatch memory batch) {
        return _unpack(batchId, _packed(self, batchId), self.canceledBeforeTimestamp);
    }

    function all(State storage self) internal view returns (ScheduledCallsBatch[] memory res) {
        uint256 batchIdsCount = self.batchIds.length;
        res = new ScheduledCallsBatch[](batchIdsCount);

        uint256 canceledBeforeTimestamp = self.canceledBeforeTimestamp;
        for (uint256 i = 0; i < batchIdsCount; ++i) {
            uint256 batchId = self.batchIds[i];
            res[i] = _unpack(batchId, self.batches[batchId], canceledBeforeTimestamp);
        }
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.batchIds.length;
    }

    function isCanceled(State storage self, uint256 batchId) internal view returns (bool) {
        ScheduledCallsBatchPacked storage packed = _packed(self, batchId);
        return packed.scheduledAt <= self.canceledBeforeTimestamp;
    }

    function isExecutable(State storage self, uint256 batchId) internal view returns (bool) {
        ScheduledCallsBatchPacked storage packed = _packed(self, batchId);
        uint256 scheduledAt = packed.scheduledAt;
        uint256 executableAfter = scheduledAt + packed.delay;
        return scheduledAt > self.canceledBeforeTimestamp && block.timestamp > executableAfter;
    }

    function _executeCalls(address executor, ExecutorCall[] memory calls) private returns (bytes[] memory results) {
        uint256 callsCount = calls.length;

        if (callsCount == 0) {
            revert EmptyCallsArray();
        }

        address target;
        uint256 value;
        bytes memory payload;
        results = new bytes[](callsCount);
        for (uint256 i = 0; i < callsCount; ++i) {
            value = calls[i].value;
            target = calls[i].target;
            payload = calls[i].payload;
            results[i] = IExecutor(payable(executor)).execute(target, value, payload);
        }
    }

    function _remove(State storage self, uint256 batchId) private returns (ScheduledCallsBatchPacked memory batch) {
        batch = _packed(self, batchId);

        // index can't be equal to zero at this point
        uint256 batchIndexToRemove = self.batches[batchId].indexOneBased - 1;
        uint256 lastBatchIndex = self.batchIds.length - 1;
        if (batchIndexToRemove != lastBatchIndex) {
            uint256 lastBatchId = self.batchIds[lastBatchIndex];
            self.batchIds[batchIndexToRemove] = lastBatchId;
            self.batches[lastBatchId].indexOneBased = batchIndexToRemove + 1;
        }
        self.batchIds.pop();

        // then remove the batch with calls
        delete self.batches[batchId];
    }

    function _packed(
        State storage self,
        uint256 batchId
    ) private view returns (ScheduledCallsBatchPacked storage packed) {
        packed = self.batches[batchId];
        if (packed.indexOneBased == 0) {
            revert BatchNotScheduled(batchId);
        }
    }

    function _unpack(
        uint256 batchId,
        ScheduledCallsBatchPacked memory packed,
        uint256 canceledBeforeTimestamp
    ) private pure returns (ScheduledCallsBatch memory batch) {
        batch.id = batchId;
        batch.calls = packed.calls;
        batch.executor = packed.executor;
        uint256 scheduledAt = packed.scheduledAt;
        batch.scheduledAt = scheduledAt;
        batch.executableAfter = scheduledAt + packed.delay;
        batch.isCanceled = scheduledAt <= canceledBeforeTimestamp;
    }
}
