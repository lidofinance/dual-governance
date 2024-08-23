// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, var-name-mixedcase */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {PercentD16, PercentsD16} from "contracts/types/PercentD16.sol";

string constant ARRAY_SEPARATOR = ",";

struct ConfigValues {
    uint256 DEPLOYER_PRIVATE_KEY;
    Duration AFTER_SUBMIT_DELAY;
    Duration MAX_AFTER_SUBMIT_DELAY;
    Duration AFTER_SCHEDULE_DELAY;
    Duration MAX_AFTER_SCHEDULE_DELAY;
    Duration EMERGENCY_MODE_DURATION;
    Duration MAX_EMERGENCY_MODE_DURATION;
    Duration EMERGENCY_PROTECTION_DURATION;
    Duration MAX_EMERGENCY_PROTECTION_DURATION;
    uint256 EMERGENCY_ACTIVATION_COMMITTEE_QUORUM;
    address[] EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS;
    uint256 EMERGENCY_EXECUTION_COMMITTEE_QUORUM;
    address[] EMERGENCY_EXECUTION_COMMITTEE_MEMBERS;
    uint256 TIEBREAKER_CORE_QUORUM;
    Duration TIEBREAKER_EXECUTION_DELAY;
    uint256 TIEBREAKER_SUB_COMMITTEES_COUNT;
    address[] TIEBREAKER_SUB_COMMITTEE_1_MEMBERS;
    uint256 TIEBREAKER_SUB_COMMITTEE_1_QUORUM;
    address[] TIEBREAKER_SUB_COMMITTEE_2_MEMBERS;
    uint256 TIEBREAKER_SUB_COMMITTEE_2_QUORUM;
    address[] RESEAL_COMMITTEE_MEMBERS;
    uint256 RESEAL_COMMITTEE_QUORUM;
    uint256 MIN_WITHDRAWALS_BATCH_SIZE;
    Duration MIN_TIEBREAKER_ACTIVATION_TIMEOUT;
    Duration TIEBREAKER_ACTIVATION_TIMEOUT;
    Duration MAX_TIEBREAKER_ACTIVATION_TIMEOUT;
    uint256 MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT;
    PercentD16 FIRST_SEAL_RAGE_QUIT_SUPPORT;
    PercentD16 SECOND_SEAL_RAGE_QUIT_SUPPORT;
    Duration MIN_ASSETS_LOCK_DURATION;
    Duration DYNAMIC_TIMELOCK_MIN_DURATION;
    Duration DYNAMIC_TIMELOCK_MAX_DURATION;
    Duration VETO_SIGNALLING_MIN_ACTIVE_DURATION;
    Duration VETO_SIGNALLING_DEACTIVATION_MAX_DURATION;
    Duration VETO_COOLDOWN_DURATION;
    Duration RAGE_QUIT_EXTENSION_DELAY;
    Duration RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK;
    uint256 RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER;
    uint256[3] RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS;
}

