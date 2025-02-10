// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    Duration,
    Durations,
    MAX_DURATION_VALUE,
    DivisionByZero,
    DurationOverflow,
    DurationUnderflow
} from "contracts/types/Duration.sol";
import {Timestamp, TimestampOverflow, MAX_TIMESTAMP_VALUE} from "contracts/types/Timestamp.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract DurationTests is UnitTest {
    // ---
    // Comparison operations
    // ---

    // ---
    // lt()
    // ---

    function test_lt_HappyPath_ReturnsTrue() external {
        assertTrue(Duration.wrap(1) < Duration.wrap(2));
        assertTrue(Duration.wrap(0) < Durations.from(MAX_DURATION_VALUE));
        assertTrue(Durations.from(MAX_DURATION_VALUE - 1) < Durations.from(MAX_DURATION_VALUE));
    }

    function test_lt_HappyPath_ReturnsFalse() external {
        assertFalse(Duration.wrap(0) < Duration.wrap(0));
        assertFalse(Duration.wrap(1) < Duration.wrap(0));
        assertFalse(Durations.from(MAX_DURATION_VALUE) < Durations.from(MAX_DURATION_VALUE - 1));
    }

    function testFuzz_lt_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 < d2, d1.toSeconds() < d2.toSeconds());
    }

    // ---
    // lte()
    // ---

    function test_lte_HappyPath_ReturnsTrue() external {
        assertTrue(Duration.wrap(0) <= Duration.wrap(0));
        assertTrue(Duration.wrap(1) <= Duration.wrap(2));
        assertTrue(Duration.wrap(2) <= Duration.wrap(2));
        assertTrue(Duration.wrap(0) <= Durations.from(MAX_DURATION_VALUE));
        assertTrue(Durations.from(MAX_DURATION_VALUE - 1) <= Durations.from(MAX_DURATION_VALUE));
        assertTrue(Durations.from(MAX_DURATION_VALUE) <= Durations.from(MAX_DURATION_VALUE));
    }

    function test_lte_HappyPath_ReturnsFalse() external {
        assertFalse(Duration.wrap(1) <= Duration.wrap(0));
        assertFalse(Durations.from(MAX_DURATION_VALUE) <= Durations.from(MAX_DURATION_VALUE - 1));
    }

    function testFuzz_lte_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 <= d2, d1.toSeconds() <= d2.toSeconds());
    }

    // ---
    // eq()
    // ---

    function test_eq_HappyPath_ReturnsTrue() external {
        assertTrue(Duration.wrap(0) == Duration.wrap(0));
        assertTrue(Duration.wrap(MAX_DURATION_VALUE / 2) == Duration.wrap(MAX_DURATION_VALUE / 2));
        assertTrue(Duration.wrap(MAX_DURATION_VALUE) == Duration.wrap(MAX_DURATION_VALUE));
    }

    function test_eq_HappyPath_ReturnsFalse() external {
        assertFalse(Duration.wrap(0) == Duration.wrap(1));
        assertFalse(Duration.wrap(1) == Duration.wrap(0));
        assertFalse(Duration.wrap(MAX_DURATION_VALUE / 2) == Duration.wrap(MAX_DURATION_VALUE));
        assertFalse(Duration.wrap(0) == Duration.wrap(MAX_DURATION_VALUE));
    }

    function testFuzz_eq_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 == d2, d1.toSeconds() == d2.toSeconds());
    }

    // ---
    // neq()
    // ---

    function test_neq_HappyPath_ReturnsTrue() external {
        assertTrue(Duration.wrap(0) != Duration.wrap(1));
        assertTrue(Duration.wrap(1) != Duration.wrap(0));
        assertTrue(Duration.wrap(MAX_DURATION_VALUE / 2) != Duration.wrap(MAX_DURATION_VALUE));
        assertTrue(Duration.wrap(0) != Duration.wrap(MAX_DURATION_VALUE));
    }

    function test_neq_HappyPath_ReturnsFalse() external {
        assertFalse(Duration.wrap(0) != Duration.wrap(0));
        assertFalse(Duration.wrap(MAX_DURATION_VALUE / 2) != Duration.wrap(MAX_DURATION_VALUE / 2));
        assertFalse(Duration.wrap(MAX_DURATION_VALUE) != Duration.wrap(MAX_DURATION_VALUE));
    }

    function testFuzz_neq_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 != d2, d1.toSeconds() != d2.toSeconds());
    }

    // ---
    // gte
    // ---

    function test_gte_HappyPath_ReturnsTrue() external {
        assertTrue(Duration.wrap(0) >= Duration.wrap(0));
        assertTrue(Duration.wrap(5) >= Duration.wrap(3));
        assertTrue(Duration.wrap(MAX_DURATION_VALUE) >= Duration.wrap(MAX_DURATION_VALUE / 2));
        assertTrue(Duration.wrap(MAX_DURATION_VALUE) >= Duration.wrap(MAX_DURATION_VALUE));
    }

    function test_gte_HappyPath_ReturnsFalse() external {
        assertFalse(Duration.wrap(0) >= Duration.wrap(1));
        assertFalse(Duration.wrap(5) >= Duration.wrap(9));
        assertFalse(Duration.wrap(MAX_DURATION_VALUE / 2) >= Duration.wrap(MAX_DURATION_VALUE));
    }

    function testFuzz_gte_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 >= d2, d1.toSeconds() >= d2.toSeconds());
    }

    // ---
    // gt
    // ---

    function test_gt_HappyPath_ReturnsTrue() external {
        assertTrue(Duration.wrap(1) > Duration.wrap(0));
        assertTrue(Duration.wrap(5) > Duration.wrap(3));
        assertTrue(Duration.wrap(MAX_DURATION_VALUE) > Duration.wrap(MAX_DURATION_VALUE / 2));
    }

    function test_gt_HappyPath_ReturnsFalse() external {
        assertFalse(Duration.wrap(0) > Duration.wrap(0));
        assertFalse(Duration.wrap(5) > Duration.wrap(9));
        assertFalse(Duration.wrap(MAX_DURATION_VALUE / 2) > Duration.wrap(MAX_DURATION_VALUE));
    }

    function testFuzz_gt_HappyPath(Duration d1, Duration d2) external {
        assertEq(d1 > d2, d1.toSeconds() > d2.toSeconds());
    }

    // ---
    // Arithmetic operations
    // ---

    // ---
    // plus()
    // ---

    function testFuzz_plus_HappyPath(Duration d1, Duration d2) external {
        uint256 expectedResult = d1.toSeconds() + d2.toSeconds();
        vm.assume(expectedResult <= MAX_DURATION_VALUE);

        assertEq(d1 + d2, Duration.wrap(uint32(expectedResult)));
    }

    function testFuzz_plus_Overflow(Duration d1, Duration d2) external {
        vm.assume(d1.toSeconds() + d2.toSeconds() > MAX_DURATION_VALUE);
        vm.expectRevert(DurationOverflow.selector);
        this.external__plus(d1, d2);
    }

    // ---
    // minus()
    // ---

    function testFuzz_minus_HappyPath(Duration d1, Duration d2) external {
        vm.assume(d1 >= d2);
        assertEq(d1 - d2, Durations.from(d1.toSeconds() - d2.toSeconds()));
    }

    function testFuzz_minus_Underflow(Duration d1, Duration d2) external {
        vm.assume(d1 < d2);
        vm.expectRevert(DurationUnderflow.selector);
        this.external__minus(d1, d2);
    }

    // ---
    // Custom operations
    // ---

    // ---
    // plusSeconds()
    // ---

    function testFuzz_plusSeconds_HappyPath(Duration d, uint256 secondsToAdd) external {
        vm.assume(secondsToAdd < type(uint256).max - MAX_DURATION_VALUE);
        vm.assume(d.toSeconds() + secondsToAdd <= MAX_DURATION_VALUE);

        assertEq(d.plusSeconds(secondsToAdd), Duration.wrap(uint32(d.toSeconds() + secondsToAdd)));
    }

    function testFuzz_plusSeconds_Overflow(Duration d, uint256 secondsToAdd) external {
        vm.assume(secondsToAdd < type(uint256).max - MAX_DURATION_VALUE);
        vm.assume(d.toSeconds() + secondsToAdd > MAX_DURATION_VALUE);

        vm.expectRevert(DurationOverflow.selector);
        this.external__plusSeconds(d, secondsToAdd);
    }

    // ---
    // minusSeconds()
    // ---

    function testFuzz_minusSeconds_HappyPath(Duration d, uint256 secondsToAdd) external {
        vm.assume(secondsToAdd <= d.toSeconds());

        assertEq(d.minusSeconds(secondsToAdd), Duration.wrap(uint32(d.toSeconds() - secondsToAdd)));
    }

    function testFuzz_minusSeconds_Overflow(Duration d, uint256 secondsToSubtract) external {
        vm.assume(secondsToSubtract > d.toSeconds());

        vm.expectRevert(DurationUnderflow.selector);
        this.external__minusSeconds(d, secondsToSubtract);
    }

    // ---
    // dividedBy()
    // ---

    function testFuzz_dividedBy_HappyPath(Duration d, uint256 divisor) external {
        vm.assume(divisor != 0);
        assertEq(d.dividedBy(divisor), Duration.wrap(uint32(d.toSeconds() / divisor)));
    }

    function testFuzz_dividedBy_RevertOn_DivisorIsZero(Duration d) external {
        vm.expectRevert(DivisionByZero.selector);
        this.external__dividedBy(d, 0);
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
        this.external__multipliedBy(d, multiplicand);
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
        this.external__addTo(d, t);
    }

    // ---
    // Conversion operations
    // ---

    function testFuzz_toSeconds_HappyPath(Duration d) external {
        assertEq(d.toSeconds(), Duration.unwrap(d));
    }

    // ---
    // Namespaced helper methods
    // ---

    function test_ZERO_CorrectValue() external {
        assertEq(Durations.ZERO, Duration.wrap(0));
    }

    function testFuzz_from_HappyPath(uint256 durationInSeconds) external {
        vm.assume(durationInSeconds <= MAX_DURATION_VALUE);
        assertEq(Durations.from(durationInSeconds), Duration.wrap(uint32(durationInSeconds)));
    }

    function testFuzz_from_RevertOn_Overflow(uint256 durationInSeconds) external {
        vm.assume(durationInSeconds > MAX_DURATION_VALUE);
        vm.expectRevert(DurationOverflow.selector);
        this.external__from(durationInSeconds);
    }

    // ---
    // Helper test methods
    // ---

    function external__plus(Duration d1, Duration d2) external returns (Duration) {
        return d1 + d2;
    }

    function external__minus(Duration d1, Duration d2) external returns (Duration) {
        return d1 - d2;
    }

    function external__plusSeconds(Duration d, uint256 secondsToAdd) external returns (Duration) {
        return d.plusSeconds(secondsToAdd);
    }

    function external__minusSeconds(Duration d, uint256 secondsToSubtract) external returns (Duration) {
        return d.minusSeconds(secondsToSubtract);
    }

    function external__dividedBy(Duration d, uint256 divisor) external returns (Duration) {
        return d.dividedBy(divisor);
    }

    function external__multipliedBy(Duration d, uint256 multiplicand) external returns (Duration) {
        return d.multipliedBy(multiplicand);
    }

    function external__addTo(Duration d, Timestamp t) external returns (Timestamp) {
        return d.addTo(t);
    }

    function external__from(uint256 valueInSeconds) external returns (Duration) {
        return Durations.from(valueInSeconds);
    }
}
