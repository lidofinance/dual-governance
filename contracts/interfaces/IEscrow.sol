// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";

interface IEscrow {
    function initialize(Duration minAssetsLockDuration) external;

    function startRageQuit(Duration rageQuitExtraTimelock, Duration rageQuitWithdrawalsTimelock) external;

    function isRageQuitFinalized() external view returns (bool);
    function getRageQuitSupport() external view returns (uint256 rageQuitSupport);
    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external;
}
