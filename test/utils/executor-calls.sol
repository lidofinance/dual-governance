// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

// Syntax sugar for more convenient creation of ExternalCall arrays
library ExternalCallHelpers {
    // calls with explicit ExternalCall definition

    function create(ExternalCall[1] memory calls) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](1);
        for (uint256 i = 0; i < 1; ++i) {
            res[i] = calls[i];
        }
    }

    function create(ExternalCall[2] memory calls) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](2);
        for (uint256 i = 0; i < 2; ++i) {
            res[i] = calls[i];
        }
    }

    function create(ExternalCall[3] memory calls) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](3);
        for (uint256 i = 0; i < 3; ++i) {
            res[i] = calls[i];
        }
    }

    function create(ExternalCall[4] memory calls) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](4);
        for (uint256 i = 0; i < 4; ++i) {
            res[i] = calls[i];
        }
    }

    function create(ExternalCall[5] memory calls) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](5);
        for (uint256 i = 0; i < 5; ++i) {
            res[i] = calls[i];
        }
    }

    function create(ExternalCall[6] memory calls) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](6);
        for (uint256 i = 0; i < 6; ++i) {
            res[i] = calls[i];
        }
    }

    function create(ExternalCall[7] memory calls) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](7);
        for (uint256 i = 0; i < 7; ++i) {
            res[i] = calls[i];
        }
    }

    // calls with value equal to 0

    function create(
        address[1] memory targets,
        bytes[1] memory payloads
    ) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](1);
        res[0].target = targets[0];
        res[0].payload = payloads[0];
    }

    function create(
        address[2] memory targets,
        bytes[2] memory payloads
    ) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](2);
        for (uint256 i = 0; i < 2; ++i) {
            res[i].target = targets[i];
            res[i].payload = payloads[i];
        }
    }

    function create(
        address[3] memory targets,
        bytes[3] memory payloads
    ) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](3);
        for (uint256 i = 0; i < 3; ++i) {
            res[i].target = targets[i];
            res[i].payload = payloads[i];
        }
    }

    function create(
        address[4] memory targets,
        bytes[4] memory payloads
    ) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](4);
        for (uint256 i = 0; i < 4; ++i) {
            res[i].target = targets[i];
            res[i].payload = payloads[i];
        }
    }

    function create(
        address[5] memory targets,
        bytes[5] memory payloads
    ) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](5);
        for (uint256 i = 0; i < 5; ++i) {
            res[i].target = targets[i];
            res[i].payload = payloads[i];
        }
    }

    function create(
        address[6] memory targets,
        bytes[6] memory payloads
    ) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](6);
        for (uint256 i = 0; i < 6; ++i) {
            res[i].target = targets[i];
            res[i].payload = payloads[i];
        }
    }

    function create(
        address[7] memory targets,
        bytes[7] memory payloads
    ) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](7);
        for (uint256 i = 0; i < 7; ++i) {
            res[i].target = targets[i];
            res[i].payload = payloads[i];
        }
    }

    function create(
        address[10] memory targets,
        bytes[10] memory payloads
    ) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](10);
        for (uint256 i = 0; i < 10; ++i) {
            res[i].target = targets[i];
            res[i].payload = payloads[i];
        }
    }

    // same target different calls

    function create(address target, bytes memory payload) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](1);
        res[0].target = target;
        res[0].payload = payload;
    }

    function create(address target, bytes[2] memory payloads) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](2);
        for (uint256 i = 0; i < 2; ++i) {
            res[i].target = target;
            res[i].payload = payloads[i];
        }
    }

    function create(address target, bytes[3] memory payloads) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](3);
        for (uint256 i = 0; i < 3; ++i) {
            res[i].target = target;
            res[i].payload = payloads[i];
        }
    }

    function create(address target, bytes[4] memory payloads) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](4);
        for (uint256 i = 0; i < 4; ++i) {
            res[i].target = target;
            res[i].payload = payloads[i];
        }
    }

    function create(address target, bytes[5] memory payloads) internal pure returns (ExternalCall[] memory res) {
        res = new ExternalCall[](5);
        for (uint256 i = 0; i < 5; ++i) {
            res[i].target = target;
            res[i].payload = payloads[i];
        }
    }
}
