// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library EvmScriptUtils {
    struct EvmScriptCall {
        address target;
        bytes data;
    }

    function encodeEvmCallScript(address target, bytes memory data) internal pure returns (bytes memory) {
        EvmScriptCall[] memory calls = new EvmScriptCall[](1);
        calls[0] = EvmScriptCall(target, data);
        return encodeEvmCallScript(calls);
    }

    function encodeEvmCallScript(EvmScriptCall[] memory calls) internal pure returns (bytes memory) {
        bytes memory script = new bytes(4);
        script[3] = 0x01;

        for (uint256 i = 0; i < calls.length; ++i) {
            EvmScriptCall memory call = calls[i];
            script = bytes.concat(script, bytes20(call.target), bytes4(uint32(call.data.length)), call.data);
        }

        return script;
    }
}
