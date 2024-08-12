// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "./types/Duration.sol";
import {PercentD16} from "./types/PercentD16.sol";
import {DualGovernanceConfig} from "./libraries/DualGovernanceConfig.sol";
import {IDualGovernanceConfigProvider} from "./interfaces/IDualGovernanceConfigProvider.sol";

contract ImmutableDualGovernanceConfigProvider is IDualGovernanceConfigProvider {
    PercentD16 public immutable FIRST_SEAL_RAGE_QUIT_SUPPORT;
    PercentD16 public immutable SECOND_SEAL_RAGE_QUIT_SUPPORT;

    Duration public immutable MIN_ASSETS_LOCK_DURATION;
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

    constructor(DualGovernanceConfig.Context memory dualGovernanceConfig) {
        FIRST_SEAL_RAGE_QUIT_SUPPORT = dualGovernanceConfig.firstSealRageQuitSupport;
        SECOND_SEAL_RAGE_QUIT_SUPPORT = dualGovernanceConfig.secondSealRageQuitSupport;

        MIN_ASSETS_LOCK_DURATION = dualGovernanceConfig.minAssetsLockDuration;
        DYNAMIC_TIMELOCK_MIN_DURATION = dualGovernanceConfig.dynamicTimelockMinDuration;
        DYNAMIC_TIMELOCK_MAX_DURATION = dualGovernanceConfig.dynamicTimelockMaxDuration;

        VETO_SIGNALLING_MIN_ACTIVE_DURATION = dualGovernanceConfig.vetoSignallingMinActiveDuration;
        VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = dualGovernanceConfig.vetoSignallingDeactivationMaxDuration;

        VETO_COOLDOWN_DURATION = dualGovernanceConfig.vetoCooldownDuration;

        RAGE_QUIT_EXTENSION_DELAY = dualGovernanceConfig.rageQuitExtensionDelay;
        RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK = dualGovernanceConfig.rageQuitEthWithdrawalsMinTimelock;
        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER =
            dualGovernanceConfig.rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber;

        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_A =
            dualGovernanceConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[0];
        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_B =
            dualGovernanceConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[1];
        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_C =
            dualGovernanceConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[2];
    }

    function getDualGovernanceConfig() external view returns (DualGovernanceConfig.Context memory config) {
        config.firstSealRageQuitSupport = FIRST_SEAL_RAGE_QUIT_SUPPORT;
        config.secondSealRageQuitSupport = SECOND_SEAL_RAGE_QUIT_SUPPORT;

        config.minAssetsLockDuration = MIN_ASSETS_LOCK_DURATION;
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
