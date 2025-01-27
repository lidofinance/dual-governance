// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeployConfig} from "../deploy/config/Config.sol";

contract DeployConfigStorage {
    DeployConfig internal _config;

    function _fillConfig(DeployConfig memory config) internal {
        _config.MIN_EXECUTION_DELAY = config.MIN_EXECUTION_DELAY;
        _config.AFTER_SUBMIT_DELAY = config.AFTER_SUBMIT_DELAY;
        _config.MAX_AFTER_SUBMIT_DELAY = config.MAX_AFTER_SUBMIT_DELAY;
        _config.AFTER_SCHEDULE_DELAY = config.AFTER_SCHEDULE_DELAY;
        _config.MAX_AFTER_SCHEDULE_DELAY = config.MAX_AFTER_SCHEDULE_DELAY;
        _config.EMERGENCY_MODE_DURATION = config.EMERGENCY_MODE_DURATION;
        _config.MAX_EMERGENCY_MODE_DURATION = config.MAX_EMERGENCY_MODE_DURATION;
        _config.EMERGENCY_PROTECTION_END_DATE = config.EMERGENCY_PROTECTION_END_DATE;
        _config.MAX_EMERGENCY_PROTECTION_DURATION = config.MAX_EMERGENCY_PROTECTION_DURATION;
        _config.EMERGENCY_ACTIVATION_COMMITTEE = config.EMERGENCY_ACTIVATION_COMMITTEE;
        _config.EMERGENCY_EXECUTION_COMMITTEE = config.EMERGENCY_EXECUTION_COMMITTEE;
        _config.RESEAL_COMMITTEE = config.RESEAL_COMMITTEE;
        _config.MIN_WITHDRAWALS_BATCH_SIZE = config.MIN_WITHDRAWALS_BATCH_SIZE;
        _config.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = config.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT;
        _config.FIRST_SEAL_RAGE_QUIT_SUPPORT = config.FIRST_SEAL_RAGE_QUIT_SUPPORT;
        _config.SECOND_SEAL_RAGE_QUIT_SUPPORT = config.SECOND_SEAL_RAGE_QUIT_SUPPORT;
        _config.MIN_ASSETS_LOCK_DURATION = config.MIN_ASSETS_LOCK_DURATION;
        _config.MAX_MIN_ASSETS_LOCK_DURATION = config.MAX_MIN_ASSETS_LOCK_DURATION;
        _config.VETO_SIGNALLING_MIN_DURATION = config.VETO_SIGNALLING_MIN_DURATION;
        _config.VETO_SIGNALLING_MAX_DURATION = config.VETO_SIGNALLING_MAX_DURATION;
        _config.VETO_SIGNALLING_MIN_ACTIVE_DURATION = config.VETO_SIGNALLING_MIN_ACTIVE_DURATION;
        _config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION;
        _config.VETO_COOLDOWN_DURATION = config.VETO_COOLDOWN_DURATION;
        _config.RAGE_QUIT_EXTENSION_PERIOD_DURATION = config.RAGE_QUIT_EXTENSION_PERIOD_DURATION;
        _config.RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY = config.RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY;
        _config.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY = config.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY;
        _config.RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH = config.RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH;
        _config.EMERGENCY_GOVERNANCE_PROPOSER = config.EMERGENCY_GOVERNANCE_PROPOSER;
        _config.ADMIN_PROPOSER = config.ADMIN_PROPOSER;
        _config.PROPOSAL_CANCELER = config.PROPOSAL_CANCELER;

        _config.tiebreakerConfig.activationTimeout = config.tiebreakerConfig.activationTimeout;
        _config.tiebreakerConfig.minActivationTimeout = config.tiebreakerConfig.minActivationTimeout;
        _config.tiebreakerConfig.maxActivationTimeout = config.tiebreakerConfig.maxActivationTimeout;
        _config.tiebreakerConfig.executionDelay = config.tiebreakerConfig.executionDelay;
        _config.tiebreakerConfig.quorum = config.tiebreakerConfig.quorum;
        _config.tiebreakerConfig.sealableWithdrawalBlockers = config.tiebreakerConfig.sealableWithdrawalBlockers;

        for (uint256 i = 0; i < config.tiebreakerConfig.subCommitteeConfigs.length; i++) {
            _config.tiebreakerConfig.subCommitteeConfigs.push(config.tiebreakerConfig.subCommitteeConfigs[i]);
        }
    }
}
