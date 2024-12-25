// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdError} from "forge-std/StdError.sol";
import {ISealable, SealableCalls} from "contracts/libraries/SealableCalls.sol";

import {UnitTest} from "test/utils/unit-test.sol";

uint256 constant BLOCK_GAS_LIMIT = 30_000_000;

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

    // ---
    // Test False Positive Results On Precompiles
    // ---

    function test_callGetResumeSinceTimestamp_IsCallSucceed_FalsePositiveResult_On_SHA256_Precompile() external {
        _assertGetResumeSinceTimestampCallResult({
            sealable: address(0x2),
            isCallSucceed: true,
            resumeSinceTimestamp: 0xc61a1ce4443e07760aea88e1ac096cb3006c1c4284ade7873025b96c2010e1c8
        });
    }

    function test_callGetResumeSinceTimestamp_IsCallSucceed_FalsePositiveResult_On_RIPEMD160_Precompile() external {
        _assertGetResumeSinceTimestampCallResult({
            sealable: address(0x3),
            isCallSucceed: true,
            resumeSinceTimestamp: 0x00000000000000000000000075b4744a1c0e92713946840b9adc0cb967652b9c
        });
    }

    // ---
    // Other Precompile Calls Are Not Successful
    // ---

    function test_callGetResumeSinceTimestamp_IsCallSucceed_CorrectResult_On_Other_Precompiles() external {
        for (uint160 i = 1; i < 12; ++i) {
            // Skip SHA-256 and RIPEMD-160 precompiles which lead to false positive results
            if (i == 0x2 || i == 0x3) continue;
            _assertGetResumeSinceTimestampCallResult({
                sealable: address(i),
                isCallSucceed: false,
                resumeSinceTimestamp: 0
            });
        }
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
        // Limit the maximum gas cost for the call to mimic mainnet behavior
         this.external__getResumeSinceTimestampCall{gas: BLOCK_GAS_LIMIT}(sealable);

        assertEq(isCallSucceedActual, isCallSucceed, "Unexpected isCallSucceed value");
        assertEq(resumeSinceTimestampActual, resumeSinceTimestamp, "Unexpected resumeSinceTimestamp value");
    }

    function _mockSealableResumeSinceTimestampReverts(address sealable, bytes memory revertReason) internal {
        vm.mockCallRevert(sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), revertReason);
    }

    function external__getResumeSinceTimestampCall(address sealable) external returns (bool, uint256) {
        return SealableCalls.callGetResumeSinceTimestamp(sealable);
    }
}
