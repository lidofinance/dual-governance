// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ---
// Type Definition
// ---

type IndexOneBased is uint32;

// ---
// Assign Global Operations
// ---

using {neq as !=} for IndexOneBased global;
using {isEmpty, isNotEmpty, toZeroBasedValue} for IndexOneBased global;

// ---
// Errors
// ---

error IndexOneBasedOverflow();
error IndexOneBasedUnderflow();

// ---
// Constants
// ---

uint32 constant MAX_INDEX_ONE_BASED_VALUE = type(uint32).max;

// ---
// Comparison Operations
// ---

function neq(IndexOneBased i1, IndexOneBased i2) pure returns (bool) {
    return IndexOneBased.unwrap(i1) != IndexOneBased.unwrap(i2);
}

// ---
// Custom Operations
// ---

function isEmpty(IndexOneBased index) pure returns (bool) {
    return IndexOneBased.unwrap(index) == 0;
}

function isNotEmpty(IndexOneBased index) pure returns (bool) {
    return IndexOneBased.unwrap(index) > 0;
}

function toZeroBasedValue(IndexOneBased index) pure returns (uint256) {
    if (IndexOneBased.unwrap(index) == 0) {
        revert IndexOneBasedUnderflow();
    }
    unchecked {
        /// @dev Subtraction is safe because `index` is not zero.
        ///      The result fits within `uint32`, so casting to `uint256` is safe.
        return IndexOneBased.unwrap(index) - 1;
    }
}

// ---
// Namespaced Helper Methods
// ---

library IndicesOneBased {
    function fromOneBasedValue(uint256 oneBasedIndexValue) internal pure returns (IndexOneBased) {
        if (oneBasedIndexValue == 0) {
            revert IndexOneBasedUnderflow();
        }
        if (oneBasedIndexValue > MAX_INDEX_ONE_BASED_VALUE) {
            revert IndexOneBasedOverflow();
        }
        /// @dev Casting `oneBasedIndexValue` to `uint32` is safe as the check ensures it is less than or equal
        ///     to `MAX_INDEX_ONE_BASED_VALUE`, which fits within the `uint32`.
        return IndexOneBased.wrap(uint32(oneBasedIndexValue));
    }
}
