// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IConfiguration} from "./interfaces/IConfiguration.sol";

uint256 constant PERCENT = 10 ** 16;

contract Configuration is IConfiguration {
    error MaxSealablesLimitOverflow(uint256 count, uint256 limit);

    address public immutable ADMIN_EXECUTOR;
    address public immutable EMERGENCY_GOVERNANCE;

    uint256 public immutable AFTER_SUBMIT_DELAY = 3 days;
    uint256 public immutable AFTER_SCHEDULE_DELAY = 2 days;

    uint256 public immutable RAGE_QUIT_ETH_WITHDRAWAL_TIMELOCK = 30 days;

    uint256 public immutable SIGNALING_COOLDOWN_DURATION = 4 days;
    uint256 public immutable SIGNALLING_DEACTIVATION_DURATION = 5 days;
    uint256 public immutable SIGNALLING_MIN_PROPOSAL_REVIEW_DURATION = 30 days;

    uint256 public immutable SIGNALING_MIN_DURATION = 3 days;
    uint256 public immutable SIGNALING_MAX_DURATION = 30 days;

    uint256 public immutable FIRST_SEAL_THRESHOLD = 3 * PERCENT;
    uint256 public immutable SECOND_SEAL_THRESHOLD = 15 * PERCENT;

    uint256 public immutable TIE_BREAK_ACTIVATION_TIMEOUT = 365 days;

    // Sealables Array Representation
    uint256 private immutable MAX_SELABLES_COUNT = 5;

    uint256 private immutable SEALABLES_COUNT;

    address private immutable SEALABLE_0;
    address private immutable SEALABLE_1;
    address private immutable SEALABLE_2;
    address private immutable SEALABLE_3;
    address private immutable SEALABLE_4;

    constructor(address adminExecutor, address emergencyGovernance, address[] memory sealableWithdrawalBlockers_) {
        ADMIN_EXECUTOR = adminExecutor;
        EMERGENCY_GOVERNANCE = emergencyGovernance;

        if (sealableWithdrawalBlockers_.length > MAX_SELABLES_COUNT) {
            revert MaxSealablesLimitOverflow(sealableWithdrawalBlockers_.length, MAX_SELABLES_COUNT);
        }

        SEALABLES_COUNT = sealableWithdrawalBlockers_.length;
        if (SEALABLES_COUNT > 0) SEALABLE_0 = sealableWithdrawalBlockers_[0];
        if (SEALABLES_COUNT > 1) SEALABLE_1 = sealableWithdrawalBlockers_[1];
        if (SEALABLES_COUNT > 2) SEALABLE_2 = sealableWithdrawalBlockers_[2];
        if (SEALABLES_COUNT > 3) SEALABLE_3 = sealableWithdrawalBlockers_[3];
        if (SEALABLES_COUNT > 4) SEALABLE_4 = sealableWithdrawalBlockers_[4];
    }

    function sealableWithdrawalBlockers() external view returns (address[] memory sealableWithdrawalBlockers_) {
        sealableWithdrawalBlockers_ = new address[](SEALABLES_COUNT);
        if (SEALABLES_COUNT > 0) sealableWithdrawalBlockers_[0] = SEALABLE_0;
        if (SEALABLES_COUNT > 1) sealableWithdrawalBlockers_[1] = SEALABLE_1;
        if (SEALABLES_COUNT > 2) sealableWithdrawalBlockers_[2] = SEALABLE_2;
        if (SEALABLES_COUNT > 3) sealableWithdrawalBlockers_[3] = SEALABLE_3;
        if (SEALABLES_COUNT > 4) sealableWithdrawalBlockers_[4] = SEALABLE_4;
    }

    function getSignallingThresholdData()
        external
        view
        returns (
            uint256 firstSealThreshold,
            uint256 secondSealThreshold,
            uint256 signallingMinDuration,
            uint256 signallingMaxDuration
        )
    {
        firstSealThreshold = FIRST_SEAL_THRESHOLD;
        secondSealThreshold = SECOND_SEAL_THRESHOLD;
        signallingMinDuration = SIGNALING_MIN_DURATION;
        signallingMaxDuration = SIGNALING_MAX_DURATION;
    }
}
