// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IExternalExecutor} from "../interfaces/IExternalExecutor.sol";

struct ExternalCall {
    address target;
    uint96 value; // ~ 7.9 billion ETH
    bytes payload;
}

library ExternalCalls {
    function execute(
        ExternalCall[] memory calls,
        IExternalExecutor executor
    ) internal returns (bytes[] memory results) {
        uint256 callsCount = calls.length;
        results = new bytes[](callsCount);
        for (uint256 i = 0; i < callsCount; ++i) {
            results[i] = executor.execute(calls[i].target, calls[i].value, calls[i].payload);
        }
    }
}
