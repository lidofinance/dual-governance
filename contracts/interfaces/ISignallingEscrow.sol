// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ETHValue} from "../types/ETHValue.sol";
import {Duration} from "../types/Duration.sol";
import {Timestamp} from "../types/Timestamp.sol";
import {PercentD16} from "../types/PercentD16.sol";
import {SharesValue} from "../types/SharesValue.sol";
import {UnstETHRecordStatus} from "../libraries/AssetsAccounting.sol";

import {IEscrowBase} from "./IEscrowBase.sol";

interface ISignallingEscrow is IEscrowBase {
    struct VetoerDetails {
        uint256 unstETHIdsCount;
        SharesValue stETHLockedShares;
        SharesValue unstETHLockedShares;
        Timestamp lastAssetsLockTimestamp;
    }

    struct LockedUnstETHDetails {
        uint256 id;
        UnstETHRecordStatus status;
        address lockedBy;
        SharesValue shares;
        ETHValue claimableAmount;
    }

    struct SignallingEscrowDetails {
        SharesValue totalStETHLockedShares;
        ETHValue totalStETHClaimedETH;
        SharesValue totalUnstETHUnfinalizedShares;
        ETHValue totalUnstETHFinalizedETH;
    }

    function lockStETH(uint256 amount) external returns (uint256 lockedStETHShares);
    function unlockStETH() external returns (uint256 unlockedStETHShares);

    function lockWstETH(uint256 amount) external returns (uint256 lockedStETHShares);
    function unlockWstETH() external returns (uint256 wstETHUnlocked);

    function lockUnstETH(uint256[] memory unstETHIds) external;
    function unlockUnstETH(uint256[] memory unstETHIds) external;

    function markUnstETHFinalized(uint256[] memory unstETHIds, uint256[] calldata hints) external;

    function startRageQuit(Duration rageQuitExtensionPeriodDuration, Duration rageQuitEthWithdrawalsDelay) external;

    function setMinAssetsLockDuration(Duration newMinAssetsLockDuration) external;

    function getRageQuitSupport() external view returns (PercentD16);
    function getMinAssetsLockDuration() external view returns (Duration);

    function getVetoerDetails(address vetoer) external view returns (VetoerDetails memory);
    function getVetoerUnstETHIds(address vetoer) external view returns (uint256[] memory);
    function getSignallingEscrowDetails() external view returns (SignallingEscrowDetails memory);

    function getLockedUnstETHDetails(uint256[] calldata unstETHIds)
        external
        view
        returns (LockedUnstETHDetails[] memory);
}
