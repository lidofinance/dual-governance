// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {ETHValue, ETHValues, ETHValueOverflow, ETHValueUnderflow, MAX_ETH_VALUE} from "contracts/types/ETHValue.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract ETHTransfersForbiddenStub {
    error ETHTransfersForbidden();

    receive() external payable {
        revert ETHTransfersForbidden();
    }
}

contract ETHValueTests is UnitTest {
    uint256 internal constant _MAX_ETH_SEND = 1_000_000 ether;
    address internal immutable _RECIPIENT = makeAddr("RECIPIENT");

    // ---
    // Comparison operations
    // ---

    function testFuzz_lt_HappyPath(ETHValue v1, ETHValue v2) external {
        assertEq(v1 < v2, ETHValue.unwrap(v1) < ETHValue.unwrap(v2));
    }

    function testFuzz_eq_HappyPath(ETHValue v1, ETHValue v2) external {
        assertEq(v1 == v2, ETHValue.unwrap(v1) == ETHValue.unwrap(v2));
    }

    function testFuzz_neq_HappyPath(ETHValue v1, ETHValue v2) external {
        assertEq(v1 != v2, ETHValue.unwrap(v1) != ETHValue.unwrap(v2));
    }

    function testFuzz_gt_HappyPath(ETHValue v1, ETHValue v2) external {
        assertEq(v1 > v2, ETHValue.unwrap(v1) > ETHValue.unwrap(v2));
    }

    // ---
    // Arithmetic operations
    // ---

    function testFuzz_plus_HappyPath(ETHValue v1, ETHValue v2) external {
        uint256 expectedResult = v1.toUint256() + v2.toUint256();
        vm.assume(expectedResult <= MAX_ETH_VALUE);
        assertEq(v1 + v2, ETHValue.wrap(uint128(expectedResult)));
    }

    function testFuzz_plus_Overflow(ETHValue v1, ETHValue v2) external {
        uint256 expectedResult = v1.toUint256() + v2.toUint256();
        vm.assume(expectedResult > MAX_ETH_VALUE);
        vm.expectRevert(ETHValueOverflow.selector);
        this.external__plus(v1, v2);
    }

    function testFuzz_minus_HappyPath(ETHValue v1, ETHValue v2) external {
        vm.assume(v1 > v2);
        uint256 expectedResult = v1.toUint256() - v2.toUint256();
        assertEq(v1 - v2, ETHValue.wrap(uint128(expectedResult)));
    }

    function testFuzz_minus_Overflow(ETHValue v1, ETHValue v2) external {
        vm.assume(v1 < v2);
        vm.expectRevert(ETHValueUnderflow.selector);
        this.external__minus(v1, v2);
    }

    // ---
    // Custom operations
    // ---

    function testFuzz_sendTo_HappyPath(ETHValue amount, uint256 balance) external {
        vm.assume(balance <= _MAX_ETH_SEND);
        vm.assume(amount.toUint256() <= balance);

        vm.deal(address(this), balance);

        assertEq(_RECIPIENT.balance, 0);

        amount.sendTo(payable(_RECIPIENT));
        assertEq(_RECIPIENT.balance, amount.toUint256());
    }

    function testFuzz_sendTo_RevertOn_InsufficientBalance(ETHValue amount, uint256 balance) external {
        vm.assume(balance <= _MAX_ETH_SEND);
        vm.assume(amount.toUint256() > balance);

        vm.deal(address(this), balance);

        vm.expectRevert(abi.encodeWithSelector(Address.AddressInsufficientBalance.selector, address(this)));
        this.external__sendTo(amount, payable(_RECIPIENT));
    }

    function testFuzz_sendTo_RevertOn_ETHTransfersForbidden(ETHValue amount, uint256 balance) external {
        vm.assume(balance <= _MAX_ETH_SEND);
        vm.assume(amount.toUint256() <= balance);

        vm.deal(address(this), balance);

        assertEq(_RECIPIENT.balance, 0);

        ETHTransfersForbiddenStub ethTransfersForbiddenStub = new ETHTransfersForbiddenStub();
        vm.expectRevert(Address.FailedInnerCall.selector);
        this.external__sendTo(amount, payable(address(ethTransfersForbiddenStub)));
    }

    function testFuzz_toUint256_HappyPath(ETHValue amount) external {
        assertEq(amount.toUint256(), ETHValue.unwrap(amount));
    }

    function testFuzz_from_HappyPath(uint256 amount) external {
        vm.assume(amount <= MAX_ETH_VALUE);
        assertEq(ETHValues.from(amount), ETHValue.wrap(uint128(amount)));
    }

    function testFuzz_from_RevertOn_Overflow(uint256 amount) external {
        vm.assume(amount > MAX_ETH_VALUE);
        vm.expectRevert(ETHValueOverflow.selector);
        this.external__from(amount);
    }

    function testFuzz_fromAddressBalance_HappyPath(ETHValue balance) external {
        vm.assume(balance.toUint256() <= _MAX_ETH_SEND);
        vm.deal(address(this), balance.toUint256());
        assertEq(balance, ETHValue.wrap(uint128(address(this).balance)));
    }

    function external__sendTo(ETHValue amount, address payable recipient) external {
        amount.sendTo(recipient);
    }

    function external__plus(ETHValue v1, ETHValue v2) external returns (ETHValue) {
        return v1 + v2;
    }

    function external__minus(ETHValue v1, ETHValue v2) external returns (ETHValue) {
        return v1 - v2;
    }

    function external__from(uint256 amount) external returns (ETHValue) {
        return ETHValues.from(amount);
    }
}
