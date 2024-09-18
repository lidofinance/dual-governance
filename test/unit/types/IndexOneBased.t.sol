// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IndicesOneBased, IndexOneBased, IndexOneBasedUnderflow} from "contracts/types/IndexOneBased.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract IndexOneBasedUnitTests is UnitTest {
    // ---
    // Comparison operations
    // ---

    function testFuzz_neq_HappyPath(IndexOneBased i1, IndexOneBased i2) external {
        assertEq(i1 != i2, IndexOneBased.unwrap(i1) != IndexOneBased.unwrap(i2));
    }

    function test_isEmpty_HappyPath() external {
        assertTrue(IndexOneBased.wrap(0).isEmpty());
        assertFalse(IndicesOneBased.fromOneBasedValue(1).isEmpty());
    }

    function testFuzz_isEmpty_HappyPath(IndexOneBased i1) external {
        assertEq(i1.isEmpty(), IndexOneBased.unwrap(i1) == 0);
    }

    function test_isNotEmpty_HappyPath() external {
        assertTrue(IndicesOneBased.fromOneBasedValue(1).isNotEmpty());
        assertFalse(IndexOneBased.wrap(0).isNotEmpty());
    }

    function testFuzz_isNotEmpty_HappyPath(IndexOneBased i1) external {
        assertEq(i1.isNotEmpty(), IndexOneBased.unwrap(i1) != 0);
    }

    function testFuzz_toZeroBasedValue_HappyPath(IndexOneBased index) external {
        vm.assume(IndexOneBased.unwrap(index) > 0);
        assertEq(index.toZeroBasedValue(), IndexOneBased.unwrap(index) - 1);
    }

    function test_toZeroBasedValue_RevertOn_EmptyIndex(IndexOneBased index) external {
        IndexOneBased emptyIndex = IndexOneBased.wrap(0);
        vm.expectRevert(IndexOneBasedUnderflow.selector);
        emptyIndex.toZeroBasedValue();
    }
}
