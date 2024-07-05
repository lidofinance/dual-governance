// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Duration} from "../types/Duration.sol";

struct DualGovernanceConfig {
    uint256 firstSealRageQuitSupport;
    uint256 secondSealRageQuitSupport;
    Duration dynamicTimelockMaxDuration;
    Duration dynamicTimelockMinDuration;
    Duration vetoSignallingMinActiveDuration;
    Duration vetoSignallingDeactivationMaxDuration;
    Duration vetoCooldownDuration;
    Duration rageQuitExtraTimelock;
    Duration rageQuitExtensionDelay;
    Duration rageQuitEthWithdrawalsMinTimelock;
    uint256 rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber;
    uint256[3] rageQuitEthWithdrawalsTimelockGrowthCoeffs;
}

interface IEscrowConfigration {
    function MIN_WITHDRAWALS_BATCH_SIZE() external view returns (uint256);
    function MAX_WITHDRAWALS_BATCH_SIZE() external view returns (uint256);
    function SIGNALLING_ESCROW_MIN_LOCK_TIME() external view returns (Duration);
}

interface IAdminExecutorConfiguration {
    function ADMIN_EXECUTOR() external view returns (address);
}

interface ITimelockConfiguration {
    function AFTER_SUBMIT_DELAY() external view returns (Duration);
    function AFTER_SCHEDULE_DELAY() external view returns (Duration);
    function EMERGENCY_GOVERNANCE() external view returns (address);
}

interface IDualGovernanceConfiguration {
    function TIE_BREAK_ACTIVATION_TIMEOUT() external view returns (Duration);

    function VETO_COOLDOWN_DURATION() external view returns (Duration);
    function VETO_SIGNALLING_MIN_ACTIVE_DURATION() external view returns (Duration);

    function VETO_SIGNALLING_DEACTIVATION_MAX_DURATION() external view returns (Duration);

    function DYNAMIC_TIMELOCK_MIN_DURATION() external view returns (Duration);
    function DYNAMIC_TIMELOCK_MAX_DURATION() external view returns (Duration);

    function FIRST_SEAL_RAGE_QUIT_SUPPORT() external view returns (uint256);
    function SECOND_SEAL_RAGE_QUIT_SUPPORT() external view returns (uint256);

    function RAGE_QUIT_EXTENSION_DELAY() external view returns (Duration);
    function RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK() external view returns (Duration);
    function RAGE_QUIT_ACCUMULATION_MAX_DURATION() external view returns (Duration);
    function RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER() external view returns (uint256);

    function RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_A() external view returns (uint256);
    function RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_B() external view returns (uint256);
    function RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_C() external view returns (uint256);

    function sealableWithdrawalBlockers() external view returns (address[] memory);

    function getSignallingThresholdData()
        external
        view
        returns (
            uint256 firstSealThreshold,
            uint256 secondSealThreshold,
            Duration signallingMinDuration,
            Duration signallingMaxDuration
        );

    function getDualGovernanceConfig() external view returns (DualGovernanceConfig memory config);
}

interface IConfiguration is
    IEscrowConfigration,
    ITimelockConfiguration,
    IAdminExecutorConfiguration,
    IDualGovernanceConfiguration
{}
