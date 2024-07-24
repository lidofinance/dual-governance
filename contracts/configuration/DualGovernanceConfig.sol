// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

import {EscrowConfig, EscrowConfigState} from "./EscrowConfig.sol";
import {ITiebreakerConfig, TiebreakerConfig, TiebreakerConfigState} from "./TiebreakerConfig.sol";

struct DualGovernanceStateMachineConfigState {
    uint256 firstSealRageQuitSupport;
    uint256 secondSealRageQuitSupport;
    Duration dynamicTimelockMaxDuration;
    Duration dynamicTimelockMinDuration;
    Duration vetoSignallingMinActiveDuration;
    Duration vetoSignallingDeactivationMaxDuration;
    Duration vetoCooldownDuration;
    Duration rageQuitExtensionDelay;
    Duration rageQuitEthWithdrawalsMinTimelock;
    uint256 rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber;
    uint256[3] rageQuitEthWithdrawalsTimelockGrowthCoeffs;
}

interface IDualGovernanceConfig is ITiebreakerConfig {
    function VETO_COOLDOWN_DURATION() external view returns (Duration);
    function VETO_SIGNALLING_MIN_ACTIVE_DURATION() external view returns (Duration);

    function VETO_SIGNALLING_DEACTIVATION_MAX_DURATION() external view returns (Duration);

    function DYNAMIC_TIMELOCK_MIN_DURATION() external view returns (Duration);
    function DYNAMIC_TIMELOCK_MAX_DURATION() external view returns (Duration);

    function FIRST_SEAL_RAGE_QUIT_SUPPORT() external view returns (uint256);
    function SECOND_SEAL_RAGE_QUIT_SUPPORT() external view returns (uint256);

    function RAGE_QUIT_EXTENSION_DELAY() external view returns (Duration);
    function RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK() external view returns (Duration);
    function RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER() external view returns (uint256);

    function RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_A() external view returns (uint256);
    function RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_B() external view returns (uint256);
    function RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_C() external view returns (uint256);

    function getDualGovernanceStateMachineConfig()
        external
        view
        returns (DualGovernanceStateMachineConfigState memory config);
}

contract DualGovernanceConfig is IDualGovernanceConfig, TiebreakerConfig, EscrowConfig {
    uint256 public immutable FIRST_SEAL_RAGE_QUIT_SUPPORT;
    uint256 public immutable SECOND_SEAL_RAGE_QUIT_SUPPORT;

    Duration public immutable DYNAMIC_TIMELOCK_MIN_DURATION;
    Duration public immutable DYNAMIC_TIMELOCK_MAX_DURATION;

    Duration public immutable VETO_SIGNALLING_MIN_ACTIVE_DURATION;
    Duration public immutable VETO_SIGNALLING_DEACTIVATION_MAX_DURATION;

    Duration public immutable VETO_COOLDOWN_DURATION;

    Duration public immutable RAGE_QUIT_EXTENSION_DELAY;
    Duration public immutable RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK;
    uint256 public immutable RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER;

    uint256 public immutable RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_A;
    uint256 public immutable RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_B;
    uint256 public immutable RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_C;

    constructor(
        EscrowConfigState memory escrowConfig,
        TiebreakerConfigState memory tiebreakerConfig,
        DualGovernanceStateMachineConfigState memory dualGovStateMachineConfig
    ) EscrowConfig(escrowConfig) TiebreakerConfig(tiebreakerConfig) {
        FIRST_SEAL_RAGE_QUIT_SUPPORT = dualGovStateMachineConfig.firstSealRageQuitSupport;
        SECOND_SEAL_RAGE_QUIT_SUPPORT = dualGovStateMachineConfig.secondSealRageQuitSupport;

        DYNAMIC_TIMELOCK_MIN_DURATION = dualGovStateMachineConfig.dynamicTimelockMinDuration;
        DYNAMIC_TIMELOCK_MAX_DURATION = dualGovStateMachineConfig.dynamicTimelockMaxDuration;

        VETO_SIGNALLING_MIN_ACTIVE_DURATION = dualGovStateMachineConfig.vetoSignallingMinActiveDuration;
        VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = dualGovStateMachineConfig.vetoSignallingDeactivationMaxDuration;

        VETO_COOLDOWN_DURATION = dualGovStateMachineConfig.vetoCooldownDuration;

        RAGE_QUIT_EXTENSION_DELAY = dualGovStateMachineConfig.rageQuitExtensionDelay;
        RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK = dualGovStateMachineConfig.rageQuitEthWithdrawalsMinTimelock;
        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER =
            dualGovStateMachineConfig.rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber;

        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_A = 0;
        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_B = 0;
        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_C = 0;
    }

    function getDualGovernanceStateMachineConfig()
        external
        view
        returns (DualGovernanceStateMachineConfigState memory config)
    {
        config.firstSealRageQuitSupport = FIRST_SEAL_RAGE_QUIT_SUPPORT;
        config.secondSealRageQuitSupport = SECOND_SEAL_RAGE_QUIT_SUPPORT;
        config.dynamicTimelockMinDuration = DYNAMIC_TIMELOCK_MIN_DURATION;
        config.dynamicTimelockMaxDuration = DYNAMIC_TIMELOCK_MAX_DURATION;
        config.vetoSignallingMinActiveDuration = VETO_SIGNALLING_MIN_ACTIVE_DURATION;
        config.vetoSignallingDeactivationMaxDuration = VETO_SIGNALLING_DEACTIVATION_MAX_DURATION;
        config.vetoCooldownDuration = VETO_COOLDOWN_DURATION;
        config.rageQuitExtensionDelay = RAGE_QUIT_EXTENSION_DELAY;
        config.rageQuitEthWithdrawalsMinTimelock = RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK;
        config.rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber =
            RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER;
        config.rageQuitEthWithdrawalsTimelockGrowthCoeffs = [
            RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_A,
            RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_B,
            RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_C
        ];
    }
}

