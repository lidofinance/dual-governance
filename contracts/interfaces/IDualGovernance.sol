// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGovernance} from "./ITimelock.sol";

interface IDualGovernance is IGovernance {
    function activateNextState() external;
}
