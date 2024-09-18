// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ---
// Type definition
// ---

type IndexOneBased is uint32;

// ---
// Errors
// ---

error IndexOneBasedOverflow();
error IndexOneBasedUnderflow();

// ---
// Assign global operations
// ---

using {neq as !=} for IndexOneBased global;
using {isEmpty, isNotEmpty, toZeroBasedValue} for IndexOneBased global;

// ---
// Comparison operations
// ---

function neq(IndexOneBased i1, IndexOneBased i2) pure returns (bool) {
    return IndexOneBased.unwrap(i1) != IndexOneBased.unwrap(i2);
}

// ---
// Custom operations
// ---

function isEmpty(IndexOneBased index) pure returns (bool) {
    return IndexOneBased.unwrap(index) == 0;
}

function isNotEmpty(IndexOneBased index) pure returns (bool) {
    return IndexOneBased.unwrap(index) != 0;
}

function toZeroBasedValue(IndexOneBased index) pure returns (uint256) {
    if (IndexOneBased.unwrap(index) == 0) {
        revert IndexOneBasedUnderflow();
    }
    unchecked {
        return IndexOneBased.unwrap(index) - 1;
    }
}

// ---
// Namespaced helper methods
// ---

library IndicesOneBased {
    function fromOneBasedValue(uint256 oneBasedIndexValue) internal pure returns (IndexOneBased) {
        if (oneBasedIndexValue > type(uint32).max) {
            revert IndexOneBasedOverflow();
        }
        return IndexOneBased.wrap(uint32(oneBasedIndexValue));
    }
}
