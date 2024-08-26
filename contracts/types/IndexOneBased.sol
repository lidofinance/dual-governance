// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

type IndexOneBased is uint32;

error IndexOneBasedOverflow();
error IndexOneBasedUnderflow();

using {neq as !=, isEmpty, isNotEmpty, toZeroBasedValue} for IndexOneBased global;

function neq(IndexOneBased i1, IndexOneBased i2) pure returns (bool) {
    return IndexOneBased.unwrap(i1) != IndexOneBased.unwrap(i2);
}

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

library IndicesOneBased {
    function fromOneBasedValue(uint256 oneBasedIndexValue) internal pure returns (IndexOneBased) {
        if (oneBasedIndexValue > type(uint32).max) {
            revert IndexOneBasedOverflow();
        }
        return IndexOneBased.wrap(uint32(oneBasedIndexValue));
    }
}
