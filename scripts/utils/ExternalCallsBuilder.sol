// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {IForwarder} from "scripts/launch/interfaces/IForwarder.sol";
import {CallsScriptBuilder} from "scripts/utils/CallsScriptBuilder.sol";

library ExternalCallsBuilder {
    using CallsScriptBuilder for CallsScriptBuilder.Context;

    error InvalidExternalCallsCount(uint256 callsCount);

    struct Context {
        uint256 _addedCallsCount;
        ExternalCall[] _result;
    }

    function getResult(Context memory self) internal pure returns (ExternalCall[] memory) {
        if (self._result.length != self._addedCallsCount) {
            revert InvalidExternalCallsCount(self._result.length);
        }
        return self._result;
    }

    function create(uint256 callsCount) internal pure returns (Context memory res) {
        res._result = new ExternalCall[](callsCount);
    }

    function addCall(Context memory self, address target, bytes memory payload) internal pure {
        addCallWithValue(self, target, 0, payload);
    }

    function addCallWithValue(Context memory self, address target, uint256 value, bytes memory payload) internal pure {
        self._result[self._addedCallsCount++] = ExternalCall(target, uint96(value), payload);
    }

    function addForwardCall(
        Context memory self,
        address forwarder,
        address target,
        bytes memory payload
    ) internal pure {
        bytes memory forwardingEVMScript = CallsScriptBuilder.create(target, payload).getResult();
        addCall(self, forwarder, abi.encodeCall(IForwarder.forward, (forwardingEVMScript)));
    }
}
