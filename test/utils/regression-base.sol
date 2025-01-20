// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestUtils} from "./test-utils.sol";

contract RegressionBase is TestUtils {
    function _setUpEnvironment() internal {
        _setUpRegressionEnvironment();
        vm.createSelectFork(vm.envString("RPC_URL"));
    }
}
