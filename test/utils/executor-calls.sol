// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutorCall} from "contracts/libraries/ScheduledCalls.sol";

// Syntax sugar for more convenient creation of ExecutorCall arrays
library ExecutorCallHelpers {
    // calls with explicit ExecutorCall definition

    function create(ExecutorCall[1] memory calls) internal pure returns (ExecutorCall[] memory res) {
        res = new ExecutorCall[](1);
        for (uint256 i = 0; i < 1; ++i) {
            res[i] = calls[i];
        }
    }

    function create(ExecutorCall[2] memory calls) internal pure returns (ExecutorCall[] memory res) {
        res = new ExecutorCall[](2);
        for (uint256 i = 0; i < 2; ++i) {
            res[i] = calls[i];
        }
    }

    function create(ExecutorCall[3] memory calls) internal pure returns (ExecutorCall[] memory res) {
        res = new ExecutorCall[](2);
        for (uint256 i = 0; i < 2; ++i) {
            res[i] = calls[i];
        }
    }

    // calls with value equal to 0

    function create(
        address[1] memory targets,
        bytes[1] memory payloads
    ) internal pure returns (ExecutorCall[] memory res) {
        res = new ExecutorCall[](1);
        res[0].target = targets[0];
        res[0].payload = payloads[0];
    }

    function create(
        address[2] memory targets,
        bytes[2] memory payloads
    ) internal pure returns (ExecutorCall[] memory res) {
        res = new ExecutorCall[](2);
        for (uint256 i = 0; i < 2; ++i) {
            res[i].target = targets[i];
            res[i].payload = payloads[i];
        }
    }

    function create(
        address[3] memory targets,
        bytes[3] memory payloads
    ) internal pure returns (ExecutorCall[] memory res) {
        res = new ExecutorCall[](3);
        for (uint256 i = 0; i < 3; ++i) {
            res[i].target = targets[i];
            res[i].payload = payloads[i];
        }
    }

    // same target different calls

    function create(address target, bytes memory payload) internal pure returns (ExecutorCall[] memory res) {
        res = new ExecutorCall[](1);
        res[0].target = target;
        res[0].payload = payload;
    }

    function create(address target, bytes[2] memory payloads) internal pure returns (ExecutorCall[] memory res) {
        res = new ExecutorCall[](2);
        for (uint256 i = 0; i < 2; ++i) {
            res[i].target = target;
            res[i].payload = payloads[i];
        }
    }

    function create(address target, bytes[3] memory payloads) internal pure returns (ExecutorCall[] memory res) {
        res = new ExecutorCall[](3);
        for (uint256 i = 0; i < 3; ++i) {
            res[i].target = target;
            res[i].payload = payloads[i];
        }
    }
}
