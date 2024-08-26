// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamp} from "../types/Timestamp.sol";
import {PercentD16} from "../types/PercentD16.sol";

interface IEscrow {
    function initialize(Duration minAssetsLockDuration) external;

    function startRageQuit(Duration rageQuitExtraTimelock, Duration rageQuitWithdrawalsTimelock) external;
    function requestNextWithdrawalsBatch(uint256 batchSize) external;
    function claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount) external;
    function claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] calldata hints) external;
    function startRageQuitExtensionDelay() external;

    function isRageQuitFinalized() external view returns (bool);
    function getRageQuitSupport() external view returns (PercentD16 rageQuitSupport);
    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external;
    function isRageQuitExtensionDelayStarted() external view returns (bool);
    function getRageQuitExtensionDelayStartedAt() external view returns (Timestamp);
}
