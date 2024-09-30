// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "./types/Duration.sol";
import {PercentD16} from "./types/PercentD16.sol";

import {IDualGovernanceConfigProvider} from "./interfaces/IDualGovernanceConfigProvider.sol";

import {DualGovernanceConfig} from "./libraries/DualGovernanceConfig.sol";

contract ImmutableDualGovernanceConfigProvider is IDualGovernanceConfigProvider {
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    PercentD16 public immutable FIRST_SEAL_RAGE_QUIT_SUPPORT;
    PercentD16 public immutable SECOND_SEAL_RAGE_QUIT_SUPPORT;

    Duration public immutable MIN_ASSETS_LOCK_DURATION;

    Duration public immutable VETO_SIGNALLING_MIN_DURATION;
    Duration public immutable VETO_SIGNALLING_MAX_DURATION;
    Duration public immutable VETO_SIGNALLING_MIN_ACTIVE_DURATION;
    Duration public immutable VETO_SIGNALLING_DEACTIVATION_MAX_DURATION;

    Duration public immutable VETO_COOLDOWN_DURATION;

    Duration public immutable RAGE_QUIT_EXTENSION_PERIOD_DURATION;
    Duration public immutable RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY;
    Duration public immutable RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY;
    Duration public immutable RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH;

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
