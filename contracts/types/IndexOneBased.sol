// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

type IndexOneBased is uint32;

error IndexOneBasedOverflow();
error IndexOneBasedUnderflow();

using {neq as !=} for IndexOneBased global;
using {value} for IndexOneBased global;

function neq(IndexOneBased i1, IndexOneBased i2) pure returns (bool) {
    return IndexOneBased.unwrap(i1) != IndexOneBased.unwrap(i2);
}

function value(IndexOneBased index) pure returns (uint256) {
    if (IndexOneBased.unwrap(index) == 0) {
        revert IndexOneBasedUnderflow();
    }
    unchecked {
        return IndexOneBased.unwrap(index) - 1;
    }
}

library IndicesOneBased {
    function from(uint256 value) internal pure returns (IndexOneBased) {
        if (value > type(uint32).max) {
            revert IndexOneBasedOverflow();
        }
        return IndexOneBased.wrap(uint32(value));
    }
}
