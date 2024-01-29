// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IExecutor} from "../interfaces/IExecutor.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

struct ExecutorCall {
    address target;
    uint96 value; // ~ 7.9 billion ETH
    bytes payload;
}

struct ScheduledExecutorCallsBatch {
    uint24 id;
    address executor;
    uint40 scheduledAt;
    uint40 executableAfter;
    ExecutorCall[] calls;
}

library ScheduledCalls {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    struct State {
        // all scheduled batch with executableAfter less or equal than given cannot be executed
        uint40 unscheduledBeforeTimestamp;
        // TODO: add ability to list all batched call ids
        // uint256[] batchIds;
        EnumerableSet.UintSet batchIds;
        mapping(uint256 batchId => ScheduledExecutorCallsBatch) batches;
    }

    event Scheduled(uint256 indexed batchId, uint256 executableAfter, ExecutorCall[] calls);
    event Forwarded(
        uint256 indexed batchId,
        address indexed executor,
        uint256 executedAt,
        ExecutorCall[] calls,
        bytes[] results
    );
    event Executed(uint256 indexed batchId, uint256 executedAt, bytes[] results);
    event UnscheduledAllBeforeTimestamp(uint256 timestamp);
    event CallsBatchRemoved(uint256 indexed batchId);

    error EmptyCallsArray();
    error CallsUnscheduled();
    error BatchNotScheduled(uint256 batchId);
    error BatchAlreadyScheduled(uint256 batchId);
    error CallsBatchNotCanceled(uint256 batchId);
    error TimelockNotExpired(uint256 batchId);
    error CallsBatchNotFound(uint256 batchId);

    function add(
        State storage self,
        uint256 batchId,
        address executor,
        uint256 timelock,
        ExecutorCall[] calldata calls
    ) internal {
        if (calls.length == 0) {
            revert EmptyCallsArray();
        }
        if (!self.batchIds.add(batchId)) {
            revert BatchAlreadyScheduled(batchId);
        }
        ScheduledExecutorCallsBatch storage batch = self.batches[batchId];
        batch.id = batchId.toUint24();
        batch.executor = executor;
        batch.scheduledAt = block.timestamp.toUint40();
        batch.executableAfter = (block.timestamp + timelock).toUint40();
        for (uint256 i = 0; i < calls.length; ) {
            ExecutorCall storage call = batch.calls.push();

            call.value = calls[i].value;
            call.target = calls[i].target;
            call.payload = calls[i].payload;

            unchecked {
                ++i;
            }
        }
        emit Scheduled(batchId, batch.executableAfter, calls);
    }

    function removeCanceled(State storage self, uint256 batchId) internal {
        ScheduledExecutorCallsBatch memory removedBatch = remove(self, batchId);
        if (removedBatch.scheduledAt > self.unscheduledBeforeTimestamp) {
            revert CallsBatchNotCanceled(batchId);
        }
        emit CallsBatchRemoved(batchId);
    }

    function remove(
        State storage self,
        uint256 batchId
    ) internal returns (ScheduledExecutorCallsBatch memory batch) {
        if (!self.batchIds.remove(batchId)) {
            revert BatchNotScheduled(batchId);
        }
        batch = self.batches[batchId];
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

    function forward(
        State storage,
        uint256 batchId,
        address executor,
        ExecutorCall[] calldata calls
    ) internal returns (bytes[] memory results) {
        results = _executeCalls(executor, calls);
        emit Forwarded(batchId, executor, block.timestamp, calls, results);
    }

    function execute(
        State storage self,
        uint256 batchId
    ) internal returns (bytes[] memory results) {
        ScheduledExecutorCallsBatch memory batch = remove(self, batchId);
        if (block.timestamp < batch.executableAfter) {
            revert TimelockNotExpired(batchId);
        }
        // check that batch wasn't unscheduled
        if (batch.executableAfter <= self.unscheduledBeforeTimestamp) {
            revert CallsUnscheduled();
        }
        results = _executeCalls(batch.executor, batch.calls);
        emit Executed(batchId, block.timestamp, results);
    }

    function has(State storage self, uint256 batchId) internal view returns (bool) {
        return self.batches[batchId].executableAfter > 0;
    }

    function get(
        State storage self,
        uint256 batchId
    ) internal view returns (ScheduledExecutorCallsBatch storage batch) {
        batch = self.batches[batchId];
    }

    function all(
        State storage self
    ) internal view returns (ScheduledExecutorCallsBatch[] memory res) {
        uint256 batchIdsCount = self.batchIds.length();
        res = new ScheduledExecutorCallsBatch[](batchIdsCount);

        for (uint256 i = 0; i < batchIdsCount; ) {
            res[i] = self.batches[self.batchIds.at(i)];
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
        return
            self.batches[batchId].scheduledAt > self.unscheduledBeforeTimestamp &&
            block.timestamp > self.batches[batchId].executableAfter;
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

    function cancelAll(State storage self) internal {
        self.unscheduledBeforeTimestamp = block.timestamp.toUint40();
        emit UnscheduledAllBeforeTimestamp(block.timestamp);
    }
}
