// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Tiebreaker} from "../libraries/Tiebreaker.sol";
import {EscrowState} from "../libraries/EscrowState.sol";
import {DualGovernanceStateMachine} from "../libraries/DualGovernanceStateMachine.sol";

interface IEscrowConfigProvider {
    function getEscrowConfig() external view returns (EscrowState.Config memory config);
}

interface ITiebreakerConfigProvider {
    function getTiebreakerConfig() external view returns (Tiebreaker.Config memory config);
}

interface IDualGovernanceStateMachineConfigProvider {
    function getDualGovernanceStateMachineConfig()
        external
        view
        returns (DualGovernanceStateMachine.Config memory config);
}

interface IDualGovernanceConfigProvider is
    IEscrowConfigProvider,
    ITiebreakerConfigProvider,
    IDualGovernanceStateMachineConfigProvider
{}

contract ImmutableDualGovernanceConfigProvider is IDualGovernanceConfigProvider {
    // ---
    // Escrow Config Immutables
    // ---
    uint256 public immutable MIN_WITHDRAWALS_BATCH_SIZE;
    uint256 public immutable MAX_WITHDRAWALS_BATCH_SIZE;
    Duration public immutable SIGNALLING_ESCROW_MIN_LOCK_TIME;

    // ---
    // Tiebreaker Config Immutables
    // ---
    uint256 public immutable MAX_SEALABLE_WITHDRAWAL_BLOCKERS;
    Duration public immutable MIN_TIEBREAKER_ACTIVATION_TIMEOUT;
    Duration public immutable MAX_TIEBREAKER_ACTIVATION_TIMEOUT;

    // ---
    // Dual Governance State Machine Config Immutables
    // ---
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
        EscrowState.Config memory escrowConfig,
        Tiebreaker.Config memory tiebreakerConfig,
        DualGovernanceStateMachine.Config memory dualGovStateMachineConfig
    ) {
        // ---
        // Escrow Config Params Initialization
        // ---
        MIN_WITHDRAWALS_BATCH_SIZE = escrowConfig.minWithdrawalsBatchSize;
        MAX_WITHDRAWALS_BATCH_SIZE = escrowConfig.maxWithdrawalsBatchSize;
        SIGNALLING_ESCROW_MIN_LOCK_TIME = escrowConfig.signallingEscrowMinLockTime;

        // ---
        // Tiebreaker Config Params Initialization
        // ---
        MAX_SEALABLE_WITHDRAWAL_BLOCKERS = tiebreakerConfig.maxSealableWithdrawalBlockers;
        MIN_TIEBREAKER_ACTIVATION_TIMEOUT = tiebreakerConfig.minTiebreakerActivationTimeout;
        MAX_TIEBREAKER_ACTIVATION_TIMEOUT = tiebreakerConfig.maxTiebreakerActivationTimeout;

        // ---
        // Dual Governance State Machine Config Params Initialization
        // ---
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

        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_A =
            dualGovStateMachineConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[0];
        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_B =
            dualGovStateMachineConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[1];
        RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFF_C =
            dualGovStateMachineConfig.rageQuitEthWithdrawalsTimelockGrowthCoeffs[2];
    }

    function getEscrowConfig() external view returns (EscrowState.Config memory config) {
        config.maxWithdrawalsBatchSize = MAX_WITHDRAWALS_BATCH_SIZE;
        config.minWithdrawalsBatchSize = MIN_WITHDRAWALS_BATCH_SIZE;
        config.signallingEscrowMinLockTime = SIGNALLING_ESCROW_MIN_LOCK_TIME;
    }

    function getTiebreakerConfig() external view returns (Tiebreaker.Config memory config) {
        config.maxSealableWithdrawalBlockers = MAX_SEALABLE_WITHDRAWAL_BLOCKERS;
        config.minTiebreakerActivationTimeout = MIN_TIEBREAKER_ACTIVATION_TIMEOUT;
        config.maxTiebreakerActivationTimeout = MAX_TIEBREAKER_ACTIVATION_TIMEOUT;
    }

    function getDualGovernanceStateMachineConfig()
        external
        view
        returns (DualGovernanceStateMachine.Config memory config)
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
