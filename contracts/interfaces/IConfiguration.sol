// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

struct DualGovernanceConfig {
    uint256 firstSealRageQuitSupport;
    uint256 secondSealRageQuitSupport;
    // TODO: consider dynamicDelayMaxDuration
    uint256 dynamicTimelockMaxDuration;
    uint256 dynamicTimelockMinDuration;
    uint256 vetoSignallingMinActiveDuration;
    uint256 vetoSignallingDeactivationMaxDuration;
    uint256 vetoCooldownDuration;
    uint256 rageQuitExtraTimelock;
    uint256 rageQuitExtensionDelay;
    uint256 rageQuitEthClaimMinTimelock;
    uint256 rageQuitEthClaimTimelockGrowthStartSeqNumber;
    uint256[3] rageQuitEthClaimTimelockGrowthCoeffs;
}

interface IAdminExecutorConfiguration {
    function ADMIN_EXECUTOR() external view returns (address);
}

interface ITimelockConfiguration {
    function AFTER_SUBMIT_DELAY() external view returns (uint256);
    function AFTER_SCHEDULE_DELAY() external view returns (uint256);
    function EMERGENCY_GOVERNANCE() external view returns (address);
}

interface IDualGovernanceConfiguration {
    function TIE_BREAK_ACTIVATION_TIMEOUT() external view returns (uint256);

    function VETO_COOLDOWN_DURATION() external view returns (uint256);
    function VETO_SIGNALLING_MIN_ACTIVE_DURATION() external view returns (uint256);

    function VETO_SIGNALLING_DEACTIVATION_MAX_DURATION() external view returns (uint256);

    function DYNAMIC_TIMELOCK_MIN_DURATION() external view returns (uint256);
    function DYNAMIC_TIMELOCK_MAX_DURATION() external view returns (uint256);

    function FIRST_SEAL_RAGE_QUIT_SUPPORT() external view returns (uint256);
    function SECOND_SEAL_RAGE_QUIT_SUPPORT() external view returns (uint256);

    function RAGE_QUIT_EXTENSION_DELAY() external view returns (uint256);
    function RAGE_QUIT_ETH_CLAIM_MIN_TIMELOCK() external view returns (uint256);
    function RAGE_QUIT_ACCUMULATION_MAX_DURATION() external view returns (uint256);
    function RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_START_SEQ_NUMBER() external view returns (uint256);

    function RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFF_A() external view returns (uint256);
    function RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFF_B() external view returns (uint256);
    function RAGE_QUIT_ETH_CLAIM_TIMELOCK_GROWTH_COEFF_C() external view returns (uint256);

    function SIGNALLING_ESCROW_MIN_LOCK_TIME() external view returns (uint256);

    function sealableWithdrawalBlockers() external view returns (address[] memory);

    function getSignallingThresholdData()
        external
        view
        returns (
            uint256 firstSealThreshold,
            uint256 secondSealThreshold,
            uint256 signallingMinDuration,
            uint256 signallingMaxDuration
        );

    function getDualGovernanceConfig() external view returns (DualGovernanceConfig memory config);
}

interface IConfiguration is IAdminExecutorConfiguration, ITimelockConfiguration, IDualGovernanceConfiguration {}