library DualGovernanceStateMachineConfigUtils {
    function isFirstSealRageQuitSupportCrossed(
        DualGovernanceStateMachineConfigState memory config,
        uint256 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport > config.firstSealRageQuitSupport;
    }

    function isSecondSealRageQuitSupportCrossed(
        DualGovernanceStateMachineConfigState memory config,
        uint256 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport > config.secondSealRageQuitSupport;
    }

    function isDynamicTimelockMaxDurationPassed(
        DualGovernanceStateMachineConfigState memory config,
        Timestamp vetoSignallingActivatedAt
    ) internal view returns (bool) {
        return Timestamps.now() > config.dynamicTimelockMaxDuration.addTo(vetoSignallingActivatedAt);
    }

    function isDynamicTimelockDurationPassed(
        DualGovernanceStateMachineConfigState memory config,
        Timestamp vetoSignallingActivatedAt,
        uint256 rageQuitSupport
    ) internal view returns (bool) {
        Duration dynamicTimelock = calcDynamicDelayDuration(config, rageQuitSupport);
        return Timestamps.now() > dynamicTimelock.addTo(vetoSignallingActivatedAt);
    }

    function isVetoSignallingReactivationDurationPassed(
        DualGovernanceStateMachineConfigState memory config,
        Timestamp vetoSignallingReactivationTime
    ) internal view returns (bool) {
        return Timestamps.now() > config.vetoSignallingMinActiveDuration.addTo(vetoSignallingReactivationTime);
    }

    function isVetoSignallingDeactivationMaxDurationPassed(
        DualGovernanceStateMachineConfigState memory config,
        Timestamp vetoSignallingDeactivationEnteredAt
    ) internal view returns (bool) {
        return
            Timestamps.now() > config.vetoSignallingDeactivationMaxDuration.addTo(vetoSignallingDeactivationEnteredAt);
    }

    function isVetoCooldownDurationPassed(
        DualGovernanceStateMachineConfigState memory config,
        Timestamp vetoCooldownEnteredAt
    ) internal view returns (bool) {
        return Timestamps.now() > config.vetoCooldownDuration.addTo(vetoCooldownEnteredAt);
    }

    function calcDynamicDelayDuration(
        DualGovernanceStateMachineConfigState memory config,
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
        DualGovernanceStateMachineConfigState memory config,
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
