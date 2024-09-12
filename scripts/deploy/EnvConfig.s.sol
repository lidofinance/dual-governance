// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, var-name-mixedcase */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {IAragonVoting} from "contracts/interfaces/IAragonVoting.sol";
import {
    ST_ETH as MAINNET_ST_ETH,
    WST_ETH as MAINNET_WST_ETH,
    WITHDRAWAL_QUEUE as MAINNET_WITHDRAWAL_QUEUE,
    DAO_VOTING as MAINNET_DAO_VOTING
} from "addresses/mainnet-addresses.sol";
import {
    ST_ETH as HOLESKY_ST_ETH,
    WST_ETH as HOLESKY_WST_ETH,
    WITHDRAWAL_QUEUE as HOLESKY_WITHDRAWAL_QUEUE,
    DAO_VOTING as HOLESKY_DAO_VOTING
} from "addresses/holesky-addresses.sol";
import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";
import {DeployConfig, LidoContracts} from "./Config.sol";

string constant ARRAY_SEPARATOR = ",";
bytes32 constant CHAIN_NAME_MAINNET_HASH = keccak256(bytes("mainnet"));
bytes32 constant CHAIN_NAME_HOLESKY_HASH = keccak256(bytes("holesky"));
bytes32 constant CHAIN_NAME_HOLESKY_MOCKS_HASH = keccak256(bytes("holesky-mocks"));

