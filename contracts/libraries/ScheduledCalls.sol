// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IExecutor} from "../interfaces/IExecutor.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

struct ExecutorCall {
    address target;
    uint256 value;
    bytes payload;
}

struct ExecutorCallPacked {
    address target;
    uint96 value; // ~ 7.9 billion ETH
    bytes payload;
}

struct ScheduledCallsBatch {
    uint256 id;
    address executor;
    uint256 scheduledAt;
    uint256 executableAfter;
    ExecutorCall[] calls;
}

library ScheduledCallsBatches {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    struct ScheduledCallsBatchPacked {
        uint24 id;
        address executor;
        uint40 scheduledAt;
        uint32 delay;
        ExecutorCallPacked[] calls;
    }

    struct State {
        uint32 delay;
        // all scheduled batch with executableAfter less or equal than given cannot be executed
        uint40 unscheduledBeforeTimestamp;
        // TODO: add indexOneBased property instead of id in the ScheduledCallsBatchPacked struct
        // and keep the ids in the uint24[] array instead of UintSet for gas economy
        EnumerableSet.UintSet batchIds;
        mapping(uint256 batchId => ScheduledCallsBatchPacked) batches;
    }

    event Scheduled(uint256 indexed batchId, uint256 delay, ExecutorCall[] calls);
    event Executed(uint256 indexed batchId, uint256 executedAt, bytes[] results);
    event Relayed(address indexed executor, ExecutorCall[] calls, bytes[] results);
    event UnscheduledAllBeforeTimestamp(uint256 timestamp);
    event CallsBatchRemoved(uint256 indexed batchId);

    error EmptyCallsArray();
    error CallsUnscheduled();
    error RelayingDisabled();
    error SchedulingDisabled();
    error BatchNotScheduled(uint256 batchId);
    error BatchAlreadyScheduled(uint256 batchId);
    error CallsBatchNotCanceled(uint256 batchId);
    error TimelockNotExpired(uint256 batchId);
    error CallsBatchNotFound(uint256 batchId);

    function add(
        State storage self,
        uint256 batchId,
        address executor,
        ExecutorCall[] calldata calls
    ) internal {
        uint32 delay = self.delay;
        if (delay == 0) {
            revert SchedulingDisabled();
        }
        if (calls.length == 0) {
            revert EmptyCallsArray();
        }
        if (!self.batchIds.add(batchId)) {
            revert BatchAlreadyScheduled(batchId);
        }
        ScheduledCallsBatchPacked storage batch = self.batches[batchId];
        batch.id = batchId.toUint24();
        batch.executor = executor;
        batch.scheduledAt = block.timestamp.toUint40();
        batch.delay = delay;
        for (uint256 i = 0; i < calls.length; ) {
            ExecutorCallPacked storage call = batch.calls.push();

            call.target = calls[i].target;
            call.value = calls[i].value.toUint96();
            call.payload = calls[i].payload;

            unchecked {
                ++i;
            }
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

    function execute(
        State storage self,
        uint256 batchId
    ) internal returns (bytes[] memory results) {
        ScheduledCallsBatch memory batch = _remove(self, batchId);
        uint256 executableAfter = batch.executableAfter;
        if (block.timestamp <= executableAfter) {
            revert TimelockNotExpired(batchId);
        }
        // check that batch wasn't unscheduled
        if (executableAfter <= self.unscheduledBeforeTimestamp) {
            revert CallsUnscheduled();
        }
        results = _executeCalls(batch.executor, batch.calls);
        emit Executed(batchId, block.timestamp, results);
    }

    function cancelAll(State storage self) internal {
        self.unscheduledBeforeTimestamp = block.timestamp.toUint40();
        emit UnscheduledAllBeforeTimestamp(block.timestamp);
    }

    function removeCanceled(State storage self, uint256 batchId) internal {
        ScheduledCallsBatch memory removedBatch = _remove(self, batchId);
        if (removedBatch.scheduledAt > self.unscheduledBeforeTimestamp) {
            revert CallsBatchNotCanceled(batchId);
        }
        emit CallsBatchRemoved(batchId);
    }

    function get(
        State storage self,
        uint256 batchId
    ) internal view returns (ScheduledCallsBatch memory batch) {
        batch = _unpack(_packed(self, batchId));
    }

    function all(State storage self) internal view returns (ScheduledCallsBatch[] memory res) {
        uint256 batchIdsCount = self.batchIds.length();
        res = new ScheduledCallsBatch[](batchIdsCount);

        for (uint256 i = 0; i < batchIdsCount; ) {
            res[i] = _unpack(_packed(self, self.batchIds.at(i)));
            unchecked {
                ++i;
            }
        }
    }

    function count(State storage self) internal view returns (uint256 count_) {
        count_ = self.batchIds.length();
    }

    function isCanceled(State storage self, uint256 batchId) internal view returns (bool) {
        if (!self.batchIds.contains(batchId)) {
            revert CallsBatchNotFound(batchId);
        }
        return self.batches[batchId].scheduledAt <= self.unscheduledBeforeTimestamp;
    }

    function isExecutable(State storage self, uint256 batchId) internal view returns (bool) {
        if (!self.batchIds.contains(batchId)) {
            revert CallsBatchNotFound(batchId);
        }
        uint256 scheduledAt = self.batches[batchId].scheduledAt;
        uint256 executableAfter = scheduledAt + self.batches[batchId].delay;
        return scheduledAt > self.unscheduledBeforeTimestamp && block.timestamp > executableAfter;
    }

    function _executeCalls(
        address executor,
        ExecutorCall[] memory calls
    ) private returns (bytes[] memory results) {
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

    function _remove(
        State storage self,
        uint256 batchId
    ) private returns (ScheduledCallsBatch memory batch) {
        ScheduledCallsBatchPacked storage packed = _packed(self, batchId);
        batch = _unpack(packed);
        self.batchIds.remove(batchId);
        uint256 callsCount = batch.calls.length;
        // remove every item in the batch
        for (uint256 i = 0; i < callsCount; ) {
            self.batches[batchId].calls.pop();
            unchecked {
                ++i;
            }
        }

        // then remove the batch itself
        delete self.batches[batchId];
    }

    function _packed(
        State storage self,
        uint256 batchId
    ) private view returns (ScheduledCallsBatchPacked storage packed) {
        packed = self.batches[batchId];
        if (packed.id == 0) {
            revert BatchNotScheduled(batchId);
        }
    }

    function _unpack(
        ScheduledCallsBatchPacked storage packed
    ) private view returns (ScheduledCallsBatch memory batch) {
        batch.id = packed.id;
        batch.executor = packed.executor;
        batch.scheduledAt = packed.scheduledAt;
        batch.executableAfter = batch.scheduledAt + packed.delay;

        uint256 callsCount = packed.calls.length;
        batch.calls = new ExecutorCall[](callsCount);
        for (uint256 i = 0; i < callsCount; ) {
            batch.calls[i].target = packed.calls[i].target;
            batch.calls[i].value = packed.calls[i].value;
            batch.calls[i].payload = packed.calls[i].payload;
            unchecked {
                ++i;
            }
        }
    }
}
