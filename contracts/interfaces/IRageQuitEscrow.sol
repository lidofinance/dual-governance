// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamp} from "../types/Timestamp.sol";

import {IEscrowBase} from "./IEscrowBase.sol";

interface IRageQuitEscrow is IEscrowBase {
    struct RageQuitEscrowDetails {
        Duration rageQuitEthWithdrawalsDelay;
        Duration rageQuitExtensionPeriodDuration;
        Timestamp rageQuitExtensionPeriodStartedAt;
        bool isRageQuitExtensionPeriodStarted;
    }

    function requestNextWithdrawalsBatch(uint256 batchSize) external;

    function claimNextWithdrawalsBatch(uint256 fromUnstETHId, uint256[] calldata hints) external;
    function claimNextWithdrawalsBatch(uint256 maxUnstETHIdsCount) external;
    function claimUnstETH(uint256[] calldata unstETHIds, uint256[] calldata hints) external;

    function startRageQuitExtensionPeriod() external;

    function withdrawETH() external;
    function withdrawETH(uint256[] calldata unstETHIds) external;

    function isRageQuitFinalized() external view returns (bool);
    function getNextWithdrawalBatch(uint256 limit) external view returns (uint256[] memory unstETHIds);
    function isWithdrawalsBatchesClosed() external view returns (bool);
    function getUnclaimedUnstETHIdsCount() external view returns (uint256);
    function getRageQuitEscrowDetails() external view returns (RageQuitEscrowDetails memory);
}
