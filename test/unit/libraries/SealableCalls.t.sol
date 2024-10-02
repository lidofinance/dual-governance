// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdError} from "forge-std/StdError.sol";
import {ISealable, SealableCalls} from "contracts/libraries/SealableCalls.sol";

import {UnitTest} from "test/utils/unit-test.sol";

error CustomSealableError(string reason);

contract SealableCallsTest is UnitTest {
    address private immutable _SEALABLE = makeAddr("SEALABLE");

    function test_callIsPaused_True_OnSucceedCallSealableReturnsTrue() external {
        _mockSealableIsPausedReturns(_SEALABLE, true);
        _assertIsPausedSealableCallResult({sealable: _SEALABLE, isCallSucceed: true, isPaused: true});
    }

    function test_callIsPaused_False_OnCallSealableReturnsFalse() external {
        _mockSealableIsPausedReturns(_SEALABLE, false);
        _assertIsPausedSealableCallResult({sealable: _SEALABLE, isCallSucceed: true, isPaused: false});
    }

    function test_callIsPaused_False_OnSealableIsNotContract() external {
        assertEq(_SEALABLE.code.length, 0);
        _assertIsPausedSealableCallResult({sealable: _SEALABLE, isCallSucceed: false, isPaused: false});
    }

    function test_callIsPaused_False_OnSealableRevertWithoutErrorReason() external {
        _mockSealableIsPausedReverts(_SEALABLE, "");
        _assertIsPausedSealableCallResult({sealable: _SEALABLE, isCallSucceed: false, isPaused: false});
    }

    function test_callIsPaused_False_OnSealableRevertWithStandardError() external {
        _mockSealableIsPausedReverts(_SEALABLE, stdError.divisionError);
        _assertIsPausedSealableCallResult({sealable: _SEALABLE, isCallSucceed: false, isPaused: false});
    }

    function test_callIsPaused_False_OnSealableRevertWithStringError() external {
        _mockSealableIsPausedReverts(_SEALABLE, "ERROR_MESSAGE");
        _assertIsPausedSealableCallResult({sealable: _SEALABLE, isCallSucceed: false, isPaused: false});
    }

    function test_callIsPaused_False_OnSealableRevertWithCustomError() external {
        _mockSealableIsPausedReverts(_SEALABLE, abi.encodeWithSelector(CustomSealableError.selector, "error reason"));
        _assertIsPausedSealableCallResult({sealable: _SEALABLE, isCallSucceed: false, isPaused: false});
    }

    function test_callIsPaused_False_OnSealableReturnsInvalidResultFitOneEVMWord() external {
        vm.mockCall(_SEALABLE, abi.encodeWithSelector(ISealable.isPaused.selector), abi.encode(42));
        _assertIsPausedSealableCallResult({sealable: _SEALABLE, isCallSucceed: false, isPaused: false});
    }

    function test_callIsPaused_False_OnSealableReturnsInvalidResultDynamicLength() external {
        string[] memory customResult = new string[](2);
        customResult[0] = "Hello";
        customResult[1] = "World";

        vm.mockCall(_SEALABLE, abi.encodeWithSelector(ISealable.isPaused.selector), abi.encode(customResult));
        _assertIsPausedSealableCallResult({sealable: _SEALABLE, isCallSucceed: false, isPaused: false});
    }

    // precompiles test is split into two methods because of the forge's out of gas error
    function test_callIsPaused_False_OnSealableIsPrecompileAddressPart1() external {
        // check precompile addresses in range (0x01, 0x07) ans address(0)
        for (uint256 i = 0; i < 8; ++i) {
            address precompile = address(uint160(i));
            _assertIsPausedSealableCallResult({sealable: precompile, isCallSucceed: false, isPaused: false});
        }
    }

    // precompiles test is split into two methods because of the forge's out of gas error
    function test_callIsPaused_False_OnSealableIsPrecompileAddressPart2() external {
        // check all precompile addresses including the addresses may become precompiles in the future
        for (uint256 i = 8; i < 16; ++i) {
            address precompile = address(uint160(i));
            _assertIsPausedSealableCallResult({sealable: precompile, isCallSucceed: false, isPaused: false});
        }
    }

    // ---
    // Helper Test Methods
    // ---

    function _mockSealableIsPausedReturns(address sealable, bool isPaused) internal {
        vm.mockCall(sealable, abi.encodeWithSelector(ISealable.isPaused.selector), abi.encode(isPaused));
    }

    function _mockSealableIsPausedReverts(address sealable, bytes memory revertReason) internal {
        vm.mockCallRevert(sealable, abi.encodeWithSelector(ISealable.isPaused.selector), revertReason);
    }

    function _assertIsPausedSealableCallResult(address sealable, bool isCallSucceed, bool isPaused) internal {
        (bool isCallSucceedActual, bool isPausedActual) = SealableCalls.callIsPaused(sealable);

        assertEq(isCallSucceedActual, isCallSucceed, "Unexpected isCallSucceed value");
        assertEq(isPausedActual, isPaused, "Unexpected isPaused value");
    }
}
