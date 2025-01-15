// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable var-name-mixedcase */

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {Duration} from "contracts/types/Duration.sol";
import {PercentD16} from "contracts/types/PercentD16.sol";

bytes32 constant CHAIN_NAME_MAINNET_HASH = keccak256(bytes("mainnet"));
bytes32 constant CHAIN_NAME_HOLESKY_HASH = keccak256(bytes("holesky"));
bytes32 constant CHAIN_NAME_HOLESKY_MOCKS_HASH = keccak256(bytes("holesky-mocks"));
uint256 constant TIEBREAKER_SUB_COMMITTEES_COUNT = 3;

struct TiebreakerSubCommitteeDeployConfig {
    address[] members;
    uint256 quorum;
}

struct TiebreakerDeployConfig {
    Duration activationTimeout;
    Duration minActivationTimeout;
    Duration maxActivationTimeout;
    Duration executionDelay;
    TiebreakerSubCommitteeDeployConfig influencers;
    TiebreakerSubCommitteeDeployConfig nodeOperators;
    TiebreakerSubCommitteeDeployConfig protocols;
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
    Duration EMERGENCY_PROTECTION_DURATION;
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
    address TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER;
}

struct LidoContracts {
    uint256 chainId;
    IStETH stETH;
    IWstETH wstETH;
    IWithdrawalQueue withdrawalQueue;
    address voting;
}

function getSubCommitteeData(
    uint256 index,
    DeployConfig memory dgDeployConfig
) pure returns (uint256 quorum, address[] memory members) {
    assert(index < TIEBREAKER_SUB_COMMITTEES_COUNT);

    if (index == 0) {
        quorum = dgDeployConfig.tiebreakerConfig.influencers.quorum;
        members = dgDeployConfig.tiebreakerConfig.influencers.members;
    }

    if (index == 1) {
        quorum = dgDeployConfig.tiebreakerConfig.nodeOperators.quorum;
        members = dgDeployConfig.tiebreakerConfig.nodeOperators.members;
    }

    if (index == 2) {
        quorum = dgDeployConfig.tiebreakerConfig.protocols.quorum;
        members = dgDeployConfig.tiebreakerConfig.protocols.members;
    }
}
