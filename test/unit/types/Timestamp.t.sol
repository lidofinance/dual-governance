// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Timestamp, Timestamps, TimestampOverflow, MAX_TIMESTAMP_VALUE} from "contracts/types/Timestamp.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract TimestampTests is UnitTest {
    // ---
    // Constants
    // ---

    function test_MAX_TIMESTAMP_VALUE_HappyPath() external {
        assertEq(MAX_TIMESTAMP_VALUE, type(uint40).max);
    }

    // ---
    // Comparison operations
    // ---

    // ---
    // lt()
    // ---

    function testFuzz_lt_HappyPath(Timestamp t1, Timestamp t2) external {
        assertEq(t1 < t2, t1.toSeconds() < t2.toSeconds());
    }

    // ---
    // lte()
    // ---

    function testFuzz_lte_HappyPath(Timestamp t1, Timestamp t2) external {
        assertEq(t1 <= t2, t1.toSeconds() <= t2.toSeconds());
    }

    // ---
    // eq()
    // ---

    function testFuzz_eq_HappyPath(Timestamp t1, Timestamp t2) external {
        assertEq(t1 == t2, t1.toSeconds() == t2.toSeconds());
    }

    // ---
    // neq()
    // ---

    function testFuzz_neq_HappyPath(Timestamp t1, Timestamp t2) external {
        assertEq(t1 != t2, t1.toSeconds() != t2.toSeconds());
    }

    // ---
    // gte()
    // ---

    function testFuzz_gte_HappyPath(Timestamp t1, Timestamp t2) external {
        assertEq(t1 >= t2, t1.toSeconds() >= t2.toSeconds());
    }

    // ---
    // gt()
    // ---

    function testFuzz_gt_HappyPath(Timestamp t1, Timestamp t2) external {
        assertEq(t1 > t2, t1.toSeconds() > t2.toSeconds());
    }

    // ---
    // Conversion operations
    // ---

    function testFuzz_toSeconds_HappyPath(Timestamp t) external {
        assertEq(t.toSeconds(), Timestamp.unwrap(t));
    }

    // ---
    // Custom operations
    // ---

    // ---
    // isZero()
    // ---

    function test_isZero_HappyPath_ReturnsTrue() external {
        assertTrue(Timestamp.wrap(0).isZero());
    }

    function test_isZero_HappyPath_ReturnFalse() external {
        assertFalse(Timestamp.wrap(1).isZero());
        assertFalse(Timestamp.wrap(MAX_TIMESTAMP_VALUE / 2).isZero());
        assertFalse(Timestamp.wrap(MAX_TIMESTAMP_VALUE).isZero());
    }

    function testFuzz_isZero_HappyPath(Timestamp t) external {
        assertEq(t.isZero(), t == Timestamps.ZERO);
    }

    // ---
    // isNotZero()
    // ---

    function test_isNotZero_HappyPath_ReturnFalse() external {
        assertTrue(Timestamp.wrap(1).isNotZero());
        assertTrue(Timestamp.wrap(MAX_TIMESTAMP_VALUE / 2).isNotZero());
        assertTrue(Timestamp.wrap(MAX_TIMESTAMP_VALUE).isNotZero());
    }

    function test_isNotZero_HappyPath_ReturnsFalse() external {
        assertFalse(Timestamp.wrap(0).isNotZero());
    }

    function testFuzz_isNotZero_HappyPath(Timestamp t) external {
        assertEq(t.isNotZero(), t != Timestamps.ZERO);
    }

    // ---
    // Namespaced helper methods
    // ---

    // ---
    // now()
    // ---

    function testFuzz_max_HappyPath(Timestamp t1, Timestamp t2) external {
        assertEq(Timestamps.max(t1, t2), Timestamps.from(Math.max(t1.toSeconds(), t2.toSeconds())));
    }

    function test_now_HappyPath() external {
        assertEq(Timestamps.now(), Timestamps.from(block.timestamp));

        vm.warp(12 hours);
        assertEq(Timestamps.now(), Timestamps.from(block.timestamp));

        vm.warp(30 days);
        assertEq(Timestamps.now(), Timestamps.from(block.timestamp));

        vm.warp(365 days);
        assertEq(Timestamps.now(), Timestamps.from(block.timestamp));

        vm.warp(100 * 365 days);
        assertEq(Timestamps.now(), Timestamps.from(block.timestamp));

        vm.warp(1_000 * 365 days);
        assertEq(Timestamps.now(), Timestamps.from(block.timestamp));

        vm.warp(10_000 * 365 days);
        assertEq(Timestamps.now(), Timestamps.from(block.timestamp));

        vm.warp(34_000 * 365 days);
        assertEq(Timestamps.now(), Timestamps.from(block.timestamp));
    }

    function test_now_InvalidValueAfterApprox34000Years() external {
        vm.warp(MAX_TIMESTAMP_VALUE); // MAX_TIMESTAMP_VALUE is ~ 36812 year
        assertEq(Timestamps.now().toSeconds(), block.timestamp);

        // After the ~34800 years the uint40 timestamp value will overflow and conversion
        // of block.timestamp to uint40 will start return incorrect values.
        vm.warp(uint256(MAX_TIMESTAMP_VALUE) + 1);
        assertEq(Timestamps.now().toSeconds(), 0);
    }

    // ---
    // from()
    // ---

    function testFuzz_from_HappyPath(uint256 value) external {
        vm.assume(value <= MAX_TIMESTAMP_VALUE);
        assertEq(Timestamps.from(value), Timestamp.wrap(uint40(value)));
    }

    function testFuzz_from_RevertOn_Overflow(uint256 value) external {
        vm.assume(value > MAX_TIMESTAMP_VALUE);

        vm.expectRevert(TimestampOverflow.selector);
        this.external__from(value);
    }

    // ---
    // Helper test methods
    // ---

    function external__from(uint256 value) external returns (Timestamp) {
        return Timestamps.from(value);
    }
}
