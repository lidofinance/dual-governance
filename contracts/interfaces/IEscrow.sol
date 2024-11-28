// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamp} from "../types/Timestamp.sol";
import {PercentD16} from "../types/PercentD16.sol";
import {Timestamp} from "../types/Timestamp.sol";

import {ETHValue} from "../types/ETHValue.sol";
import {SharesValue} from "../types/SharesValue.sol";

import {State as EscrowState} from "../libraries/EscrowState.sol";
import {UnstETHRecordStatus} from "../libraries/AssetsAccounting.sol";

interface IEscrowBase {
    struct VetoerState {
        uint256 stETHLockedShares;
        uint256 unstETHLockedShares;
        uint256 unstETHIdsCount;
        uint256 lastAssetsLockTimestamp;
    }

    /// @notice Summary of the total locked assets in the Escrow.
    /// @param stETHLockedShares The total number of stETH shares currently locked in the Escrow.
    /// @param stETHClaimedETH The total amount of ETH claimed from the stETH shares locked in the Escrow.
    /// @param unstETHUnfinalizedShares The total number of shares from unstETH NFTs that have not yet been marked as finalized.
    /// @param unstETHFinalizedETH The total amount of ETH claimable from unstETH NFTs that have been marked as finalized.
    /// TODO: Remove and use LockedUnstETHState instead
    struct LockedAssetsTotals {
        uint256 stETHLockedShares;
        uint256 stETHClaimedETH;
        uint256 unstETHUnfinalizedShares;
        uint256 unstETHFinalizedETH;
    }

    // TODO: add standalone getter
    function ESCROW_MASTER_COPY() external view returns (IEscrowBase);

    function initialize(Duration minAssetsLockDuration) external;

    function getEscrowState() external view returns (EscrowState);
    function getVetoerState(address vetoer) external view returns (VetoerState memory);
}

interface ISignallingEscrow is IEscrowBase {
    struct LockedUnstETHState {
        UnstETHRecordStatus status;
        address lockedBy;
        SharesValue shares;
        ETHValue claimableAmount;
    }

    struct SignallingEscrowState {
        PercentD16 rageQuitSupport;
        //
        ETHValue totalStETHClaimedETH;
        SharesValue totalStETHLockedShares;
        //
        ETHValue totalUnstETHFinalizedETH;
        SharesValue totalUnstETHUnfinalizedShares;
    }

    function lockStETH(uint256 amount) external returns (uint256 lockedStETHShares);
    function unlockStETH() external returns (uint256 unlockedStETHShares);

    function lockWstETH(uint256 amount) external returns (uint256 lockedStETHShares);
    function unlockWstETH() external returns (uint256 wstETHUnlocked);

    function lockUnstETH(uint256[] memory unstETHIds) external;
    function unlockUnstETH(uint256[] memory unstETHIds) external;

    function markUnstETHFinalized(uint256[] memory unstETHIds, uint256[] calldata hints) external;

    function startRageQuit(
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitEthWithdrawalsDelay
    ) external returns (IRageQuitEscrow);

    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external;

    function getRageQuitSupport() external view returns (PercentD16);
    function getMinAssetsLockDuration() external view returns (Duration);
    function getLockedUnstETHState(uint256 unstETHId) external view returns (LockedUnstETHState memory);
    function getSignallingEscrowState() external view returns (SignallingEscrowState memory);
}

interface IRageQuitEscrow is IEscrowBase {
    struct RageQuitEscrowState {
        bool isRageQuitFinalized;
        bool isWithdrawalsBatchesClosed;
        bool isRageQuitExtensionPeriodStarted;
        uint256 unclaimedUnstETHIdsCount;
        Duration rageQuitWithdrawalsDelay;
        Duration rageQuitExtensionPeriodDuration;
        Timestamp rageQuitExtensionPeriodStartedAt;
    }

    function requestNextWithdrawalsBatch(uint256 batchSize) external;

    function claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] calldata hints) external;
    function claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount) external;
    function claimUnstETH(uint256[] calldata unstETHIds, uint256[] calldata hints) external;

    function startRageQuitExtensionPeriod() external;

    function withdrawETH() external;
    function withdrawETH(uint256[] calldata unstETHIds) external;

    function isRageQuitFinalized() external view returns (bool);
    function getRageQuitEscrowState() external view returns (RageQuitEscrowState memory);
    function getNextWithdrawalBatch(uint256 limit) external view returns (uint256[] memory unstETHIds);
}
