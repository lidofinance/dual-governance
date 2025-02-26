// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "./types/Duration.sol";
import {PercentD16} from "./types/PercentD16.sol";

import {IDualGovernanceConfigProvider} from "./interfaces/IDualGovernanceConfigProvider.sol";

import {DualGovernanceConfig} from "./libraries/DualGovernanceConfig.sol";

/// @title Immutable Dual Governance Config Provider
/// @notice Provides configuration values for the Dual Governance system in a gas-efficient way using immutable
///     variables to store values.
contract ImmutableDualGovernanceConfigProvider is IDualGovernanceConfigProvider {
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    // ---
    // Immutable Variables
    // ---

    /// @notice The percentage of the total stETH supply that must be reached in the Signalling Escrow to transition
    ///     Dual Governance from the Normal, VetoCooldown and RageQuit state to the VetoSignalling state.
    PercentD16 public immutable FIRST_SEAL_RAGE_QUIT_SUPPORT;

    /// @notice The percentage of the total stETH supply that must be reached in the Signalling Escrow to transition
    ///     Dual Governance into the RageQuit state.
    PercentD16 public immutable SECOND_SEAL_RAGE_QUIT_SUPPORT;

    /// @notice The minimum duration that assets must remain locked in the Signalling Escrow contract before unlocking
    ///     is permitted.
    Duration public immutable MIN_ASSETS_LOCK_DURATION;

    /// @notice The minimum duration of the VetoSignalling state.
    Duration public immutable VETO_SIGNALLING_MIN_DURATION;

    /// @notice The maximum duration of the VetoSignalling state.
    Duration public immutable VETO_SIGNALLING_MAX_DURATION;

    /// @notice The minimum duration of the VetoSignalling state before it can be exited. Once in the VetoSignalling
    ///     state, it cannot be exited sooner than `vetoSignallingMinActiveDuration`.
    Duration public immutable VETO_SIGNALLING_MIN_ACTIVE_DURATION;

    /// @notice The maximum duration of the VetoSignallingDeactivation state.
    Duration public immutable VETO_SIGNALLING_DEACTIVATION_MAX_DURATION;

    /// @notice The duration of the VetoCooldown state.
    Duration public immutable VETO_COOLDOWN_DURATION;

    /// @notice The duration of the Rage Quit Extension Period.
    Duration public immutable RAGE_QUIT_EXTENSION_PERIOD_DURATION;

    /// @notice The minimum delay for ETH withdrawals after the Rage Quit process completes.
    Duration public immutable RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY;

    /// @notice The maximum delay for ETH withdrawals after the Rage Quit process completes.
    Duration public immutable RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY;

    /// @notice The incremental growth of the ETH withdrawal delay with each "continuous" Rage Quit (a Rage Quit is
    ///     considered continuous if, between two Rage Quits, Dual Governance has not re-entered
    ///     the Normal state).
    Duration public immutable RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH;

    // ---
    // Constructor
    // ---

    /// @notice Initializes the Dual Governance Configuration Provider with parameters, validating that key configuration
    ///     values are within logical ranges to prevent malfunction of the Dual Governance system.
    /// @param dualGovernanceConfig The configuration struct containing all governance parameters.
    constructor(DualGovernanceConfig.Context memory dualGovernanceConfig) {
        dualGovernanceConfig.validate();

        FIRST_SEAL_RAGE_QUIT_SUPPORT = dualGovernanceConfig.firstSealRageQuitSupport;
        SECOND_SEAL_RAGE_QUIT_SUPPORT = dualGovernanceConfig.secondSealRageQuitSupport;

        MIN_ASSETS_LOCK_DURATION = dualGovernanceConfig.minAssetsLockDuration;
        VETO_SIGNALLING_MIN_DURATION = dualGovernanceConfig.vetoSignallingMinDuration;
        VETO_SIGNALLING_MAX_DURATION = dualGovernanceConfig.vetoSignallingMaxDuration;

        VETO_SIGNALLING_MIN_ACTIVE_DURATION = dualGovernanceConfig.vetoSignallingMinActiveDuration;
        VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = dualGovernanceConfig.vetoSignallingDeactivationMaxDuration;

        VETO_COOLDOWN_DURATION = dualGovernanceConfig.vetoCooldownDuration;

        RAGE_QUIT_EXTENSION_PERIOD_DURATION = dualGovernanceConfig.rageQuitExtensionPeriodDuration;
        RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY = dualGovernanceConfig.rageQuitEthWithdrawalsMinDelay;
        RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY = dualGovernanceConfig.rageQuitEthWithdrawalsMaxDelay;
        RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH = dualGovernanceConfig.rageQuitEthWithdrawalsDelayGrowth;
    }

    // ---
    // Getters
    // ---

    /// @notice Returns the entire configuration for the Dual Governance system.
    /// @return config A `DualGovernanceConfig.Context` struct containing all governance parameters.
    function getDualGovernanceConfig() external view returns (DualGovernanceConfig.Context memory config) {
        config.firstSealRageQuitSupport = FIRST_SEAL_RAGE_QUIT_SUPPORT;
        config.secondSealRageQuitSupport = SECOND_SEAL_RAGE_QUIT_SUPPORT;

        config.minAssetsLockDuration = MIN_ASSETS_LOCK_DURATION;
        config.vetoSignallingMinDuration = VETO_SIGNALLING_MIN_DURATION;
        config.vetoSignallingMaxDuration = VETO_SIGNALLING_MAX_DURATION;
        config.vetoSignallingMinActiveDuration = VETO_SIGNALLING_MIN_ACTIVE_DURATION;
        config.vetoSignallingDeactivationMaxDuration = VETO_SIGNALLING_DEACTIVATION_MAX_DURATION;

        config.vetoCooldownDuration = VETO_COOLDOWN_DURATION;

        config.rageQuitExtensionPeriodDuration = RAGE_QUIT_EXTENSION_PERIOD_DURATION;
        config.rageQuitEthWithdrawalsMinDelay = RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY;
        config.rageQuitEthWithdrawalsMaxDelay = RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY;
        config.rageQuitEthWithdrawalsDelayGrowth = RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH;
    }
}
