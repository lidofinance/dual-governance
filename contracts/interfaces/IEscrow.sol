// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {PercentD16} from "../types/PercentD16.sol";

interface IEscrow {
    function initialize(Duration minAssetsLockDuration) external;

    function startRageQuit(Duration rageQuitExtensionPeriodDuration, Duration rageQuitEthWithdrawalsDelay) external;

    function isRageQuitFinalized() external view returns (bool);
    function getRageQuitSupport() external view returns (PercentD16 rageQuitSupport);
    function getMinAssetsLockDuration() external view returns (Duration minAssetsLockDuration);
    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external;
}
