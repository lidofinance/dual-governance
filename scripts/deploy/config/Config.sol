// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable var-name-mixedcase */

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {Duration} from "contracts/types/Duration.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";

struct TiebreakerSubCommitteeDeployConfig {
    address[] members;
    uint256 quorum;
}

struct TiebreakerDeployConfig {
    Duration activationTimeout;
    Duration minActivationTimeout;
    Duration maxActivationTimeout;
    Duration executionDelay;
    TiebreakerSubCommitteeDeployConfig[] subCommitteeConfigs;
    uint256 quorum;
    address[] sealableWithdrawalBlockers;
}

struct DeployConfig {
    Duration MIN_EXECUTION_DELAY;
    Duration AFTER_SUBMIT_DELAY;
    Duration MAX_AFTER_SUBMIT_DELAY;
    Duration AFTER_SCHEDULE_DELAY;
    Duration MAX_AFTER_SCHEDULE_DELAY;
    Duration EMERGENCY_MODE_DURATION;
    Duration MAX_EMERGENCY_MODE_DURATION;
    Timestamp EMERGENCY_PROTECTION_END_DATE;
    Duration MAX_EMERGENCY_PROTECTION_DURATION;
    address EMERGENCY_ACTIVATION_COMMITTEE;
    address EMERGENCY_EXECUTION_COMMITTEE;
    address RESEAL_COMMITTEE;
    uint256 MIN_WITHDRAWALS_BATCH_SIZE;
    TiebreakerDeployConfig tiebreakerConfig;
    uint256 MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT;
    PercentD16 FIRST_SEAL_RAGE_QUIT_SUPPORT;
    PercentD16 SECOND_SEAL_RAGE_QUIT_SUPPORT;
    Duration MIN_ASSETS_LOCK_DURATION;
    Duration MAX_MIN_ASSETS_LOCK_DURATION;
    Duration VETO_SIGNALLING_MIN_DURATION;
    Duration VETO_SIGNALLING_MAX_DURATION;
    Duration VETO_SIGNALLING_MIN_ACTIVE_DURATION;
    Duration VETO_SIGNALLING_DEACTIVATION_MAX_DURATION;
    Duration VETO_COOLDOWN_DURATION;
    Duration RAGE_QUIT_EXTENSION_PERIOD_DURATION;
    Duration RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY;
    Duration RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY;
    Duration RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH;
    address EMERGENCY_GOVERNANCE_PROPOSER;
    address ADMIN_PROPOSER;
    address PROPOSAL_CANCELER;
}

struct LidoContracts {
    uint256 chainId;
    IStETH stETH;
    IWstETH wstETH;
    IWithdrawalQueue withdrawalQueue;
}
