// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";

struct EscrowConfigState {
    uint256 minWithdrawalsBatchSize;
    uint256 maxWithdrawalsBatchSize;
    Duration signallingEscrowMinLockTime;
}

interface IEscrowConfig {
    function MIN_WITHDRAWALS_BATCH_SIZE() external view returns (uint256);
    function MAX_WITHDRAWALS_BATCH_SIZE() external view returns (uint256);
    function SIGNALLING_ESCROW_MIN_LOCK_TIME() external view returns (Duration);
}

contract EscrowConfig is IEscrowConfig {
    uint256 public immutable MIN_WITHDRAWALS_BATCH_SIZE;

    uint256 public immutable MAX_WITHDRAWALS_BATCH_SIZE;

    Duration public immutable SIGNALLING_ESCROW_MIN_LOCK_TIME;

    constructor(EscrowConfigState memory input) {
        MIN_WITHDRAWALS_BATCH_SIZE = input.minWithdrawalsBatchSize;
        MAX_WITHDRAWALS_BATCH_SIZE = input.maxWithdrawalsBatchSize;
        SIGNALLING_ESCROW_MIN_LOCK_TIME = input.signallingEscrowMinLockTime;
    }
}
