// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PercentD16, PercentsD16, HUNDRED_PERCENT_D16} from "../types/PercentD16.sol";
import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

/// @title Dual Governance Config Library
/// @notice Provides functionality to work with the configuration of the Dual Governance mechanism
library DualGovernanceConfig {
    // ---
    // Errors
    // ---

    error InvalidSecondSealRageQuitSupport(PercentD16 secondSealRageQuitSupport);
    error InvalidRageQuitSupportRange(PercentD16 firstSealRageQuitSupport, PercentD16 secondSealRageQuitSupport);
    error InvalidRageQuitEthWithdrawalsDelayRange(
        Duration rageQuitEthWithdrawalsMinDelay, Duration rageQuitEthWithdrawalsMaxDelay
    );
    error InvalidVetoSignallingDurationRange(Duration vetoSignallingMinDuration, Duration vetoSignallingMaxDuration);
    error InvalidMinAssetsLockDuration(Duration minAssetsLockDuration);

    // ---
    // Data Types
    // ---

    /// @notice Configuration values for Dual Governance.
    /// @param firstSealRageQuitSupport The percentage of the total stETH supply that must be reached in the Signalling
    ///     Escrow to transition Dual Governance from Normal, VetoCooldown and RageQuit states to the VetoSignalling state.
    /// @param secondSealRageQuitSupport The percentage of the total stETH supply that must be reached in the
    ///     Signalling Escrow to transition Dual Governance into the RageQuit state.
    ///
    /// @param minAssetsLockDuration The minimum duration that assets must remain locked in the Signalling Escrow contract
    ///     before unlocking is permitted.
    ///
    /// @param vetoSignallingMinDuration The minimum duration of the VetoSignalling state.
    /// @param vetoSignallingMaxDuration The maximum duration of the VetoSignalling state.
    /// @param vetoSignallingMinActiveDuration The minimum duration of the VetoSignalling state before it can be exited.
    ///     Once in the VetoSignalling state, it cannot be exited sooner than `vetoSignallingMinActiveDuration`.
    /// @param vetoSignallingDeactivationMaxDuration The maximum duration of the VetoSignallingDeactivation state.
    /// @param vetoCooldownDuration The duration of the VetoCooldown state.
    ///
    /// @param rageQuitExtensionPeriodDuration The duration of the Rage Quit Extension Period.
    /// @param rageQuitEthWithdrawalsMinDelay The minimum delay for ETH withdrawals after the Rage Quit process completes.
    /// @param rageQuitEthWithdrawalsMaxDelay The maximum delay for ETH withdrawals after the Rage Quit process completes.
    /// @param rageQuitEthWithdrawalsDelayGrowth The incremental growth of the ETH withdrawal delay with each "continuous"
    ///     Rage Quit (a Rage Quit is considered continuous if, between two Rage Quits, Dual Governance has not re-entered
    ///     the Normal state).
    struct Context {
        PercentD16 firstSealRageQuitSupport;
        PercentD16 secondSealRageQuitSupport;
        //
        Duration minAssetsLockDuration;
        //
        Duration vetoSignallingMinDuration;
        Duration vetoSignallingMaxDuration;
        Duration vetoSignallingMinActiveDuration;
        Duration vetoSignallingDeactivationMaxDuration;
        Duration vetoCooldownDuration;
        //
        Duration rageQuitExtensionPeriodDuration;
        Duration rageQuitEthWithdrawalsMinDelay;
        Duration rageQuitEthWithdrawalsMaxDelay;
        Duration rageQuitEthWithdrawalsDelayGrowth;
    }

    // ---
    // Constants
    // ---

    uint256 internal constant MAX_SECOND_SEAL_RAGE_QUIT_SUPPORT = HUNDRED_PERCENT_D16;

    // ---
    // Main Functionality
    // ---

    /// @notice Validates that key configuration values are within logical ranges to prevent malfunction
    ///     of the Dual Governance system.
    /// @param self The configuration context.
    function validate(Context memory self) internal pure {
        if (self.secondSealRageQuitSupport > PercentsD16.from(MAX_SECOND_SEAL_RAGE_QUIT_SUPPORT)) {
            revert InvalidSecondSealRageQuitSupport(self.secondSealRageQuitSupport);
        }

        if (self.firstSealRageQuitSupport >= self.secondSealRageQuitSupport) {
            revert InvalidRageQuitSupportRange(self.firstSealRageQuitSupport, self.secondSealRageQuitSupport);
        }

        if (self.vetoSignallingMinDuration >= self.vetoSignallingMaxDuration) {
            revert InvalidVetoSignallingDurationRange(self.vetoSignallingMinDuration, self.vetoSignallingMaxDuration);
        }

        if (self.rageQuitEthWithdrawalsMinDelay > self.rageQuitEthWithdrawalsMaxDelay) {
            revert InvalidRageQuitEthWithdrawalsDelayRange(
                self.rageQuitEthWithdrawalsMinDelay, self.rageQuitEthWithdrawalsMaxDelay
            );
        }

        if (self.minAssetsLockDuration == Durations.ZERO) {
            revert InvalidMinAssetsLockDuration(self.minAssetsLockDuration);
        }
    }

    /// @notice Determines whether the first seal Rage Quit support threshold has been reached.
    /// @param self The configuration context.
    /// @param rageQuitSupport The current Rage Quit support level.
    /// @return bool A boolean indicating whether the Rage Quit support level reaches the first seal threshold.
    function isFirstSealRageQuitSupportReached(
        Context memory self,
        PercentD16 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport >= self.firstSealRageQuitSupport;
    }

    /// @notice Determines whether the second seal Rage Quit support threshold has been reached.
    /// @param self The configuration context.
    /// @param rageQuitSupport The current Rage Quit support level.
    /// @return bool A boolean indicating whether the Rage Quit support level reaches the second seal threshold.
    function isSecondSealRageQuitSupportReached(
        Context memory self,
        PercentD16 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport >= self.secondSealRageQuitSupport;
    }

    /// @notice Determines whether the VetoSignalling duration has passed based on the current time.
    /// @dev This check calculates the time elapsed since VetoSignalling was activated and compares it
    ///      against the calculated VetoSignalling duration based on the current Rage Quit support level.
    /// @param self The configuration context.
    /// @param vetoSignallingActivatedAt The timestamp when VetoSignalling was activated.
    /// @param rageQuitSupport The current Rage Quit support level, which influences the signalling duration.
    /// @return bool A boolean indicating whether the current time has passed the calculated VetoSignalling duration.
    function isVetoSignallingDurationPassed(
        Context memory self,
        Timestamp vetoSignallingActivatedAt,
        PercentD16 rageQuitSupport
    ) internal view returns (bool) {
        return Timestamps.now() > calcVetoSignallingDuration(self, rageQuitSupport).addTo(vetoSignallingActivatedAt);
    }

    /// @notice Determines whether the VetoSignalling reactivation duration has passed.
    /// @param self The configuration context.
    /// @param vetoSignallingReactivatedAt The timestamp when VetoSignalling was reactivated.
    /// @return bool A boolean indicating whether the minimum active duration for VetoSignalling has passed.
    function isVetoSignallingReactivationDurationPassed(
        Context memory self,
        Timestamp vetoSignallingReactivatedAt
    ) internal view returns (bool) {
        return Timestamps.now() > self.vetoSignallingMinActiveDuration.addTo(vetoSignallingReactivatedAt);
    }

    /// @notice Determines whether the maximum VetoSignallingDeactivation duration has passed.
    /// @param self The configuration context.
    /// @param vetoSignallingDeactivationEnteredAt The timestamp when the VetoSignallingDeactivation state began.
    /// @return bool A boolean indicating whether the maximum deactivation duration has passed.
    function isVetoSignallingDeactivationMaxDurationPassed(
        Context memory self,
        Timestamp vetoSignallingDeactivationEnteredAt
    ) internal view returns (bool) {
        return Timestamps.now() > self.vetoSignallingDeactivationMaxDuration.addTo(vetoSignallingDeactivationEnteredAt);
    }

    /// @notice Determines whether the VetoCooldown duration has passed.
    /// @param self The configuration context.
    /// @param vetoCooldownEnteredAt The timestamp when the VetoCooldown state was entered.
    /// @return bool A boolean indicating whether the VetoCooldown duration has passed.
    function isVetoCooldownDurationPassed(
        Context memory self,
        Timestamp vetoCooldownEnteredAt
    ) internal view returns (bool) {
        return Timestamps.now() > self.vetoCooldownDuration.addTo(vetoCooldownEnteredAt);
    }

    /// @notice Calculates the appropriate VetoSignalling duration based on the current Rage Quit support level.
    /// @dev The duration is determined by interpolating between the minimum and maximum VetoSignalling durations,
    ///      based on where the current Rage Quit support falls between the first and second seal thresholds.
    /// @param self The configuration context.
    /// @param rageQuitSupport The current Rage Quit support level.
    /// @return Duration The calculated VetoSignalling duration based on the Rage Quit support level.
    function calcVetoSignallingDuration(
        Context memory self,
        PercentD16 rageQuitSupport
    ) internal pure returns (Duration) {
        PercentD16 firstSealRageQuitSupport = self.firstSealRageQuitSupport;
        PercentD16 secondSealRageQuitSupport = self.secondSealRageQuitSupport;

        Duration vetoSignallingMinDuration = self.vetoSignallingMinDuration;
        Duration vetoSignallingMaxDuration = self.vetoSignallingMaxDuration;

        if (rageQuitSupport < firstSealRageQuitSupport) {
            return Durations.ZERO;
        }

        if (rageQuitSupport >= secondSealRageQuitSupport) {
            return vetoSignallingMaxDuration;
        }

        return vetoSignallingMinDuration
            + Durations.from(
                (rageQuitSupport - firstSealRageQuitSupport).toUint256()
                    * (vetoSignallingMaxDuration - vetoSignallingMinDuration).toSeconds()
                    / (secondSealRageQuitSupport - firstSealRageQuitSupport).toUint256()
            );
    }

    /// @notice Calculates the delay for ETH withdrawals after a Rage Quit, adjusted based on the number of continuous
    ///     Rage Quit rounds.
    /// @dev The delay grows with each Rage Quit round until reaching a maximum limit.
    /// @param self The configuration context.
    /// @param rageQuitRound The current round of Rage Quit events, used to calculate the cumulative delay.
    /// @return Duration The calculated delay for ETH withdrawals, capped at the maximum delay.
    function calcRageQuitWithdrawalsDelay(
        Context memory self,
        uint256 rageQuitRound
    ) internal pure returns (Duration) {
        uint256 rageQuitWithdrawalsDelayInSeconds = self.rageQuitEthWithdrawalsMinDelay.toSeconds()
            + rageQuitRound * self.rageQuitEthWithdrawalsDelayGrowth.toSeconds();

        return rageQuitWithdrawalsDelayInSeconds > self.rageQuitEthWithdrawalsMaxDelay.toSeconds()
            ? self.rageQuitEthWithdrawalsMaxDelay
            : Durations.from(rageQuitWithdrawalsDelayInSeconds);
    }
}
