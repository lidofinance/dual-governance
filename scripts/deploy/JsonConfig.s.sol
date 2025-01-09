// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, var-name-mixedcase */

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
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
import {
    DeployConfig,
    LidoContracts,
    CHAIN_NAME_MAINNET_HASH,
    CHAIN_NAME_HOLESKY_HASH,
    CHAIN_NAME_HOLESKY_MOCKS_HASH
} from "./Config.sol";

contract DGDeployJSONConfigProvider is Script {
    error InvalidQuorum(string committee, uint256 quorum);
    error InvalidParameter(string parameter);
    error InvalidChain(string chainName);

    string private configFilePath;

    constructor(string memory _configFilePath) {
        configFilePath = _configFilePath;
    }

    function loadAndValidate() external view returns (DeployConfig memory config) {
        string memory jsonConfig = loadConfigFile();

        config = DeployConfig({
            MIN_EXECUTION_DELAY: Durations.from(stdJson.readUint(jsonConfig, ".MIN_EXECUTION_DELAY")),
            AFTER_SUBMIT_DELAY: Durations.from(stdJson.readUint(jsonConfig, ".AFTER_SUBMIT_DELAY")),
            MAX_AFTER_SUBMIT_DELAY: Durations.from(stdJson.readUint(jsonConfig, ".MAX_AFTER_SUBMIT_DELAY")),
            AFTER_SCHEDULE_DELAY: Durations.from(stdJson.readUint(jsonConfig, ".AFTER_SCHEDULE_DELAY")),
            MAX_AFTER_SCHEDULE_DELAY: Durations.from(stdJson.readUint(jsonConfig, ".MAX_AFTER_SCHEDULE_DELAY")),
            EMERGENCY_MODE_DURATION: Durations.from(stdJson.readUint(jsonConfig, ".EMERGENCY_MODE_DURATION")),
            MAX_EMERGENCY_MODE_DURATION: Durations.from(stdJson.readUint(jsonConfig, ".MAX_EMERGENCY_MODE_DURATION")),
            EMERGENCY_PROTECTION_DURATION: Durations.from(stdJson.readUint(jsonConfig, ".EMERGENCY_PROTECTION_DURATION")),
            MAX_EMERGENCY_PROTECTION_DURATION: Durations.from(
                stdJson.readUint(jsonConfig, ".MAX_EMERGENCY_PROTECTION_DURATION")
            ),
            EMERGENCY_ACTIVATION_COMMITTEE: stdJson.readAddress(jsonConfig, ".EMERGENCY_ACTIVATION_COMMITTEE"),
            EMERGENCY_EXECUTION_COMMITTEE: stdJson.readAddress(jsonConfig, ".EMERGENCY_EXECUTION_COMMITTEE"),
            TIEBREAKER_CORE_QUORUM: stdJson.readUint(jsonConfig, ".TIEBREAKER_CORE_QUORUM"),
            TIEBREAKER_EXECUTION_DELAY: Durations.from(stdJson.readUint(jsonConfig, ".TIEBREAKER_EXECUTION_DELAY")),
            TIEBREAKER_SUB_COMMITTEES_COUNT: stdJson.readUint(jsonConfig, ".TIEBREAKER_SUB_COMMITTEES_COUNT"),
            TIEBREAKER_SUB_COMMITTEE_1_MEMBERS: stdJson.readAddressArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_1_MEMBERS"),
            TIEBREAKER_SUB_COMMITTEE_2_MEMBERS: stdJson.readAddressArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_2_MEMBERS"),
            TIEBREAKER_SUB_COMMITTEE_3_MEMBERS: stdJson.readAddressArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_3_MEMBERS"),
            TIEBREAKER_SUB_COMMITTEE_4_MEMBERS: stdJson.readAddressArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_4_MEMBERS"),
            TIEBREAKER_SUB_COMMITTEE_5_MEMBERS: stdJson.readAddressArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_5_MEMBERS"),
            TIEBREAKER_SUB_COMMITTEE_6_MEMBERS: stdJson.readAddressArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_6_MEMBERS"),
            TIEBREAKER_SUB_COMMITTEE_7_MEMBERS: stdJson.readAddressArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_7_MEMBERS"),
            TIEBREAKER_SUB_COMMITTEE_8_MEMBERS: stdJson.readAddressArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_8_MEMBERS"),
            TIEBREAKER_SUB_COMMITTEE_9_MEMBERS: stdJson.readAddressArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_9_MEMBERS"),
            TIEBREAKER_SUB_COMMITTEE_10_MEMBERS: stdJson.readAddressArray(
                jsonConfig, ".TIEBREAKER_SUB_COMMITTEE_10_MEMBERS"
            ),
            TIEBREAKER_SUB_COMMITTEES_QUORUMS: stdJson.readUintArray(jsonConfig, ".TIEBREAKER_SUB_COMMITTEES_QUORUMS"),
            RESEAL_COMMITTEE: stdJson.readAddress(jsonConfig, ".RESEAL_COMMITTEE"),
            MIN_WITHDRAWALS_BATCH_SIZE: stdJson.readUint(jsonConfig, ".MIN_WITHDRAWALS_BATCH_SIZE"),
            MIN_TIEBREAKER_ACTIVATION_TIMEOUT: Durations.from(
                stdJson.readUint(jsonConfig, ".MIN_TIEBREAKER_ACTIVATION_TIMEOUT")
            ),
            TIEBREAKER_ACTIVATION_TIMEOUT: Durations.from(stdJson.readUint(jsonConfig, ".TIEBREAKER_ACTIVATION_TIMEOUT")),
            MAX_TIEBREAKER_ACTIVATION_TIMEOUT: Durations.from(
                stdJson.readUint(jsonConfig, ".MAX_TIEBREAKER_ACTIVATION_TIMEOUT")
            ),
            MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT: stdJson.readUint(jsonConfig, ".MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT"),
            FIRST_SEAL_RAGE_QUIT_SUPPORT: PercentsD16.fromBasisPoints(
                stdJson.readUint(jsonConfig, ".FIRST_SEAL_RAGE_QUIT_SUPPORT")
            ),
            SECOND_SEAL_RAGE_QUIT_SUPPORT: PercentsD16.fromBasisPoints(
                stdJson.readUint(jsonConfig, ".SECOND_SEAL_RAGE_QUIT_SUPPORT")
            ),
            MIN_ASSETS_LOCK_DURATION: Durations.from(stdJson.readUint(jsonConfig, ".MIN_ASSETS_LOCK_DURATION")),
            MAX_MIN_ASSETS_LOCK_DURATION: Durations.from(stdJson.readUint(jsonConfig, ".MAX_MIN_ASSETS_LOCK_DURATION")),
            VETO_SIGNALLING_MIN_DURATION: Durations.from(stdJson.readUint(jsonConfig, ".VETO_SIGNALLING_MIN_DURATION")),
            VETO_SIGNALLING_MAX_DURATION: Durations.from(stdJson.readUint(jsonConfig, ".VETO_SIGNALLING_MAX_DURATION")),
            VETO_SIGNALLING_MIN_ACTIVE_DURATION: Durations.from(
                stdJson.readUint(jsonConfig, ".VETO_SIGNALLING_MIN_ACTIVE_DURATION")
            ),
            VETO_SIGNALLING_DEACTIVATION_MAX_DURATION: Durations.from(
                stdJson.readUint(jsonConfig, ".VETO_SIGNALLING_DEACTIVATION_MAX_DURATION")
            ),
            VETO_COOLDOWN_DURATION: Durations.from(stdJson.readUint(jsonConfig, ".VETO_COOLDOWN_DURATION")),
            RAGE_QUIT_EXTENSION_PERIOD_DURATION: Durations.from(
                stdJson.readUint(jsonConfig, ".RAGE_QUIT_EXTENSION_PERIOD_DURATION")
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY: Durations.from(
                stdJson.readUint(jsonConfig, ".RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY")
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY: Durations.from(
                stdJson.readUint(jsonConfig, ".RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY")
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH: Durations.from(
                stdJson.readUint(jsonConfig, ".RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH")
            ),
            TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER: stdJson.readAddress(
                jsonConfig, ".TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER"
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
                voting: MAINNET_DAO_VOTING
            });
        }

        if (keccak256(bytes(chainName)) == CHAIN_NAME_HOLESKY_MOCKS_HASH) {
            string memory jsonConfig = loadConfigFile();

            return LidoContracts({
                chainId: 17000,
                stETH: IStETH(stdJson.readAddress(jsonConfig, ".HOLESKY_MOCK_ST_ETH")),
                wstETH: IWstETH(stdJson.readAddress(jsonConfig, ".HOLESKY_MOCK_WST_ETH")),
                withdrawalQueue: IWithdrawalQueue(stdJson.readAddress(jsonConfig, ".HOLESKY_MOCK_WITHDRAWAL_QUEUE")),
                voting: stdJson.readAddress(jsonConfig, ".HOLESKY_MOCK_DAO_VOTING")
            });
        }

        return LidoContracts({
            chainId: 17000,
            stETH: IStETH(HOLESKY_ST_ETH),
            wstETH: IWstETH(HOLESKY_WST_ETH),
            withdrawalQueue: IWithdrawalQueue(HOLESKY_WITHDRAWAL_QUEUE),
            voting: HOLESKY_DAO_VOTING
        });
    }

    function validateConfig(DeployConfig memory config) internal pure {
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

        if (config.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT == 0) {
            revert InvalidParameter("MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT");
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

    function printCommittees(DeployConfig memory config) internal pure {
        console.log("=================================================");
        console.log("Loaded valid config with the following committees:");

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

        console.log("=================================================");
    }

    function printCommittee(address[] memory committee, uint256 quorum, string memory message) internal pure {
        console.log(message, quorum, "of", committee.length);
        for (uint256 k = 0; k < committee.length; ++k) {
            console.log(">> #", k, address(committee[k]));
        }
    }

    function loadConfigFile() internal view returns (string memory jsonConfig) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", configFilePath);
        jsonConfig = vm.readFile(path);
    }

    function writeDeployedAddressesToConfigFile(string memory deployedAddrsJson) external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", configFilePath);

        stdJson.write(deployedAddrsJson, path, ".deployedContracts");
    }
}
