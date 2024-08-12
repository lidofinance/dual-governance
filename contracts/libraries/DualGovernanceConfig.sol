// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PercentD16} from "../types/PercentD16.sol";
import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

library DualGovernanceConfig {
    struct Context {
        PercentD16 firstSealRageQuitSupport;
        PercentD16 secondSealRageQuitSupport;
        Duration minAssetsLockDuration;
        Duration dynamicTimelockMinDuration;
        Duration dynamicTimelockMaxDuration;
        Duration vetoSignallingMinActiveDuration;
        Duration vetoSignallingDeactivationMaxDuration;
        Duration vetoCooldownDuration;
        Duration rageQuitExtensionDelay;
        Duration rageQuitEthWithdrawalsMinTimelock;
        uint256 rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber;
        uint256[3] rageQuitEthWithdrawalsTimelockGrowthCoeffs;
    }

    function isFirstSealRageQuitSupportCrossed(
        Context memory self,
        PercentD16 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport > self.firstSealRageQuitSupport;
    }

    function isSecondSealRageQuitSupportCrossed(
        Context memory self,
        PercentD16 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport > self.secondSealRageQuitSupport;
    }

    function isDynamicTimelockMaxDurationPassed(
        Context memory self,
        Timestamp vetoSignallingActivatedAt
    ) internal view returns (bool) {
        return Timestamps.now() > self.dynamicTimelockMaxDuration.addTo(vetoSignallingActivatedAt);
    }

    function isDynamicTimelockDurationPassed(
        Context memory self,
        Timestamp vetoSignallingActivatedAt,
        PercentD16 rageQuitSupport
    ) internal view returns (bool) {
        return Timestamps.now() > calcDynamicDelayDuration(self, rageQuitSupport).addTo(vetoSignallingActivatedAt);
    }

    function isVetoSignallingReactivationDurationPassed(
        Context memory self,
        Timestamp vetoSignallingReactivationTime
    ) internal view returns (bool) {
        return Timestamps.now() > self.vetoSignallingMinActiveDuration.addTo(vetoSignallingReactivationTime);
    }

    function isVetoSignallingDeactivationMaxDurationPassed(
        Context memory self,
        Timestamp vetoSignallingDeactivationEnteredAt
    ) internal view returns (bool) {
        return Timestamps.now() > self.vetoSignallingDeactivationMaxDuration.addTo(vetoSignallingDeactivationEnteredAt);
    }

    function isVetoCooldownDurationPassed(
        Context memory self,
        Timestamp vetoCooldownEnteredAt
    ) internal view returns (bool) {
        return Timestamps.now() > self.vetoCooldownDuration.addTo(vetoCooldownEnteredAt);
    }

    function calcDynamicDelayDuration(
        Context memory self,
        PercentD16 rageQuitSupport
    ) internal pure returns (Duration duration_) {
        PercentD16 firstSealRageQuitSupport = self.firstSealRageQuitSupport;
        PercentD16 secondSealRageQuitSupport = self.secondSealRageQuitSupport;

        Duration dynamicTimelockMinDuration = self.dynamicTimelockMinDuration;
        Duration dynamicTimelockMaxDuration = self.dynamicTimelockMaxDuration;

        if (rageQuitSupport <= firstSealRageQuitSupport) {
            return Durations.ZERO;
        }

        if (rageQuitSupport >= secondSealRageQuitSupport) {
            return dynamicTimelockMaxDuration;
        }

        duration_ = dynamicTimelockMinDuration
            + Durations.from(
                PercentD16.unwrap(rageQuitSupport - firstSealRageQuitSupport)
                    * (dynamicTimelockMaxDuration - dynamicTimelockMinDuration).toSeconds()
                    / PercentD16.unwrap(secondSealRageQuitSupport - firstSealRageQuitSupport)
            );
    }

    function calcRageQuitWithdrawalsTimelock(
        Context memory self,
        uint256 rageQuitRound
    ) internal pure returns (Duration) {
        if (rageQuitRound < self.rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber) {
            return self.rageQuitEthWithdrawalsMinTimelock;
        }
        return self.rageQuitEthWithdrawalsMinTimelock
            + Durations.from(
                (
                    self.rageQuitEthWithdrawalsTimelockGrowthCoeffs[0] * rageQuitRound * rageQuitRound
                        + self.rageQuitEthWithdrawalsTimelockGrowthCoeffs[1] * rageQuitRound
                        + self.rageQuitEthWithdrawalsTimelockGrowthCoeffs[2]
                ) / 10 ** 18
            ); // TODO: rewrite in a prettier way
    }
}
