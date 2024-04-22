// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IConfiguration, DualGovernanceConfig} from "./interfaces/IConfiguration.sol";

uint256 constant PERCENT = 10 ** 16;

contract Configuration is IConfiguration {
    error MaxSealablesLimitOverflow(uint256 count, uint256 limit);

    // ---
    // Dual Governance State Properties
    // ---
    uint256 public immutable FIRST_SEAL_RAGE_QUIT_SUPPORT = 3 * PERCENT;
    uint256 public immutable SECOND_SEAL_RAGE_QUIT_SUPPORT = 15 * PERCENT;

    uint256 public immutable DYNAMIC_TIMELOCK_MIN_DURATION = 3 days;
    uint256 public immutable DYNAMIC_TIMELOCK_MAX_DURATION = 30 days;

    uint256 public immutable VETO_SIGNALLING_MIN_ACTIVE_DURATION = 5 hours;
    uint256 public immutable VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = 5 days;
    uint256 public immutable RAGE_QUIT_ACCUMULATION_MAX_DURATION = 3 days;

    uint256 public immutable VETO_COOLDOWN_DURATION = 4 days;

    uint256 public immutable RAGE_QUIT_EXTENSION_DELAY = 7 days;
    uint256 public immutable RAGE_QUIT_ETH_CLAIM_MIN_TIMELOCK = 60 days;
    uint256 public immutable RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_START_SEQ_NUMBER = 2;

    uint256 public immutable RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFF_A = 0;
    uint256 public immutable RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFF_B = 0;
    uint256 public immutable RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFF_C = 0;
    // ---

    address public immutable ADMIN_EXECUTOR;
    address public immutable EMERGENCY_GOVERNANCE;

    uint256 public immutable AFTER_SUBMIT_DELAY = 3 days;
    uint256 public immutable AFTER_SCHEDULE_DELAY = 2 days;

    uint256 public immutable SIGNALLING_ESCROW_MIN_LOCK_TIME = 5 hours;

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
            uint256 firstSealRageQuitSupport,
            uint256 secondSealRageQuitSupport,
            uint256 dynamicTimelockMinDuration,
            uint256 dynamicTimelockMaxDuration
        )
    {
        firstSealRageQuitSupport = FIRST_SEAL_RAGE_QUIT_SUPPORT;
        secondSealRageQuitSupport = SECOND_SEAL_RAGE_QUIT_SUPPORT;
        dynamicTimelockMinDuration = DYNAMIC_TIMELOCK_MIN_DURATION;
        dynamicTimelockMaxDuration = DYNAMIC_TIMELOCK_MAX_DURATION;
    }

    function getDualGovernanceConfig() external view returns (DualGovernanceConfig memory config) {
        config.firstSealRageQuitSupport = FIRST_SEAL_RAGE_QUIT_SUPPORT;
        config.secondSealRageQuitSupport = SECOND_SEAL_RAGE_QUIT_SUPPORT;
        config.dynamicTimelockMinDuration = DYNAMIC_TIMELOCK_MIN_DURATION;
        config.dynamicTimelockMaxDuration = DYNAMIC_TIMELOCK_MAX_DURATION;
        config.vetoSignallingMinActiveDuration = VETO_SIGNALLING_MIN_ACTIVE_DURATION;
        config.vetoSignallingDeactivationMaxDuration = VETO_SIGNALLING_DEACTIVATION_MAX_DURATION;
        config.vetoCooldownDuration = VETO_COOLDOWN_DURATION;
        config.rageQuitExtensionDelay = RAGE_QUIT_EXTENSION_DELAY;
        config.rageQuitEthClaimMinTimelock = RAGE_QUIT_ETH_CLAIM_MIN_TIMELOCK;
        config.rageQuitEthClaimTimelockGrowthStartSeqNumber = RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_START_SEQ_NUMBER;
        config.rageQuitEthClaimTimelockGrowthCoeffs = [
            RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFF_A,
            RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFF_B,
            RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFF_C
        ];
    }
}