contract DGDeployConfig is Script {
    error InvalidRageQuitETHWithdrawalsTimelockGrowthCoeffs(uint256[] coeffs);
    error InvalidQuorum(string committee, uint256 quorum);

    uint256 internal immutable DEFAULT_AFTER_SUBMIT_DELAY = 3 days;
    uint256 internal immutable DEFAULT_MAX_AFTER_SUBMIT_DELAY = 45 days;
    uint256 internal immutable DEFAULT_AFTER_SCHEDULE_DELAY = 3 days;
    uint256 internal immutable DEFAULT_MAX_AFTER_SCHEDULE_DELAY = 45 days;
    uint256 internal immutable DEFAULT_EMERGENCY_MODE_DURATION = 180 days;
    uint256 internal immutable DEFAULT_MAX_EMERGENCY_MODE_DURATION = 365 days;
    uint256 internal immutable DEFAULT_EMERGENCY_PROTECTION_DURATION = 90 days;
    uint256 internal immutable DEFAULT_MAX_EMERGENCY_PROTECTION_DURATION = 365 days;
    uint256 internal immutable DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE_QUORUM = 3;
    uint256 internal immutable DEFAULT_EMERGENCY_EXECUTION_COMMITTEE_QUORUM = 5;
    uint256 internal immutable DEFAULT_TIEBREAKER_CORE_QUORUM = 1;
    uint256 internal immutable DEFAULT_TIEBREAKER_EXECUTION_DELAY = 30 days;
    uint256 internal immutable DEFAULT_TIEBREAKER_SUB_COMMITTEES_COUNT = 2;
    uint256 internal immutable DEFAULT_TIEBREAKER_SUB_COMMITTEE_1_QUORUM = 5;
    uint256 internal immutable DEFAULT_TIEBREAKER_SUB_COMMITTEE_2_QUORUM = 5;
    uint256 internal immutable DEFAULT_RESEAL_COMMITTEE_QUORUM = 3;
    uint256 internal immutable DEFAULT_MIN_WITHDRAWALS_BATCH_SIZE = 4;
    uint256 internal immutable DEFAULT_MIN_TIEBREAKER_ACTIVATION_TIMEOUT = 90 days;
    uint256 internal immutable DEFAULT_TIEBREAKER_ACTIVATION_TIMEOUT = 365 days;
    uint256 internal immutable DEFAULT_MAX_TIEBREAKER_ACTIVATION_TIMEOUT = 730 days;
    uint256 internal immutable DEFAULT_MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = 255;

    uint256 internal immutable DEFAULT_FIRST_SEAL_RAGE_QUIT_SUPPORT = 3_00; // 3%
    uint256 internal immutable DEFAULT_SECOND_SEAL_RAGE_QUIT_SUPPORT = 15_00; // 15%
    uint256 internal immutable DEFAULT_MIN_ASSETS_LOCK_DURATION = 5 hours;
    uint256 internal immutable DEFAULT_DYNAMIC_TIMELOCK_MIN_DURATION = 3 days;
    uint256 internal immutable DEFAULT_DYNAMIC_TIMELOCK_MAX_DURATION = 30 days;
    uint256 internal immutable DEFAULT_VETO_SIGNALLING_MIN_ACTIVE_DURATION = 5 hours;
    uint256 internal immutable DEFAULT_VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = 5 days;
    uint256 internal immutable DEFAULT_VETO_COOLDOWN_DURATION = 4 days;
    uint256 internal immutable DEFAULT_RAGE_QUIT_EXTENSION_DELAY = 7 days;
    uint256 internal immutable DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK = 60 days;
    uint256 internal immutable DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER = 2;
    uint256[] internal DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS = new uint256[](3);

    constructor() {
        // TODO: are these values correct as a default?
        DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[0] = 0;
        DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[1] = 0;
        DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS[2] = 0;
    }

    function loadAndValidate() external returns (ConfigValues memory config) {
        config = ConfigValues({
            DEPLOYER_PRIVATE_KEY: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            AFTER_SUBMIT_DELAY: Durations.from(vm.envOr("AFTER_SUBMIT_DELAY", DEFAULT_AFTER_SUBMIT_DELAY)),
            MAX_AFTER_SUBMIT_DELAY: Durations.from(vm.envOr("MAX_AFTER_SUBMIT_DELAY", DEFAULT_MAX_AFTER_SUBMIT_DELAY)),
            AFTER_SCHEDULE_DELAY: Durations.from(vm.envOr("AFTER_SCHEDULE_DELAY", DEFAULT_AFTER_SCHEDULE_DELAY)),
            MAX_AFTER_SCHEDULE_DELAY: Durations.from(vm.envOr("MAX_AFTER_SCHEDULE_DELAY", DEFAULT_MAX_AFTER_SCHEDULE_DELAY)),
            EMERGENCY_MODE_DURATION: Durations.from(vm.envOr("EMERGENCY_MODE_DURATION", DEFAULT_EMERGENCY_MODE_DURATION)),
            MAX_EMERGENCY_MODE_DURATION: Durations.from(
                vm.envOr("MAX_EMERGENCY_MODE_DURATION", DEFAULT_MAX_EMERGENCY_MODE_DURATION)
            ),
            EMERGENCY_PROTECTION_DURATION: Durations.from(
                vm.envOr("EMERGENCY_PROTECTION_DURATION", DEFAULT_EMERGENCY_PROTECTION_DURATION)
            ),
            MAX_EMERGENCY_PROTECTION_DURATION: Durations.from(
                vm.envOr("MAX_EMERGENCY_PROTECTION_DURATION", DEFAULT_MAX_EMERGENCY_PROTECTION_DURATION)
            ),
            EMERGENCY_ACTIVATION_COMMITTEE_QUORUM: vm.envOr(
                "EMERGENCY_ACTIVATION_COMMITTEE_QUORUM", DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE_QUORUM
            ),
            EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS: vm.envAddress("EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS", ARRAY_SEPARATOR),
            EMERGENCY_EXECUTION_COMMITTEE_QUORUM: vm.envOr(
                "EMERGENCY_EXECUTION_COMMITTEE_QUORUM", DEFAULT_EMERGENCY_EXECUTION_COMMITTEE_QUORUM
            ),
            EMERGENCY_EXECUTION_COMMITTEE_MEMBERS: vm.envAddress("EMERGENCY_EXECUTION_COMMITTEE_MEMBERS", ARRAY_SEPARATOR),
            // TODO: Do we need to configure this?
            TIEBREAKER_CORE_QUORUM: DEFAULT_TIEBREAKER_CORE_QUORUM,
            TIEBREAKER_EXECUTION_DELAY: Durations.from(
                vm.envOr("TIEBREAKER_EXECUTION_DELAY", DEFAULT_TIEBREAKER_EXECUTION_DELAY)
            ),
            // TODO: Do we need to configure this?
            TIEBREAKER_SUB_COMMITTEES_COUNT: DEFAULT_TIEBREAKER_SUB_COMMITTEES_COUNT,
            TIEBREAKER_SUB_COMMITTEE_1_MEMBERS: vm.envAddress("TIEBREAKER_SUB_COMMITTEE_1_MEMBERS", ARRAY_SEPARATOR),
            TIEBREAKER_SUB_COMMITTEE_1_QUORUM: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_1_QUORUM", DEFAULT_TIEBREAKER_SUB_COMMITTEE_1_QUORUM
            ),
            TIEBREAKER_SUB_COMMITTEE_2_MEMBERS: vm.envAddress("TIEBREAKER_SUB_COMMITTEE_2_MEMBERS", ARRAY_SEPARATOR),
            TIEBREAKER_SUB_COMMITTEE_2_QUORUM: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_2_QUORUM", DEFAULT_TIEBREAKER_SUB_COMMITTEE_2_QUORUM
            ),
            RESEAL_COMMITTEE_MEMBERS: vm.envAddress("RESEAL_COMMITTEE_MEMBERS", ARRAY_SEPARATOR),
            RESEAL_COMMITTEE_QUORUM: vm.envOr("RESEAL_COMMITTEE_QUORUM", DEFAULT_RESEAL_COMMITTEE_QUORUM),
            MIN_WITHDRAWALS_BATCH_SIZE: vm.envOr("MIN_WITHDRAWALS_BATCH_SIZE", DEFAULT_MIN_WITHDRAWALS_BATCH_SIZE),
            MIN_TIEBREAKER_ACTIVATION_TIMEOUT: Durations.from(
                vm.envOr("MIN_TIEBREAKER_ACTIVATION_TIMEOUT", DEFAULT_MIN_TIEBREAKER_ACTIVATION_TIMEOUT)
            ),
            TIEBREAKER_ACTIVATION_TIMEOUT: Durations.from(
                vm.envOr("TIEBREAKER_ACTIVATION_TIMEOUT", DEFAULT_TIEBREAKER_ACTIVATION_TIMEOUT)
            ),
            MAX_TIEBREAKER_ACTIVATION_TIMEOUT: Durations.from(
                vm.envOr("MAX_TIEBREAKER_ACTIVATION_TIMEOUT", DEFAULT_MAX_TIEBREAKER_ACTIVATION_TIMEOUT)
            ),
            MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT: vm.envOr(
                "MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT", DEFAULT_MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT
            ),
            FIRST_SEAL_RAGE_QUIT_SUPPORT: PercentsD16.fromBasisPoints(
                vm.envOr("FIRST_SEAL_RAGE_QUIT_SUPPORT", DEFAULT_FIRST_SEAL_RAGE_QUIT_SUPPORT)
            ),
            SECOND_SEAL_RAGE_QUIT_SUPPORT: PercentsD16.fromBasisPoints(
                vm.envOr("SECOND_SEAL_RAGE_QUIT_SUPPORT", DEFAULT_SECOND_SEAL_RAGE_QUIT_SUPPORT)
            ),
            MIN_ASSETS_LOCK_DURATION: Durations.from(vm.envOr("MIN_ASSETS_LOCK_DURATION", DEFAULT_MIN_ASSETS_LOCK_DURATION)),
            DYNAMIC_TIMELOCK_MIN_DURATION: Durations.from(
                vm.envOr("DYNAMIC_TIMELOCK_MIN_DURATION", DEFAULT_DYNAMIC_TIMELOCK_MIN_DURATION)
            ),
            DYNAMIC_TIMELOCK_MAX_DURATION: Durations.from(
                vm.envOr("DYNAMIC_TIMELOCK_MAX_DURATION", DEFAULT_DYNAMIC_TIMELOCK_MAX_DURATION)
            ),
            VETO_SIGNALLING_MIN_ACTIVE_DURATION: Durations.from(
                vm.envOr("VETO_SIGNALLING_MIN_ACTIVE_DURATION", DEFAULT_VETO_SIGNALLING_MIN_ACTIVE_DURATION)
            ),
            VETO_SIGNALLING_DEACTIVATION_MAX_DURATION: Durations.from(
                vm.envOr("VETO_SIGNALLING_DEACTIVATION_MAX_DURATION", DEFAULT_VETO_SIGNALLING_DEACTIVATION_MAX_DURATION)
            ),
            VETO_COOLDOWN_DURATION: Durations.from(vm.envOr("VETO_COOLDOWN_DURATION", DEFAULT_VETO_COOLDOWN_DURATION)),
            RAGE_QUIT_EXTENSION_DELAY: Durations.from(
                vm.envOr("RAGE_QUIT_EXTENSION_DELAY", DEFAULT_RAGE_QUIT_EXTENSION_DELAY)
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK: Durations.from(
                vm.envOr("RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK", DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_MIN_TIMELOCK)
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER: vm.envOr(
                "RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER",
                DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_START_SEQ_NUMBER
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS: getValidCoeffs()
        });

        validateConfig(config);
        printCommittees(config);
    }

    function getValidCoeffs() internal returns (uint256[3] memory coeffs) {
        uint256[] memory coeffsRaw = vm.envOr(
            "RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS",
            ARRAY_SEPARATOR,
            DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_TIMELOCK_GROWTH_COEFFS
        );

        if (coeffsRaw.length != 3) {
            revert InvalidRageQuitETHWithdrawalsTimelockGrowthCoeffs(coeffsRaw);
        }

        // TODO: validate each coeff value?
        coeffs[0] = coeffsRaw[0];
        coeffs[1] = coeffsRaw[1];
        coeffs[2] = coeffsRaw[2];
    }

    function validateConfig(ConfigValues memory config) internal pure {
        if (
            config.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM == 0
                || config.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM > config.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS.length
        ) {
            revert InvalidQuorum("EMERGENCY_ACTIVATION_COMMITTEE", config.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM);
        }

        if (
            config.EMERGENCY_EXECUTION_COMMITTEE_QUORUM == 0
                || config.EMERGENCY_EXECUTION_COMMITTEE_QUORUM > config.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS.length
        ) {
            revert InvalidQuorum("EMERGENCY_EXECUTION_COMMITTEE", config.EMERGENCY_EXECUTION_COMMITTEE_QUORUM);
        }

        if (
            config.TIEBREAKER_SUB_COMMITTEE_1_QUORUM == 0
                || config.TIEBREAKER_SUB_COMMITTEE_1_QUORUM > config.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS.length
        ) {
            revert InvalidQuorum("TIEBREAKER_SUB_COMMITTEE_1", config.TIEBREAKER_SUB_COMMITTEE_1_QUORUM);
        }

        if (
            config.TIEBREAKER_SUB_COMMITTEE_2_QUORUM == 0
                || config.TIEBREAKER_SUB_COMMITTEE_2_QUORUM > config.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS.length
        ) {
            revert InvalidQuorum("TIEBREAKER_SUB_COMMITTEE_2", config.TIEBREAKER_SUB_COMMITTEE_2_QUORUM);
        }

        if (
            config.RESEAL_COMMITTEE_QUORUM == 0
                || config.RESEAL_COMMITTEE_QUORUM > config.RESEAL_COMMITTEE_MEMBERS.length
        ) {
            revert InvalidQuorum("RESEAL_COMMITTEE", config.RESEAL_COMMITTEE_QUORUM);
        }
    }

    function printCommittees(ConfigValues memory config) internal view {
        console.log("=================================================");
        console.log("Loaded valid config with the following committees:");

        console.log(
            "EmergencyActivationCommittee members, quorum",
            config.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM,
            "of",
            config.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS.length
        );
        for (uint256 k = 0; k < config.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS.length; ++k) {
            console.log(">> #", k, address(config.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS[k]));
        }

        console.log(
            "EmergencyExecutionCommittee members, quorum",
            config.EMERGENCY_EXECUTION_COMMITTEE_QUORUM,
            "of",
            config.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS.length
        );
        for (uint256 k = 0; k < config.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS.length; ++k) {
            console.log(">> #", k, address(config.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS[k]));
        }

        console.log(
            "TiebreakerSubCommittee #1 members, quorum",
            config.TIEBREAKER_SUB_COMMITTEE_1_QUORUM,
            "of",
            config.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS.length
        );
        for (uint256 k = 0; k < config.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS.length; ++k) {
            console.log(">> #", k, address(config.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS[k]));
        }

        console.log(
            "TiebreakerSubCommittee #2 members, quorum",
            config.TIEBREAKER_SUB_COMMITTEE_2_QUORUM,
            "of",
            config.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS.length
        );
        for (uint256 k = 0; k < config.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS.length; ++k) {
            console.log(">> #", k, address(config.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS[k]));
        }

        console.log(
            "ResealCommittee members, quorum",
            config.RESEAL_COMMITTEE_QUORUM,
            "of",
            config.RESEAL_COMMITTEE_MEMBERS.length
        );
        for (uint256 k = 0; k < config.RESEAL_COMMITTEE_MEMBERS.length; ++k) {
            console.log(">> #", k, address(config.RESEAL_COMMITTEE_MEMBERS[k]));
        }
        console.log("=================================================");
    }
}
