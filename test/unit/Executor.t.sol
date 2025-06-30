// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Executor} from "contracts/Executor.sol";
import {UnitTest} from "test/utils/unit-test.sol";

contract ExecutorTarget {
    event NonPayableMethodCalled(address caller);
    event PayableMethodCalled(address caller, uint256 value);

    function nonPayableMethod() external {
        emit NonPayableMethodCalled(msg.sender);
    }

    function payableMethod() external payable {
        emit PayableMethodCalled(msg.sender, msg.value);
    }
}

contract ExecutorUnitTests is UnitTest {
    address internal _owner = makeAddr("OWNER");

    Executor internal _executor;
    ExecutorTarget internal _target;

    function setUp() external {
        _target = new ExecutorTarget();
        _executor = new Executor(_owner);
    }

    function test_constructor_HappyPath() external {
        assertEq(_executor.owner(), _owner);
    }

    function test_constructor_RevertOn_ZeroOwnerAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Executor(address(0));
    }

    // ---
    // execute()
    // ---

    function test_execute_HappyPath_NonPayableMethod_ZeroValue() external {
        vm.expectEmit();
        emit ExecutorTarget.NonPayableMethodCalled(address(_executor));

        vm.expectEmit();
        emit Executor.Executed(address(_target), 0, abi.encodeCall(_target.nonPayableMethod, ()), new bytes(0));

        vm.prank(_owner);
        _executor.execute({target: address(_target), value: 0, payload: abi.encodeCall(_target.nonPayableMethod, ())});
    }

    function test_execute_HappyPath_PayableMethod_ZeroValue() external {
        vm.expectEmit();
        emit ExecutorTarget.PayableMethodCalled(address(_executor), 0);

        vm.expectEmit();
        emit Executor.Executed(address(_target), 0, abi.encodeCall(_target.payableMethod, ()), new bytes(0));

        vm.prank(_owner);
        _executor.execute({target: address(_target), value: 0, payload: abi.encodeCall(_target.payableMethod, ())});
    }

    function test_execute_HappyPath_PayableMethod_NonZeroValue() external {
        uint256 valueAmount = 1 ether;

        vm.deal(address(_executor), valueAmount);

        assertEq(address(_target).balance, 0);
        assertEq(address(_executor).balance, 1 ether);

        vm.expectEmit();
        emit ExecutorTarget.PayableMethodCalled(address(_executor), valueAmount);

        vm.expectEmit();
        emit Executor.Executed(address(_target), valueAmount, abi.encodeCall(_target.payableMethod, ()), new bytes(0));

        vm.prank(_owner);
        _executor.execute({
            target: address(_target),
            value: valueAmount,
            payload: abi.encodeCall(_target.payableMethod, ())
        });

        assertEq(address(_target).balance, valueAmount);
        assertEq(address(_executor).balance, 0);
    }

    function test_execute_RevertOn_NonPayableMethod_NonZeroValue() external {
        uint256 callValue = 1 ether;

        vm.deal(address(_executor), callValue);
        assertEq(address(_executor).balance, callValue);

        vm.prank(_owner);
        vm.expectRevert(Address.FailedInnerCall.selector);
        _executor.execute({
            target: address(_target),
            value: callValue,
            payload: abi.encodeCall(_target.nonPayableMethod, ())
        });
    }
    // ---
    // receive()
    // ---

    function test_receive_HappyPath() external {
        uint256 sendValue = 1 ether;

        vm.deal(address(this), sendValue);

        assertEq(address(this).balance, sendValue);
        assertEq(address(_executor).balance, 0);

        Address.sendValue(payable(address(_executor)), sendValue);

        assertEq(address(this).balance, 0);
        assertEq(address(_executor).balance, sendValue);
    }

    function test_receive_HappyPath_UsingSend() external {
        uint256 sendValue = 1 ether;

        vm.deal(address(this), sendValue);

        assertEq(address(this).balance, sendValue);
        assertEq(address(_executor).balance, 0);

        bool success = payable(address(_executor)).send(sendValue);

        assertTrue(success);
        assertEq(address(this).balance, 0);
        assertEq(address(_executor).balance, sendValue);
    }

    // ---
    // Custom call
    // ---

    function test_RevertOnInvalidMethodCall() external {
        vm.prank(_owner);
        (bool success, bytes memory returndata) =
            address(_executor).call{value: 1 ether}(abi.encodeWithSelector(bytes4(0xdeadbeaf), 42));

        assertFalse(success);
        assertEq(returndata, new bytes(0));
    }
}
