// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestUtils} from "./test-utils.sol";

import {Random} from "../utils/random.sol";
import {LidoUtils} from "../utils/lido-utils.sol";

uint256 constant FORK_BLOCK_NUMBER = 20218312;

contract ScenarioTestBlueprint is TestUtils {
    using LidoUtils for LidoUtils.Context;

    function _setUpEnvironment() internal {
        _setUpScenarioEnvironment(Random.create(block.timestamp));
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(FORK_BLOCK_NUMBER);
        _lido.removeStakingLimit();
    }
}
