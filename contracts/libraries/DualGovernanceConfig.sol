// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

struct TiebreakConfig {
    Duration tiebreakActivationTimeout;
    address[] potentialDeadlockSealables;
}

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

library DualGovernanceConfigUtils {
    function isFirstSealRageQuitSupportCrossed(
        DualGovernanceConfig memory config,
        uint256 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport > config.firstSealRageQuitSupport;
    }

    function isSecondSealRageQuitSupportCrossed(
        DualGovernanceConfig memory config,
        uint256 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport > config.secondSealRageQuitSupport;
    }

    function isDynamicTimelockMaxDurationPassed(
        DualGovernanceConfig memory config,
        Timestamp vetoSignallingActivatedAt
    ) internal view returns (bool) {
        return Timestamps.now() > config.dynamicTimelockMaxDuration.addTo(vetoSignallingActivatedAt);
    }

    function isDynamicTimelockDurationPassed(
        DualGovernanceConfig memory config,
        Timestamp vetoSignallingActivatedAt,
        uint256 rageQuitSupport
    ) internal view returns (bool) {
        Duration dynamicTimelock = calcDynamicTimelockDuration(config, rageQuitSupport);
        return Timestamps.now() > dynamicTimelock.addTo(vetoSignallingActivatedAt);
    }

    function isVetoSignallingReactivationDurationPassed(
        DualGovernanceConfig memory config,
        Timestamp vetoSignallingReactivationTime
    ) internal view returns (bool) {
        return Timestamps.now() > config.vetoSignallingMinActiveDuration.addTo(vetoSignallingReactivationTime);
    }

    function isVetoSignallingDeactivationMaxDurationPassed(
        DualGovernanceConfig memory config,
        Timestamp vetoSignallingDeactivationEnteredAt
    ) internal view returns (bool) {
        return
            Timestamps.now() > config.vetoSignallingDeactivationMaxDuration.addTo(vetoSignallingDeactivationEnteredAt);
    }

    function isVetoCooldownDurationPassed(
        DualGovernanceConfig memory config,
        Timestamp vetoCooldownEnteredAt
    ) internal view returns (bool) {
        return Timestamps.now() > config.vetoCooldownDuration.addTo(vetoCooldownEnteredAt);
    }

    function calcDynamicTimelockDuration(
        DualGovernanceConfig memory config,
        uint256 rageQuitSupport
    ) internal pure returns (Duration duration_) {
        uint256 firstSealRageQuitSupport = config.firstSealRageQuitSupport;
        uint256 secondSealRageQuitSupport = config.secondSealRageQuitSupport;
        Duration dynamicTimelockMinDuration = config.dynamicTimelockMinDuration;
        Duration dynamicTimelockMaxDuration = config.dynamicTimelockMaxDuration;

        if (rageQuitSupport < firstSealRageQuitSupport) {
            return Durations.ZERO;
        }

        if (rageQuitSupport >= secondSealRageQuitSupport) {
            return dynamicTimelockMaxDuration;
        }

        duration_ = dynamicTimelockMinDuration
            + Durations.from(
                (rageQuitSupport - firstSealRageQuitSupport)
                    * (dynamicTimelockMaxDuration - dynamicTimelockMinDuration).toSeconds()
                    / (secondSealRageQuitSupport - firstSealRageQuitSupport)
            );
    }

    function calcRageQuitWithdrawalsTimelock(
        DualGovernanceConfig memory config,
        uint256 rageQuitRound
    ) internal pure returns (Duration) {
        if (rageQuitRound < config.rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber) {
            return config.rageQuitEthWithdrawalsMinTimelock;
        }
        return config.rageQuitEthWithdrawalsMinTimelock
            + Durations.from(
                (
                    config.rageQuitEthWithdrawalsTimelockGrowthCoeffs[0] * rageQuitRound * rageQuitRound
                        + config.rageQuitEthWithdrawalsTimelockGrowthCoeffs[1] * rageQuitRound
                        + config.rageQuitEthWithdrawalsTimelockGrowthCoeffs[2]
                ) / 10 ** 18
            ); // TODO: rewrite in a prettier way
    }
}
