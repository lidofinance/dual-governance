// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {PercentD16} from "../types/PercentD16.sol";
import {Timestamp} from "../types/Timestamp.sol";

/// @notice Summary of the total locked assets in the Escrow.
/// @param stETHLockedShares The total number of stETH shares currently locked in the Escrow.
/// @param stETHClaimedETH The total amount of ETH claimed from the stETH shares locked in the Escrow.
/// @param unstETHUnfinalizedShares The total number of shares from unstETH NFTs that have not yet been marked as finalized.
/// @param unstETHFinalizedETH The total amount of ETH claimable from unstETH NFTs that have been marked as finalized.
struct LockedAssetsTotals {
    uint256 stETHLockedShares;
    uint256 stETHClaimedETH;
    uint256 unstETHUnfinalizedShares;
    uint256 unstETHFinalizedETH;
}

/// @notice Summary of the assets locked in the Escrow by a specific vetoer.
/// @param stETHLockedShares The total number of stETH shares currently locked in the Escrow by the vetoer.
/// @param unstETHLockedShares The total number of unstETH shares currently locked in the Escrow by the vetoer.
/// @param unstETHIdsCount The total number of unstETH NFTs locked in the Escrow by the vetoer.
/// @param lastAssetsLockTimestamp The timestamp of the last time the vetoer locked stETH, wstETH, or unstETH in the Escrow.
struct VetoerState {
    uint256 stETHLockedShares;
    uint256 unstETHLockedShares;
    uint256 unstETHIdsCount;
    uint256 lastAssetsLockTimestamp;
}

interface IEscrow {
    function initialize(Duration minAssetsLockDuration) external;

    function lockStETH(uint256 amount) external returns (uint256 lockedStETHShares);
    function unlockStETH() external returns (uint256 unlockedStETHShares);
    function lockWstETH(uint256 amount) external returns (uint256 lockedStETHShares);
    function unlockWstETH() external returns (uint256 unlockedStETHShares);
    function lockUnstETH(uint256[] memory unstETHIds) external;
    function unlockUnstETH(uint256[] memory unstETHIds) external;
    function markUnstETHFinalized(uint256[] memory unstETHIds, uint256[] calldata hints) external;

    function startRageQuit(Duration rageQuitExtensionPeriodDuration, Duration rageQuitEthWithdrawalsDelay) external;

    function requestNextWithdrawalsBatch(uint256 batchSize) external;

    function claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] calldata hints) external;
    function claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount) external;

    function startRageQuitExtensionPeriod() external;
    function claimUnstETH(uint256[] calldata unstETHIds, uint256[] calldata hints) external;

    function withdrawETH() external;
    function withdrawETH(uint256[] calldata unstETHIds) external;

    function getLockedAssetsTotals() external view returns (LockedAssetsTotals memory totals);
    function getVetoerState(address vetoer) external view returns (VetoerState memory state);
    function getUnclaimedUnstETHIdsCount() external view returns (uint256);
    function getNextWithdrawalBatch(uint256 limit) external view returns (uint256[] memory unstETHIds);
    function isWithdrawalsBatchesFinalized() external view returns (bool);
    function isRageQuitExtensionPeriodStarted() external view returns (bool);
    function getRageQuitExtensionPeriodStartedAt() external view returns (Timestamp);

    function isRageQuitFinalized() external view returns (bool);
    function getRageQuitSupport() external view returns (PercentD16 rageQuitSupport);
    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external;
}
