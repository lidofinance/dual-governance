// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

uint256 constant BATCH_SIZE_LENGTH = 16;
uint256 constant BATCH_SIZE_MASK = 2 ** BATCH_SIZE_LENGTH - 1;

uint256 constant MAX_BATCH_SIZE = BATCH_SIZE_MASK;
uint256 constant MAX_BATCH_VALUE = 2 ** (256 - BATCH_SIZE_LENGTH) - 1;

// Stores the info about the withdrawals batch encoded as single uint256
// The 230 MST bits stores the id of the UnstETH id
// the 16 LST bits stores the size of the batch (max size is 2 ^ 16 - 1= 65535)
type SequentialBatch is uint256;

error BatchValueOverflow();
error InvalidBatchSize(uint256 size);
error IndexOutOfBounds(uint256 index);

using {size} for SequentialBatch global;
using {last} for SequentialBatch global;
using {first} for SequentialBatch global;
using {valueAt} for SequentialBatch global;
using {capacity} for SequentialBatch global;

function capacity(SequentialBatch) pure returns (uint256) {
    return MAX_BATCH_SIZE;
}

function size(SequentialBatch batch) pure returns (uint256) {
    unchecked {
        return SequentialBatch.unwrap(batch) & BATCH_SIZE_MASK;
    }
}

function first(SequentialBatch batch) pure returns (uint256) {
    unchecked {
        return SequentialBatch.unwrap(batch) >> BATCH_SIZE_LENGTH;
    }
}

function last(SequentialBatch batch) pure returns (uint256) {
    unchecked {
        return batch.first() + batch.size() - 1;
    }
}

function valueAt(SequentialBatch batch, uint256 index) pure returns (uint256) {
    if (index >= batch.size()) {
        revert IndexOutOfBounds(index);
    }
    unchecked {
        return batch.first() + index;
    }
}

library SequentialBatches {
    function create(uint256 seed, uint256 count) internal pure returns (SequentialBatch) {
        if (seed > MAX_BATCH_VALUE) {
            revert BatchValueOverflow();
        }
        if (count == 0 || count > MAX_BATCH_SIZE) {
            revert InvalidBatchSize(count);
        }
        unchecked {
            return SequentialBatch.wrap(seed << BATCH_SIZE_LENGTH | count);
        }
    }

    function canMerge(SequentialBatch b1, SequentialBatch b2) internal pure returns (bool) {
        unchecked {
            return b1.last() == b2.first() && b1.capacity() - b1.size() > 0;
        }
    }

    function merge(SequentialBatch b1, SequentialBatch b2) internal pure returns (SequentialBatch b3) {
        return create(b1.first(), b1.size() + b2.size());
    }
}
