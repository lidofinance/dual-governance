// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";

import {State} from "../libraries/EscrowState.sol";

interface IEscrowBase {
    function ESCROW_MASTER_COPY() external view returns (IEscrowBase);

    function initialize(Duration minAssetsLockDuration) external;

    function getEscrowState() external view returns (State);
}
