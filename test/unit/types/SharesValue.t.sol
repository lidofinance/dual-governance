// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    SharesValue,
    SharesValues,
    SharesValueOverflow,
    SharesValueUnderflow,
    MAX_SHARES_VALUE
} from "contracts/types/SharesValue.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract ETHTransfersForbiddenStub {
    error ETHTransfersForbidden();

    receive() external payable {
        revert ETHTransfersForbidden();
    }
}

contract SharesValueTests is UnitTest {
    // ---
    // Comparison operations
    // ---

    // ---
    // lt()
    // ---

    function testFuzz_lt_HappyPath(SharesValue v1, SharesValue v2) external {
        assertEq(v1 < v2, SharesValue.unwrap(v1) < SharesValue.unwrap(v2));
    }

    // ---
    // eq()
    // ---

    function testFuzz_eq_HappyPath(SharesValue v1, SharesValue v2) external {
        assertEq(v1 == v2, SharesValue.unwrap(v1) == SharesValue.unwrap(v2));
    }

    // ---
    // Arithmetic operations
    // ---

    // ---
    // plus()
    // ---

    function test_plus_HappyPath() external {
        assertEq(SharesValues.from(0) + SharesValues.from(0), SharesValue.wrap(0));
        assertEq(SharesValues.from(1) + SharesValues.from(0), SharesValue.wrap(1));
        assertEq(SharesValues.from(0) + SharesValues.from(1), SharesValue.wrap(1));
        assertEq(
            SharesValues.from(MAX_SHARES_VALUE / 2) + SharesValues.from(MAX_SHARES_VALUE / 2),
            SharesValue.wrap(type(uint128).max - 1)
        );
        assertEq(SharesValues.from(MAX_SHARES_VALUE) + SharesValues.from(0), SharesValue.wrap(type(uint128).max));
    }

    function test_plus_RevertOn_Overflow() external {
        vm.expectRevert(SharesValueOverflow.selector);
        this.external__plus(SharesValues.from(MAX_SHARES_VALUE), SharesValues.from(1));

        vm.expectRevert(SharesValueOverflow.selector);
        this.external__plus(SharesValues.from(MAX_SHARES_VALUE / 2 + 1), SharesValues.from(MAX_SHARES_VALUE / 2 + 1));
    }

    function testFuzz_plus_HappyPath(SharesValue v1, SharesValue v2) external {
        uint256 expectedResult = v1.toUint256() + v2.toUint256();
        vm.assume(expectedResult <= MAX_SHARES_VALUE);
        assertEq(v1 + v2, SharesValue.wrap(uint128(expectedResult)));
    }

    function testFuzz_plus_RevertOn_Overflow(SharesValue v1, SharesValue v2) external {
        uint256 expectedResult = v1.toUint256() + v2.toUint256();
        vm.assume(expectedResult > MAX_SHARES_VALUE);
        vm.expectRevert(SharesValueOverflow.selector);
        this.external__plus(v1, v2);
    }

    // ---
    // minus()
    // ---

    function test_minus_HappyPath() external {
        assertEq(SharesValues.from(0) - SharesValues.from(0), SharesValue.wrap(0));
        assertEq(SharesValues.from(1) - SharesValues.from(0), SharesValue.wrap(1));
        assertEq(SharesValues.from(1) - SharesValues.from(1), SharesValue.wrap(0));
        assertEq(
            SharesValues.from(MAX_SHARES_VALUE) - SharesValues.from(1), SharesValue.wrap(uint128(MAX_SHARES_VALUE - 1))
        );

        assertEq(SharesValues.from(MAX_SHARES_VALUE) - SharesValues.from(MAX_SHARES_VALUE), SharesValue.wrap(0));
    }

    function test_minus_RevertOn_SharesValueUnderflow() external {
        vm.expectRevert(SharesValueUnderflow.selector);
        this.external__minus(SharesValues.from(0), SharesValues.from(1));

        vm.expectRevert(SharesValueUnderflow.selector);
        this.external__minus(SharesValues.from(0), SharesValues.from(MAX_SHARES_VALUE));
    }

    function testFuzz_minus_HappyPath(SharesValue v1, SharesValue v2) external {
        vm.assume(SharesValue.unwrap(v1) > SharesValue.unwrap(v2));
        uint256 expectedResult = v1.toUint256() - v2.toUint256();
        assertEq(v1 - v2, SharesValue.wrap(uint128(expectedResult)));
    }

    function testFuzz_minus_Overflow(SharesValue v1, SharesValue v2) external {
        vm.assume(v1 < v2);
        vm.expectRevert(SharesValueUnderflow.selector);
        this.external__minus(v1, v2);
    }

    // ---
    // Custom operations
    // ---

    // ---
    // toUint256()
    // ---

    function test_toUint256_HappyPath() external {
        assertEq(SharesValues.from(0).toUint256(), 0);
        assertEq(SharesValues.from(MAX_SHARES_VALUE / 2).toUint256(), MAX_SHARES_VALUE / 2);
        assertEq(SharesValues.from(MAX_SHARES_VALUE).toUint256(), MAX_SHARES_VALUE);
    }

    function testFuzz_toUint256_HappyPath(SharesValue amount) external {
        assertEq(amount.toUint256(), SharesValue.unwrap(amount));
    }

    // ---
    // from()
    // ---

    function testFuzz_from_HappyPath(uint256 amount) external {
        vm.assume(amount <= MAX_SHARES_VALUE);
        assertEq(SharesValues.from(amount), SharesValue.wrap(uint128(amount)));
    }

    function testFuzz_from_RevertOn_Overflow(uint256 amount) external {
        vm.assume(amount > MAX_SHARES_VALUE);
        vm.expectRevert(SharesValueOverflow.selector);
        this.external__from(amount);
    }

    // ---
    // Helper test methods
    // ---

    function external__plus(SharesValue a, SharesValue b) external {
        a + b;
    }

    function external__minus(SharesValue a, SharesValue b) external {
        a - b;
    }

    function external__from(uint256 amount) external returns (SharesValue) {
        SharesValues.from(amount);
    }
}
