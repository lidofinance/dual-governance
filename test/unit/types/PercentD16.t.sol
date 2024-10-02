// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    PercentD16,
    PercentsD16,
    DivisionByZero,
    PercentD16Underflow,
    PercentD16Overflow,
    MAX_PERCENT_D16,
    HUNDRED_PERCENT_BP,
    HUNDRED_PERCENT_D16
} from "contracts/types/PercentD16.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {stdError} from "forge-std/StdError.sol";

contract PercentD16UnitTests is UnitTest {
    // ---
    // Comparison operations
    // ---

    // ---
    // lt()
    // ---

    function testFuzz_lt_HappyPath(PercentD16 a, PercentD16 b) external {
        assertEq(a < b, a.toUint256() < b.toUint256());
    }

    // ---
    // lte()
    // ---

    function testFuzz_lte_HappyPath(PercentD16 a, PercentD16 b) external {
        assertEq(a <= b, a.toUint256() <= b.toUint256());
    }

    // ---
    // eq()
    // ---

    function testFuzz_eq_HappyPath(PercentD16 a, PercentD16 b) external {
        assertEq(a == b, a.toUint256() == b.toUint256());
    }

    // ---
    // gt()
    // ---

    function testFuzz_gt_HappyPath(PercentD16 a, PercentD16 b) external {
        assertEq(a > b, a.toUint256() > b.toUint256());
    }

    // ---
    // gte()
    // ---

    function testFuzz_gte_HappyPath(PercentD16 a, PercentD16 b) external {
        assertEq(a >= b, a.toUint256() >= b.toUint256());
    }

    // ---
    // Arithmetic operations
    // ---

    // ---
    // plus
    // ---

    function test_plus_HappyPath() external {
        assertEq(PercentsD16.from(0) + PercentsD16.from(0), PercentsD16.from(0));
        assertEq(PercentsD16.from(0) + PercentsD16.from(1), PercentsD16.from(1));
        assertEq(PercentsD16.from(1) + PercentsD16.from(0), PercentsD16.from(1));
        assertEq(PercentsD16.from(500) + PercentsD16.from(20), PercentsD16.from(520));
        assertEq(PercentsD16.from(0) + PercentsD16.from(MAX_PERCENT_D16), PercentsD16.from(MAX_PERCENT_D16));
        assertEq(PercentsD16.from(MAX_PERCENT_D16) + PercentsD16.from(0), PercentsD16.from(MAX_PERCENT_D16));

        assertEq(
            PercentsD16.from(MAX_PERCENT_D16 / 2) + PercentsD16.from(MAX_PERCENT_D16 / 2 + 1),
            PercentsD16.from(MAX_PERCENT_D16)
        );
    }

    function test_plus_RevertOn_Overflow() external {
        vm.expectRevert(PercentD16Overflow.selector);
        this.external__plus(PercentsD16.from(MAX_PERCENT_D16), PercentsD16.from(1));

        vm.expectRevert(PercentD16Overflow.selector);
        this.external__plus(PercentsD16.from(MAX_PERCENT_D16), PercentsD16.from(MAX_PERCENT_D16));

        vm.expectRevert(PercentD16Overflow.selector);
        this.external__plus(PercentsD16.from(MAX_PERCENT_D16 / 2 + 1), PercentsD16.from(MAX_PERCENT_D16 / 2 + 1));
    }

    function testFuzz_plus_HappyPath(PercentD16 a, PercentD16 b) external {
        vm.assume(a.toUint256() + b.toUint256() <= MAX_PERCENT_D16);
        assertEq(a + b, PercentD16.wrap(uint128(a.toUint256() + b.toUint256())));
    }

    function testFuzz_plus_RevertOn_Overflow(PercentD16 a, PercentD16 b) external {
        vm.assume(a.toUint256() + b.toUint256() > MAX_PERCENT_D16);
        vm.expectRevert(PercentD16Overflow.selector);
        this.external__plus(a, b);
    }

    // ---
    // minus
    // ---

    function test_minus_HappyPath() external {
        assertEq(PercentsD16.from(5) - PercentsD16.from(2), PercentsD16.from(3));
        assertEq(PercentsD16.from(0) - PercentsD16.from(0), PercentsD16.from(0));
        assertEq(PercentsD16.from(1) - PercentsD16.from(0), PercentsD16.from(1));
    }

    function test_minus_RevertOn_Underflow() external {
        vm.expectRevert(PercentD16Underflow.selector);
        this.external__minus(PercentsD16.from(0), PercentsD16.from(1));

        vm.expectRevert(PercentD16Underflow.selector);
        this.external__minus(PercentsD16.from(4), PercentsD16.from(5));
    }

    function testFuzz_minus_HappyPath(PercentD16 a, PercentD16 b) external {
        vm.assume(a >= b);
        assertEq(a - b, PercentD16.wrap(uint128(a.toUint256() - b.toUint256())));
    }

    function testFuzz_minus_RevertOn_Underflow(PercentD16 a, PercentD16 b) external {
        vm.assume(a < b);
        vm.expectRevert(PercentD16Underflow.selector);
        this.external__minus(a, b);
    }

    // ---
    // Conversion operations
    // ---

    // ---
    // toUint256()
    // ---

    function test_toUint256_HappyPath() external {
        assertEq(PercentsD16.from(0).toUint256(), 0);
        assertEq(PercentsD16.from(1).toUint256(), 1);
        assertEq(PercentsD16.from(MAX_PERCENT_D16 / 2).toUint256(), MAX_PERCENT_D16 / 2);
        assertEq(PercentsD16.from(MAX_PERCENT_D16 - 1).toUint256(), MAX_PERCENT_D16 - 1);
        assertEq(PercentsD16.from(MAX_PERCENT_D16).toUint256(), MAX_PERCENT_D16);
    }

    function testFuzz_toUint256_HappyPath(PercentD16 a) external {
        assertEq(a.toUint256(), PercentD16.unwrap(a));
    }

    // ---
    // Namespaced helper methods
    // ---

    // ---
    // from()
    // ---

    function test_from_HappyPath() external {
        assertEq(PercentsD16.from(0), PercentD16.wrap(0));
        assertEq(PercentsD16.from(1), PercentD16.wrap(1));
        assertEq(PercentsD16.from(MAX_PERCENT_D16 / 2), PercentD16.wrap(uint128(MAX_PERCENT_D16 / 2)));
        assertEq(PercentsD16.from(MAX_PERCENT_D16 - 1), PercentD16.wrap(uint128(MAX_PERCENT_D16 - 1)));
        assertEq(PercentsD16.from(MAX_PERCENT_D16), PercentD16.wrap(uint128(MAX_PERCENT_D16)));
    }

    function test_from_RevertOn_Overflow() external {
        vm.expectRevert(PercentD16Overflow.selector);
        this.external__from(uint256(MAX_PERCENT_D16) + 1);

        vm.expectRevert(PercentD16Overflow.selector);
        this.external__from(type(uint256).max);
    }

    function testFuzz_from_HappyPath(uint256 a) external {
        vm.assume(a <= MAX_PERCENT_D16);
        assertEq(PercentsD16.from(a), PercentD16.wrap(uint128(a)));
    }

    function testFuzz_from_RevertOn_Overflow(uint256 a) external {
        vm.assume(a > MAX_PERCENT_D16);
        vm.expectRevert(PercentD16Overflow.selector);
        this.external__from(a);
    }

    // ---
    // fromFraction()
    // ---

    function test_fromFraction() external {
        assertEq(PercentsD16.fromFraction({numerator: 0, denominator: 1}), PercentsD16.from(0));
        assertEq(PercentsD16.fromFraction({numerator: 0, denominator: 33}), PercentsD16.from(0));
        assertEq(PercentsD16.fromFraction({numerator: 1, denominator: 1}), PercentsD16.from(100 * 10 ** 16));
        assertEq(PercentsD16.fromFraction({numerator: 1, denominator: 2}), PercentsD16.from(50 * 10 ** 16));
        assertEq(PercentsD16.fromFraction({numerator: 5, denominator: 2}), PercentsD16.from(250 * 10 ** 16));
        assertEq(PercentsD16.fromFraction({numerator: 2, denominator: 5}), PercentsD16.from(40 * 10 ** 16));
        assertEq(PercentsD16.fromFraction({numerator: 1, denominator: 100}), PercentsD16.from(1 * 10 ** 16));
        assertEq(PercentsD16.fromFraction({numerator: 2, denominator: 1000}), PercentsD16.from(0.2 * 10 ** 16));

        assertEq(
            PercentsD16.fromFraction({numerator: MAX_PERCENT_D16 / HUNDRED_PERCENT_D16, denominator: 1}),
            PercentsD16.from(MAX_PERCENT_D16 / HUNDRED_PERCENT_D16 * HUNDRED_PERCENT_D16)
        );

        assertEq(
            PercentsD16.fromFraction({
                numerator: MAX_PERCENT_D16 / HUNDRED_PERCENT_D16,
                denominator: HUNDRED_PERCENT_D16
            }),
            PercentsD16.from(MAX_PERCENT_D16 / HUNDRED_PERCENT_D16)
        );
    }

    function test_fromFraction_RevertOn_DenominatorIsZero() external {
        vm.expectRevert(DivisionByZero.selector);
        this.external__fromFraction({numerator: 1, denominator: 0});
    }

    function test_fromFraction_RevertOn_ArithmeticErrors() external {
        vm.expectRevert(stdError.arithmeticError);
        this.external__fromFraction({numerator: type(uint256).max, denominator: 1});

        vm.expectRevert(stdError.arithmeticError);
        this.external__fromFraction({numerator: type(uint256).max, denominator: type(uint256).max});

        vm.expectRevert(stdError.arithmeticError);
        this.external__fromFraction({numerator: type(uint256).max / HUNDRED_PERCENT_D16 + 1, denominator: 1});
    }

    function test_fromFraction_RevertOn_PercentD16Overflow() external {
        vm.expectRevert(PercentD16Overflow.selector);
        this.external__fromFraction({numerator: uint256(MAX_PERCENT_D16) + 1, denominator: 1});

        vm.expectRevert(PercentD16Overflow.selector);
        this.external__fromFraction({numerator: MAX_PERCENT_D16 / 1000, denominator: 100});
    }

    function testFuzz_fromFraction_HappyPath(uint256 numerator, uint256 denominator) external {
        vm.assume(numerator <= MAX_PERCENT_D16 / HUNDRED_PERCENT_D16);
        vm.assume(denominator > 0);
        assertEq(
            PercentsD16.fromFraction(numerator, denominator),
            PercentD16.wrap(uint128(HUNDRED_PERCENT_D16 * numerator / denominator))
        );
    }

    function testFuzz_fromFraction_RevertOn_ArithmeticErrors(uint256 numerator, uint256 denominator) external {
        (bool isSuccess,) = Math.tryMul(numerator, HUNDRED_PERCENT_D16);
        vm.assume(!isSuccess);
        vm.assume(denominator > 0);

        vm.expectRevert(stdError.arithmeticError);
        this.external__fromFraction(numerator, denominator);
    }

    function testFuzz_fromFraction_RevertOn_PercentD16Overflow(uint256 numerator, uint256 denominator) external {
        (bool isSuccess,) = Math.tryMul(numerator, HUNDRED_PERCENT_D16);
        vm.assume(isSuccess);

        vm.assume(denominator > 0);
        vm.assume(HUNDRED_PERCENT_D16 * numerator / denominator > MAX_PERCENT_D16);

        vm.expectRevert(PercentD16Overflow.selector);
        this.external__fromFraction(numerator, denominator);
    }

    // ---
    // fromBasisPoints()
    // ---

    function test_fromBasisPoints_HappyPath() external {
        assertEq(PercentsD16.fromBasisPoints(0), PercentsD16.from(0));
        assertEq(PercentsD16.fromBasisPoints(42_42), PercentsD16.from(42.42 * 10 ** 16));
        assertEq(PercentsD16.fromBasisPoints(100_00), PercentsD16.from(100 * 10 ** 16));
        assertEq(PercentsD16.fromBasisPoints(3000_00), PercentsD16.from(3000 * 10 ** 16));
        assertEq(
            PercentsD16.fromBasisPoints(uint256(HUNDRED_PERCENT_BP) * MAX_PERCENT_D16 / HUNDRED_PERCENT_D16),
            PercentsD16.from(
                uint256(MAX_PERCENT_D16) * HUNDRED_PERCENT_BP / HUNDRED_PERCENT_D16 * HUNDRED_PERCENT_D16
                    / HUNDRED_PERCENT_BP
            )
        );
    }

    function test_fromBasisPoints_RevertOn_ArithmeticErrors() external {
        vm.expectRevert(stdError.arithmeticError);
        this.external__fromBasisPoints(type(uint256).max);

        vm.expectRevert(stdError.arithmeticError);
        this.external__fromBasisPoints(type(uint256).max / HUNDRED_PERCENT_D16 * HUNDRED_PERCENT_BP);

        vm.expectRevert(stdError.arithmeticError);
        this.external__fromBasisPoints(type(uint256).max / HUNDRED_PERCENT_D16 + 1);
    }

    function test_fromBasisPoints_RevertOn_PercentD16Overflow() external {
        vm.expectRevert(PercentD16Overflow.selector);
        this.external__fromBasisPoints(MAX_PERCENT_D16);

        vm.expectRevert(PercentD16Overflow.selector);
        this.external__fromBasisPoints(MAX_PERCENT_D16 / HUNDRED_PERCENT_D16 * HUNDRED_PERCENT_BP * 10);
    }

    function testFuzz_fromBasisPoints(uint256 value) external {
        vm.assume(value <= MAX_PERCENT_D16 / HUNDRED_PERCENT_D16);
        assertEq(
            PercentsD16.fromBasisPoints(value),
            PercentD16.wrap(uint128(value * HUNDRED_PERCENT_D16 / HUNDRED_PERCENT_BP))
        );
    }

    // ---
    // Helper test methods
    // ---

    function external__fromBasisPoints(uint256 bpValue) external returns (PercentD16) {
        return PercentsD16.fromBasisPoints(bpValue);
    }

    function external__fromFraction(uint256 numerator, uint256 denominator) external returns (PercentD16) {
        return PercentsD16.fromFraction(numerator, denominator);
    }

    function external__plus(PercentD16 a, PercentD16 b) external returns (PercentD16) {
        return a + b;
    }

    function external__minus(PercentD16 a, PercentD16 b) external returns (PercentD16) {
        return a - b;
    }

    function external__from(uint256 value) external returns (PercentD16) {
        return PercentsD16.from(value);
    }
}
