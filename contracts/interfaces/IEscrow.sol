// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Duration} from "../types/Duration.sol";

interface IEscrow {
    function initialize(address dualGovernance) external;

    function startRageQuit(Duration rageQuitExtraTimelock, Duration rageQuitWithdrawalsTimelock) external;

    function MASTER_COPY() external view returns (address);
    function isRageQuitFinalized() external view returns (bool);
    function getRageQuitSupport() external view returns (uint256 rageQuitSupport);
}