contract DGDeployConfigProvider is Script {
    error InvalidQuorum(string committee, uint256 quorum);
    error InvalidParameter(string parameter);
    error InvalidChain(string chainName);

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
    uint256 internal immutable DEFAULT_RESEAL_COMMITTEE_QUORUM = 3;
    uint256 internal immutable DEFAULT_MIN_WITHDRAWALS_BATCH_SIZE = 4;
    uint256 internal immutable DEFAULT_MIN_TIEBREAKER_ACTIVATION_TIMEOUT = 90 days;
    uint256 internal immutable DEFAULT_TIEBREAKER_ACTIVATION_TIMEOUT = 365 days;
    uint256 internal immutable DEFAULT_MAX_TIEBREAKER_ACTIVATION_TIMEOUT = 730 days;
    uint256 internal immutable DEFAULT_MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT = 255;

    uint256 internal immutable DEFAULT_FIRST_SEAL_RAGE_QUIT_SUPPORT = 3_00; // 3%
    uint256 internal immutable DEFAULT_SECOND_SEAL_RAGE_QUIT_SUPPORT = 15_00; // 15%
    uint256 internal immutable DEFAULT_MIN_ASSETS_LOCK_DURATION = 5 hours;
    uint256 internal immutable DEFAULT_VETO_SIGNALLING_MIN_DURATION = 3 days;
    uint256 internal immutable DEFAULT_VETO_SIGNALLING_MAX_DURATION = 30 days;
    uint256 internal immutable DEFAULT_VETO_SIGNALLING_MIN_ACTIVE_DURATION = 5 hours;
    uint256 internal immutable DEFAULT_VETO_SIGNALLING_DEACTIVATION_MAX_DURATION = 5 days;
    uint256 internal immutable DEFAULT_VETO_COOLDOWN_DURATION = 4 days;
    uint256 internal immutable DEFAULT_RAGE_QUIT_EXTENSION_PERIOD_DURATION = 7 days;
    uint256 internal immutable DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY = 30 days;
    uint256 internal immutable DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY = 180 days;
    uint256 internal immutable DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH = 15 days;

    function loadAndValidate() external returns (DeployConfig memory config) {
        config = DeployConfig({
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
            TIEBREAKER_CORE_QUORUM: vm.envOr("TIEBREAKER_CORE_QUORUM", DEFAULT_TIEBREAKER_CORE_QUORUM),
            TIEBREAKER_EXECUTION_DELAY: Durations.from(
                vm.envOr("TIEBREAKER_EXECUTION_DELAY", DEFAULT_TIEBREAKER_EXECUTION_DELAY)
            ),
            TIEBREAKER_SUB_COMMITTEES_COUNT: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEES_COUNT", DEFAULT_TIEBREAKER_SUB_COMMITTEES_COUNT
            ),
            TIEBREAKER_SUB_COMMITTEE_1_MEMBERS: vm.envAddress("TIEBREAKER_SUB_COMMITTEE_1_MEMBERS", ARRAY_SEPARATOR),
            TIEBREAKER_SUB_COMMITTEE_2_MEMBERS: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_2_MEMBERS", ARRAY_SEPARATOR, new address[](0)
            ),
            TIEBREAKER_SUB_COMMITTEE_3_MEMBERS: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_3_MEMBERS", ARRAY_SEPARATOR, new address[](0)
            ),
            TIEBREAKER_SUB_COMMITTEE_4_MEMBERS: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_4_MEMBERS", ARRAY_SEPARATOR, new address[](0)
            ),
            TIEBREAKER_SUB_COMMITTEE_5_MEMBERS: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_5_MEMBERS", ARRAY_SEPARATOR, new address[](0)
            ),
            TIEBREAKER_SUB_COMMITTEE_6_MEMBERS: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_6_MEMBERS", ARRAY_SEPARATOR, new address[](0)
            ),
            TIEBREAKER_SUB_COMMITTEE_7_MEMBERS: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_7_MEMBERS", ARRAY_SEPARATOR, new address[](0)
            ),
            TIEBREAKER_SUB_COMMITTEE_8_MEMBERS: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_8_MEMBERS", ARRAY_SEPARATOR, new address[](0)
            ),
            TIEBREAKER_SUB_COMMITTEE_9_MEMBERS: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_9_MEMBERS", ARRAY_SEPARATOR, new address[](0)
            ),
            TIEBREAKER_SUB_COMMITTEE_10_MEMBERS: vm.envOr(
                "TIEBREAKER_SUB_COMMITTEE_10_MEMBERS", ARRAY_SEPARATOR, new address[](0)
            ),
            TIEBREAKER_SUB_COMMITTEES_QUORUMS: vm.envUint("TIEBREAKER_SUB_COMMITTEES_QUORUMS", ARRAY_SEPARATOR),
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
            VETO_SIGNALLING_MIN_DURATION: Durations.from(
                vm.envOr("VETO_SIGNALLING_MIN_DURATION", DEFAULT_VETO_SIGNALLING_MIN_DURATION)
            ),
            VETO_SIGNALLING_MAX_DURATION: Durations.from(
                vm.envOr("VETO_SIGNALLING_MAX_DURATION", DEFAULT_VETO_SIGNALLING_MAX_DURATION)
            ),
            VETO_SIGNALLING_MIN_ACTIVE_DURATION: Durations.from(
                vm.envOr("VETO_SIGNALLING_MIN_ACTIVE_DURATION", DEFAULT_VETO_SIGNALLING_MIN_ACTIVE_DURATION)
            ),
            VETO_SIGNALLING_DEACTIVATION_MAX_DURATION: Durations.from(
                vm.envOr("VETO_SIGNALLING_DEACTIVATION_MAX_DURATION", DEFAULT_VETO_SIGNALLING_DEACTIVATION_MAX_DURATION)
            ),
            VETO_COOLDOWN_DURATION: Durations.from(vm.envOr("VETO_COOLDOWN_DURATION", DEFAULT_VETO_COOLDOWN_DURATION)),
            RAGE_QUIT_EXTENSION_PERIOD_DURATION: Durations.from(
                vm.envOr("RAGE_QUIT_EXTENSION_PERIOD_DURATION", DEFAULT_RAGE_QUIT_EXTENSION_PERIOD_DURATION)
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY: Durations.from(
                vm.envOr("RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY", DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY)
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY: Durations.from(
                vm.envOr("RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY", DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY)
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH: Durations.from(
                vm.envOr("RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH", DEFAULT_RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH)
            )
        });

        validateConfig(config);
        printCommittees(config);
    }

    function getLidoAddresses(string memory chainName) external view returns (LidoContracts memory) {
        bytes32 chainNameHash = keccak256(bytes(chainName));
        if (
            chainNameHash != CHAIN_NAME_MAINNET_HASH && chainNameHash != CHAIN_NAME_HOLESKY_HASH
                && chainNameHash != CHAIN_NAME_HOLESKY_MOCKS_HASH
        ) {
            revert InvalidChain(chainName);
        }

        if (keccak256(bytes(chainName)) == CHAIN_NAME_MAINNET_HASH) {
            return LidoContracts({
                chainId: 1,
                stETH: IStETH(MAINNET_ST_ETH),
                wstETH: IWstETH(MAINNET_WST_ETH),
                withdrawalQueue: IWithdrawalQueue(MAINNET_WITHDRAWAL_QUEUE),
                voting: IAragonVoting(MAINNET_DAO_VOTING)
            });
        }

        if (keccak256(bytes(chainName)) == CHAIN_NAME_HOLESKY_MOCKS_HASH) {
            return LidoContracts({
                chainId: 17000,
                stETH: IStETH(vm.envAddress("HOLESKY_MOCK_ST_ETH")),
                wstETH: IWstETH(vm.envAddress("HOLESKY_MOCK_WST_ETH")),
                withdrawalQueue: IWithdrawalQueue(vm.envAddress("HOLESKY_MOCK_WITHDRAWAL_QUEUE")),
                voting: IAragonVoting(vm.envAddress("HOLESKY_MOCK_DAO_VOTING"))
            });
        }

        return LidoContracts({
            chainId: 17000,
            stETH: IStETH(HOLESKY_ST_ETH),
            wstETH: IWstETH(HOLESKY_WST_ETH),
            withdrawalQueue: IWithdrawalQueue(HOLESKY_WITHDRAWAL_QUEUE),
            voting: IAragonVoting(HOLESKY_DAO_VOTING)
        });
    }

    function validateConfig(DeployConfig memory config) internal pure {
        checkCommitteeQuorum(
            config.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS,
            config.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM,
            "EMERGENCY_ACTIVATION_COMMITTEE"
        );
        checkCommitteeQuorum(
            config.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS,
            config.EMERGENCY_EXECUTION_COMMITTEE_QUORUM,
            "EMERGENCY_EXECUTION_COMMITTEE"
        );

        checkCommitteeQuorum(config.RESEAL_COMMITTEE_MEMBERS, config.RESEAL_COMMITTEE_QUORUM, "RESEAL_COMMITTEE");

        if (
            config.TIEBREAKER_CORE_QUORUM == 0 || config.TIEBREAKER_CORE_QUORUM > config.TIEBREAKER_SUB_COMMITTEES_COUNT
        ) {
            revert InvalidQuorum("TIEBREAKER_CORE", config.TIEBREAKER_CORE_QUORUM);
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT == 0 || config.TIEBREAKER_SUB_COMMITTEES_COUNT > 10) {
            revert InvalidParameter("TIEBREAKER_SUB_COMMITTEES_COUNT");
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_QUORUMS.length != config.TIEBREAKER_SUB_COMMITTEES_COUNT) {
            revert InvalidParameter("TIEBREAKER_SUB_COMMITTEES_QUORUMS");
        }

        checkCommitteeQuorum(
            config.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS,
            config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[0],
            "TIEBREAKER_SUB_COMMITTEE_1"
        );

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 2) {
            checkCommitteeQuorum(
                config.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[1],
                "TIEBREAKER_SUB_COMMITTEE_2"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 3) {
            checkCommitteeQuorum(
                config.TIEBREAKER_SUB_COMMITTEE_3_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[2],
                "TIEBREAKER_SUB_COMMITTEE_3"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 4) {
            checkCommitteeQuorum(
                config.TIEBREAKER_SUB_COMMITTEE_4_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[3],
                "TIEBREAKER_SUB_COMMITTEE_4"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 5) {
            checkCommitteeQuorum(
                config.TIEBREAKER_SUB_COMMITTEE_5_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[4],
                "TIEBREAKER_SUB_COMMITTEE_5"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 6) {
            checkCommitteeQuorum(
                config.TIEBREAKER_SUB_COMMITTEE_6_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[5],
                "TIEBREAKER_SUB_COMMITTEE_6"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 7) {
            checkCommitteeQuorum(
                config.TIEBREAKER_SUB_COMMITTEE_7_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[6],
                "TIEBREAKER_SUB_COMMITTEE_7"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 8) {
            checkCommitteeQuorum(
                config.TIEBREAKER_SUB_COMMITTEE_8_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[7],
                "TIEBREAKER_SUB_COMMITTEE_8"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 9) {
            checkCommitteeQuorum(
                config.TIEBREAKER_SUB_COMMITTEE_9_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[8],
                "TIEBREAKER_SUB_COMMITTEE_9"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT == 10) {
            checkCommitteeQuorum(
                config.TIEBREAKER_SUB_COMMITTEE_10_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[9],
                "TIEBREAKER_SUB_COMMITTEE_10"
            );
        }

        if (config.AFTER_SUBMIT_DELAY > config.MAX_AFTER_SUBMIT_DELAY) {
            revert InvalidParameter("AFTER_SUBMIT_DELAY");
        }

        if (config.AFTER_SCHEDULE_DELAY > config.MAX_AFTER_SCHEDULE_DELAY) {
            revert InvalidParameter("AFTER_SCHEDULE_DELAY");
        }

        if (config.EMERGENCY_MODE_DURATION > config.MAX_EMERGENCY_MODE_DURATION) {
            revert InvalidParameter("EMERGENCY_MODE_DURATION");
        }

        if (config.MIN_TIEBREAKER_ACTIVATION_TIMEOUT > config.TIEBREAKER_ACTIVATION_TIMEOUT) {
            revert InvalidParameter("MIN_TIEBREAKER_ACTIVATION_TIMEOUT");
        }

        if (config.TIEBREAKER_ACTIVATION_TIMEOUT > config.MAX_TIEBREAKER_ACTIVATION_TIMEOUT) {
            revert InvalidParameter("TIEBREAKER_ACTIVATION_TIMEOUT");
        }

        if (config.VETO_SIGNALLING_MIN_DURATION > config.VETO_SIGNALLING_MAX_DURATION) {
            revert InvalidParameter("VETO_SIGNALLING_MIN_DURATION");
        }
    }

    function checkCommitteeQuorum(address[] memory committee, uint256 quorum, string memory message) internal pure {
        if (quorum == 0 || quorum > committee.length) {
            revert InvalidQuorum(message, quorum);
        }
    }

    function printCommittees(DeployConfig memory config) internal view {
        console.log("=================================================");
        console.log("Loaded valid config with the following committees:");

        printCommittee(
            config.EMERGENCY_ACTIVATION_COMMITTEE_MEMBERS,
            config.EMERGENCY_ACTIVATION_COMMITTEE_QUORUM,
            "EmergencyActivationCommittee members, quorum"
        );

        printCommittee(
            config.EMERGENCY_EXECUTION_COMMITTEE_MEMBERS,
            config.EMERGENCY_EXECUTION_COMMITTEE_QUORUM,
            "EmergencyExecutionCommittee members, quorum"
        );

        printCommittee(
            config.TIEBREAKER_SUB_COMMITTEE_1_MEMBERS,
            config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[0],
            "TiebreakerSubCommittee #1 members, quorum"
        );

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 2) {
            printCommittee(
                config.TIEBREAKER_SUB_COMMITTEE_2_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[1],
                "TiebreakerSubCommittee #2 members, quorum"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 3) {
            printCommittee(
                config.TIEBREAKER_SUB_COMMITTEE_3_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[2],
                "TiebreakerSubCommittee #3 members, quorum"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 4) {
            printCommittee(
                config.TIEBREAKER_SUB_COMMITTEE_4_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[3],
                "TiebreakerSubCommittee #4 members, quorum"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 5) {
            printCommittee(
                config.TIEBREAKER_SUB_COMMITTEE_5_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[4],
                "TiebreakerSubCommittee #5 members, quorum"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 6) {
            printCommittee(
                config.TIEBREAKER_SUB_COMMITTEE_6_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[5],
                "TiebreakerSubCommittee #6 members, quorum"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 7) {
            printCommittee(
                config.TIEBREAKER_SUB_COMMITTEE_7_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[6],
                "TiebreakerSubCommittee #7 members, quorum"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 8) {
            printCommittee(
                config.TIEBREAKER_SUB_COMMITTEE_8_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[7],
                "TiebreakerSubCommittee #8 members, quorum"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT >= 9) {
            printCommittee(
                config.TIEBREAKER_SUB_COMMITTEE_9_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[8],
                "TiebreakerSubCommittee #9 members, quorum"
            );
        }

        if (config.TIEBREAKER_SUB_COMMITTEES_COUNT == 10) {
            printCommittee(
                config.TIEBREAKER_SUB_COMMITTEE_10_MEMBERS,
                config.TIEBREAKER_SUB_COMMITTEES_QUORUMS[9],
                "TiebreakerSubCommittee #10 members, quorum"
            );
        }

        printCommittee(
            config.RESEAL_COMMITTEE_MEMBERS, config.RESEAL_COMMITTEE_QUORUM, "ResealCommittee members, quorum"
        );

        console.log("=================================================");
    }

    function printCommittee(address[] memory committee, uint256 quorum, string memory message) internal view {
        console.log(message, quorum, "of", committee.length);
        for (uint256 k = 0; k < committee.length; ++k) {
            console.log(">> #", k, address(committee[k]));
        }
    }
}
