// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdError} from "forge-std/StdError.sol";
import {ISealable, SealableCalls, MIN_VALID_SEALABLE_ADDRESS} from "contracts/libraries/SealableCalls.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {SealableMock} from "test/mocks/SealableMock.sol";

error CustomSealableError(string message);

contract SealableCallsTest is UnitTest {
    address private immutable _SEALABLE = makeAddr("SEALABLE");

    function test_callGetResumeSinceTimestamp_IsCallSucceedTrue() external {
        // edge case when timestamp is 0
        _mockSealableResumeSinceTimestampResult(_SEALABLE, 0);
        _assertGetResumeSinceTimestampCallResult({sealable: _SEALABLE, isCallSucceed: true, resumeSinceTimestamp: 0});

        // edge case when sealable paused indefinitely
        _mockSealableResumeSinceTimestampResult(_SEALABLE, type(uint256).max);
        _assertGetResumeSinceTimestampCallResult({
            sealable: _SEALABLE,
            isCallSucceed: true,
            resumeSinceTimestamp: type(uint256).max
        });

        // paused for finite time
        uint256 sealablePauseDuration = 14 days;
        _mockSealableResumeSinceTimestampResult(_SEALABLE, block.timestamp + sealablePauseDuration);
        _assertGetResumeSinceTimestampCallResult({
            sealable: _SEALABLE,
            isCallSucceed: true,
            resumeSinceTimestamp: block.timestamp + sealablePauseDuration
        });
    }

    function testFuzz_callGetResumeSinceTimestamp_IsCallSucceedTrue(uint256 resumeSinceTimestamp) external {
        _mockSealableResumeSinceTimestampResult(_SEALABLE, resumeSinceTimestamp);
        _assertGetResumeSinceTimestampCallResult({
            sealable: _SEALABLE,
            isCallSucceed: true,
            resumeSinceTimestamp: resumeSinceTimestamp
        });
    }

    function test_callGetResumeSinceTimestamp_IsCallSucceedFalse_OnSealableIsNotContract() external {
        assertEq(_SEALABLE.code.length, 0);
        _assertGetResumeSinceTimestampCallResult({sealable: _SEALABLE, isCallSucceed: false, resumeSinceTimestamp: 0});
    }

    function test_callGetResumeSinceTimestamp_IsCallSucceedFalse_OnSealableRevertWithoutErrorReason() external {
        _mockSealableResumeSinceTimestampReverts(_SEALABLE, "");
        _assertGetResumeSinceTimestampCallResult({sealable: _SEALABLE, isCallSucceed: false, resumeSinceTimestamp: 0});
    }

    function test_callGetResumeSinceTimestamp_IsCallSucceedFalse_OnSealableRevertWithStandardError() external {
        _mockSealableResumeSinceTimestampReverts(_SEALABLE, stdError.divisionError);
        _assertGetResumeSinceTimestampCallResult({sealable: _SEALABLE, isCallSucceed: false, resumeSinceTimestamp: 0});
    }

    function test_callGetResumeSinceTimestamp_IsCallSucceedFalse_OnSealableRevertWithStringError() external {
        _mockSealableResumeSinceTimestampReverts(_SEALABLE, "ERROR_MESSAGE");
        _assertGetResumeSinceTimestampCallResult({sealable: _SEALABLE, isCallSucceed: false, resumeSinceTimestamp: 0});
    }

    function test_callGetResumeSinceTimestamp_IsCallSucceedFalse_OnSealableRevertWithCustomError() external {
        _mockSealableResumeSinceTimestampReverts(
            _SEALABLE, abi.encodeWithSelector(CustomSealableError.selector, "error reason")
        );
        _assertGetResumeSinceTimestampCallResult({sealable: _SEALABLE, isCallSucceed: false, resumeSinceTimestamp: 0});
    }

    function test_callGetResumeSinceTimestamp_IsCallSucceedFalse_OnSealableReturnsInvalidResultDynamicLength()
        external
    {
        string[] memory customResult = new string[](2);
        customResult[0] = "Hello";
        customResult[1] = "World";

        vm.mockCall(
            _SEALABLE, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), abi.encode(customResult)
        );
        _assertGetResumeSinceTimestampCallResult({sealable: _SEALABLE, isCallSucceed: false, resumeSinceTimestamp: 0});
    }

    function test_callGetResumeSinceTimestamp_IsCallSucceedFalse_OnSealableLessThanMinValidSealableAddress() external {
        // check addresses (0x00, 0x400) reserved for precompiles.
        // Currently Ethereum has only precompiles for 0x01 - 0x09 but new precompiles may be added in the future
        for (uint256 i = 0; i < uint160(MIN_VALID_SEALABLE_ADDRESS); ++i) {
            address precompile = address(uint160(i));
            _assertGetResumeSinceTimestampCallResult({
                sealable: precompile,
                isCallSucceed: false,
                resumeSinceTimestamp: 0
            });
        }

        address LAST_INVALID_SEALABLE_ADDRESS = address(uint160(MIN_VALID_SEALABLE_ADDRESS) - 1);
        // assuming address MIN_VALID_SEALABLE_ADDRESS and LAST_INVALID_SEALABLE_ADDRESS has
        // deployed bytecode which returns some value
        _mockSealableResumeSinceTimestampResult(MIN_VALID_SEALABLE_ADDRESS, block.timestamp);
        _mockSealableResumeSinceTimestampResult(LAST_INVALID_SEALABLE_ADDRESS, block.timestamp);

        // call to the LAST_INVALID_SEALABLE_ADDRESS considered not succeed as made to precompile
        _assertGetResumeSinceTimestampCallResult({
            sealable: LAST_INVALID_SEALABLE_ADDRESS,
            isCallSucceed: false,
            resumeSinceTimestamp: 0
        });

        // but call to the MIN_VALID_SEALABLE_ADDRESS considered succeed
        _assertGetResumeSinceTimestampCallResult({
            sealable: MIN_VALID_SEALABLE_ADDRESS,
            isCallSucceed: true,
            resumeSinceTimestamp: block.timestamp
        });
    }

    // ---
    // Helper Test Methods
    // ---

    function _mockSealableResumeSinceTimestampResult(address sealable, uint256 resumeSinceTimestamp) internal {
        vm.mockCall(
            sealable,
            abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector),
            abi.encode(resumeSinceTimestamp)
        );
    }

    function _assertGetResumeSinceTimestampCallResult(
        address sealable,
        bool isCallSucceed,
        uint256 resumeSinceTimestamp
    ) internal {
        (bool isCallSucceedActual, uint256 resumeSinceTimestampActual) =
            SealableCalls.callGetResumeSinceTimestamp(sealable);

        assertEq(isCallSucceedActual, isCallSucceed, "Unexpected isCallSucceed value");
        assertEq(resumeSinceTimestampActual, resumeSinceTimestamp, "Unexpected resumeSinceTimestamp value");
    }

    function _mockSealableResumeSinceTimestampReverts(address sealable, bytes memory revertReason) internal {
        vm.mockCallRevert(sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), revertReason);
    }
}
