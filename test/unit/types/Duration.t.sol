// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    Duration, Durations, MAX_DURATION_VALUE, DurationOverflow, DurationUnderflow
} from "contracts/types/Duration.sol";
import {Timestamp, TimestampOverflow, MAX_TIMESTAMP_VALUE} from "contracts/types/Timestamp.sol";

import {stdError} from "forge-std/StdError.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract DurationTests is UnitTest {
    uint256 private constant MAX_SECONDS_VALUE = type(uint256).max - MAX_DURATION_VALUE;
    // ---
    // Conversion operations
    // ---

    function testFuzz_toSeconds_HappyPath(Duration d) external {
        assertEq(d.toSeconds(), Duration.unwrap(d));
    }

    // ---
    // Comparison operations
    // ---

    function testFuzz_lt_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 < d2, d1.toSeconds() < d2.toSeconds());
    }

    function testFuzz_lte_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 <= d2, d1.toSeconds() <= d2.toSeconds());
    }

    function testFuzz_eq_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 == d2, d1.toSeconds() == d2.toSeconds());
    }

    function testFuzz_neq_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 != d2, d1.toSeconds() != d2.toSeconds());
    }

    function testFuzz_gt_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 > d2, d1.toSeconds() > d2.toSeconds());
    }

    function testFuzz_gte_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 >= d2, d1.toSeconds() >= d2.toSeconds());
    }

    // ---
    // Arithmetic operations
    // ---

    function testFuzz_plus_HappyPath(Duration d1, Duration d2) external {
        uint256 expectedResult = d1.toSeconds() + d2.toSeconds();
        vm.assume(expectedResult <= MAX_DURATION_VALUE);

        assertEq(d1 + d2, Duration.wrap(uint32(expectedResult)));
    }

    function testFuzz_plus_Overflow(Duration d1, Duration d2) external {
        vm.assume(d1.toSeconds() + d2.toSeconds() > MAX_DURATION_VALUE);
        vm.expectRevert(DurationOverflow.selector);
        d1 + d2;
    }

    function testFuzz_minus_HappyPath(Duration d1, Duration d2) external {
        vm.assume(d1 >= d2);
        assertEq(d1 - d2, Durations.from(d1.toSeconds() - d2.toSeconds()));
    }

    function testFuzz_minus_Underflow(Duration d1, Duration d2) external {
        vm.assume(d1 < d2);
        vm.expectRevert(DurationUnderflow.selector);
        d1 - d2;
    }

    // ---
    // Custom operations
    // ---

    // ---
    // plusSeconds()
    // ---

    function testFuzz_plusSeconds_HappyPath(Duration d, uint256 seconds_) external {
        vm.assume(seconds_ < MAX_SECONDS_VALUE);
        vm.assume(d.toSeconds() + seconds_ <= MAX_DURATION_VALUE);

        assertEq(d.plusSeconds(seconds_), Duration.wrap(uint32(d.toSeconds() + seconds_)));
    }

    function testFuzz_plusSeconds_Overflow(Duration d, uint256 seconds_) external {
        vm.assume(seconds_ < MAX_SECONDS_VALUE);
        vm.assume(d.toSeconds() + seconds_ > MAX_DURATION_VALUE);

        vm.expectRevert(DurationOverflow.selector);
        d.plusSeconds(seconds_);
    }

    // ---
    // minusSeconds()
    // ---

    function testFuzz_minusSeconds_HappyPath(Duration d, uint256 seconds_) external {
        vm.assume(seconds_ <= d.toSeconds());

        assertEq(d.minusSeconds(seconds_), Duration.wrap(uint32(d.toSeconds() - seconds_)));
    }

    function testFuzz_minusSeconds_Overflow(Duration d, uint256 seconds_) external {
        vm.assume(seconds_ > d.toSeconds());

        vm.expectRevert(DurationUnderflow.selector);
        d.minusSeconds(seconds_);
    }

    // ---
    // dividedBy()
    // ---

    function testFuzz_dividedBy_HappyPath(Duration d, uint256 divisor) external {
        vm.assume(divisor != 0);
        assertEq(d.dividedBy(divisor), Duration.wrap(uint32(d.toSeconds() / divisor)));
    }

    function testFuzz_dividedBy_RevertOn_DivisorIsZero(Duration d) external {
        vm.expectRevert(stdError.divisionError);
        d.dividedBy(0);
    }

    // ---
    // multipliedBy()
    // ---

    function testFuzz_multipliedBy_HappyPath(Duration d, uint256 multiplicand) external {
        (bool isSuccess, uint256 expectedResult) = Math.tryMul(d.toSeconds(), multiplicand);
        vm.assume(isSuccess && expectedResult <= MAX_DURATION_VALUE);
        assertEq(d.multipliedBy(multiplicand), Duration.wrap(uint32(expectedResult)));
    }

    function testFuzz_multipliedBy_RevertOn_ResultOverflow(Duration d, uint256 multiplicand) external {
        (bool isSuccess, uint256 expectedResult) = Math.tryMul(d.toSeconds(), multiplicand);
        vm.assume(isSuccess && expectedResult > MAX_DURATION_VALUE);
        vm.expectRevert(DurationOverflow.selector);
        d.multipliedBy(multiplicand);
    }

    // ---
    // addTo()
    // ---

    function testFuzz_addTo_HappyPath(Duration d, Timestamp t) external {
        (bool isSuccess, uint256 expectedResult) = Math.tryAdd(t.toSeconds(), d.toSeconds());
        vm.assume(isSuccess && expectedResult <= MAX_TIMESTAMP_VALUE);
        assertEq(d.addTo(t), Timestamp.wrap(uint40(expectedResult)));
    }

    function testFuzz_addTo_RevertOn_Overflow(Duration d, Timestamp t) external {
        (bool isSuccess, uint256 expectedResult) = Math.tryAdd(t.toSeconds(), d.toSeconds());
        vm.assume(isSuccess && expectedResult > MAX_TIMESTAMP_VALUE);
        vm.expectRevert(TimestampOverflow.selector);
        d.addTo(t);
    }

    // ---
    // Namespaced helper methods
    // ---

    function test_ZERO_CorrectValue() external {
        assertEq(Durations.ZERO, Duration.wrap(0));
    }

    function test_MIN_CorrectValue() external {
        assertEq(Durations.MIN, Duration.wrap(0));
    }

    function test_MAX_CorrectValue() external {
        assertEq(Durations.MAX, Duration.wrap(uint32(MAX_DURATION_VALUE)));
    }

    function testFuzz_from_HappyPath(uint256 seconds_) external {
        vm.assume(seconds_ <= MAX_DURATION_VALUE);
        assertEq(Durations.from(seconds_), Duration.wrap(uint32(seconds_)));
    }

    function testFuzz_from_RevertOn_Overflow(uint256 seconds_) external {
        vm.assume(seconds_ > MAX_DURATION_VALUE);
        vm.expectRevert(DurationOverflow.selector);
        Durations.from(seconds_);
    }

    function testFuzz_between_HappyPath(Timestamp t1, Timestamp t2) external {
        uint256 t1Seconds = t1.toSeconds();
        uint256 t2Seconds = t2.toSeconds();
        uint256 expectedValue = t1Seconds > t2Seconds ? t1Seconds - t2Seconds : t2Seconds - t1Seconds;

        vm.assume(expectedValue <= MAX_DURATION_VALUE);

        assertEq(Durations.between(t1, t2), Duration.wrap(uint32(expectedValue)));
    }

    function testFuzz_between_RevertOn_Overflow(Timestamp t1, Timestamp t2) external {
        uint256 t1Seconds = t1.toSeconds();
        uint256 t2Seconds = t2.toSeconds();
        uint256 expectedValue = t1Seconds > t2Seconds ? t1Seconds - t2Seconds : t2Seconds - t1Seconds;

        vm.assume(expectedValue > MAX_DURATION_VALUE);

        vm.expectRevert(DurationOverflow.selector);
        Durations.between(t1, t2);
    }

    function testFuzz_min_HappyPath(Duration d1, Duration d2) external {
        assertEq(Durations.min(d1, d2), Durations.from(Math.min(d1.toSeconds(), d2.toSeconds())));
    }
}
