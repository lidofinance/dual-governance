// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGovernance} from "./IGovernance.sol";
import {ITiebreaker} from "./ITiebreaker.sol";

interface IDualGovernance is IGovernance, ITiebreaker {
    function activateNextState() external;

    function resealSealable(address sealables) external;
}
