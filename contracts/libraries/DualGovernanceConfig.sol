// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PercentD16} from "../types/PercentD16.sol";
import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

library DualGovernanceConfig {

    error InvalidRageQuitSupportRange(PercentD16 firstSealRageQuitSupport, PercentD16 secondSealRageQuitSupport);
    error RageQuitEthWithdrawalsDelayRange(
        Duration rageQuitEthWithdrawalsMinDelay, Duration rageQuitEthWithdrawalsMaxDelay
    );
    error InvalidVetoSignallingDurationRange(Duration vetoSignallingMinDuration, Duration vetoSignallingMaxDuration);

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
        //
        Duration vetoCooldownDuration;
        //
        Duration rageQuitExtensionDelay;
        Duration rageQuitEthWithdrawalsMinDelay;
        Duration rageQuitEthWithdrawalsMaxDelay;
        Duration rageQuitEthWithdrawalsDelayGrowth;
    }

    function validate(
        Context memory self
    ) internal pure {
        if (self.firstSealRageQuitSupport >= self.secondSealRageQuitSupport) {
            revert InvalidRageQuitSupportRange(self.firstSealRageQuitSupport, self.secondSealRageQuitSupport);
        }

        if (self.vetoSignallingMinDuration >= self.vetoSignallingMaxDuration) {
            revert InvalidVetoSignallingDurationRange(self.vetoSignallingMinDuration, self.vetoSignallingMaxDuration);
        }

        if (self.rageQuitEthWithdrawalsMinDelay > self.rageQuitEthWithdrawalsMaxDelay) {
            revert RageQuitEthWithdrawalsDelayRange(
                self.rageQuitEthWithdrawalsMinDelay, self.rageQuitEthWithdrawalsMaxDelay
            );
        }
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

    function isVetoSignallingDurationPassed(
        Context memory self,
        Timestamp vetoSignallingActivatedAt,
        PercentD16 rageQuitSupport
    ) internal view returns (bool) {
        return Timestamps.now() > calcVetoSignallingDuration(self, rageQuitSupport).addTo(vetoSignallingActivatedAt);
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

    function calcVetoSignallingDuration(
        Context memory self,
        PercentD16 rageQuitSupport
    ) internal pure returns (Duration duration_) {
        PercentD16 firstSealRageQuitSupport = self.firstSealRageQuitSupport;
        PercentD16 secondSealRageQuitSupport = self.secondSealRageQuitSupport;

        Duration vetoSignallingMinDuration = self.vetoSignallingMinDuration;
        Duration vetoSignallingMaxDuration = self.vetoSignallingMaxDuration;

        if (rageQuitSupport <= firstSealRageQuitSupport) {
            return Durations.ZERO;
        }

        if (rageQuitSupport >= secondSealRageQuitSupport) {
            return vetoSignallingMaxDuration;
        }

        duration_ = vetoSignallingMinDuration
            + Durations.from(
                PercentD16.unwrap(rageQuitSupport - firstSealRageQuitSupport)
                    * (vetoSignallingMaxDuration - vetoSignallingMinDuration).toSeconds()
                    / PercentD16.unwrap(secondSealRageQuitSupport - firstSealRageQuitSupport)
            );
    }

    function calcRageQuitWithdrawalsDelay(
        Context memory self,
        uint256 rageQuitRound
    ) internal pure returns (Duration) {
        return Durations.from(
            Math.min(
                self.rageQuitEthWithdrawalsMinDelay.toSeconds()
                    + rageQuitRound * self.rageQuitEthWithdrawalsDelayGrowth.toSeconds(),
                self.rageQuitEthWithdrawalsMaxDelay.toSeconds()
            )
        );
    }

}
