// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, var-name-mixedcase */

import {Script} from "forge-std/Script.sol";
import {stdToml} from "forge-std/StdToml.sol";
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
    TiebreakerDeployConfig,
    TiebreakerSubCommitteeDeployConfig,
    CHAIN_NAME_MAINNET_HASH,
    CHAIN_NAME_HOLESKY_HASH,
    CHAIN_NAME_HOLESKY_MOCKS_HASH,
    TIEBREAKER_SUB_COMMITTEES_COUNT
} from "./Config.sol";

string constant CONFIG_FILES_DIR = "deploy-config";

contract DGDeployTOMLConfigProvider is Script {
    error InvalidQuorum(string committee, uint256 quorum);
    error InvalidParameter(string parameter);
    error InvalidChain(string chainName);

    string private _configFileName;

    constructor(string memory configFileName) {
        _configFileName = configFileName;
    }

    function loadAndValidate() external view returns (DeployConfig memory config) {
        string memory tomlConfig = _loadConfigFile();

        TiebreakerSubCommitteeDeployConfig memory influencersSubCommitteeConfig = TiebreakerSubCommitteeDeployConfig({
            members: stdToml.readAddressArray(tomlConfig, ".TIEBREAKER_CONFIG.INFLUENCERS.MEMBERS"),
            quorum: stdToml.readUint(tomlConfig, ".TIEBREAKER_CONFIG.INFLUENCERS.QUORUM")
        });

        TiebreakerSubCommitteeDeployConfig memory nodeOperatorsSubCommitteeConfig = TiebreakerSubCommitteeDeployConfig({
            members: stdToml.readAddressArray(tomlConfig, ".TIEBREAKER_CONFIG.NODE_OPERATORS.MEMBERS"),
            quorum: stdToml.readUint(tomlConfig, ".TIEBREAKER_CONFIG.NODE_OPERATORS.QUORUM")
        });

        TiebreakerSubCommitteeDeployConfig memory protocolsSubCommitteeConfig = TiebreakerSubCommitteeDeployConfig({
            members: stdToml.readAddressArray(tomlConfig, ".TIEBREAKER_CONFIG.PROTOCOLS.MEMBERS"),
            quorum: stdToml.readUint(tomlConfig, ".TIEBREAKER_CONFIG.PROTOCOLS.QUORUM")
        });

        TiebreakerDeployConfig memory tiebreakerConfig = TiebreakerDeployConfig({
            activationTimeout: Durations.from(stdToml.readUint(tomlConfig, ".TIEBREAKER_CONFIG.ACTIVATION_TIMEOUT")),
            minActivationTimeout: Durations.from(stdToml.readUint(tomlConfig, ".TIEBREAKER_CONFIG.MIN_ACTIVATION_TIMEOUT")),
            maxActivationTimeout: Durations.from(stdToml.readUint(tomlConfig, ".TIEBREAKER_CONFIG.MAX_ACTIVATION_TIMEOUT")),
            executionDelay: Durations.from(stdToml.readUint(tomlConfig, ".TIEBREAKER_CONFIG.EXECUTION_DELAY")),
            influencers: influencersSubCommitteeConfig,
            nodeOperators: nodeOperatorsSubCommitteeConfig,
            protocols: protocolsSubCommitteeConfig,
            quorum: stdToml.readUint(tomlConfig, ".TIEBREAKER_CONFIG.QUORUM")
        });

        config = DeployConfig({
            // EMERGENCY_PROTECTED_TIMELOCK_CONFIG
            MIN_EXECUTION_DELAY: Durations.from(
                stdToml.readUint(tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MIN_EXECUTION_DELAY")
            ),
            AFTER_SUBMIT_DELAY: Durations.from(
                stdToml.readUint(tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.AFTER_SUBMIT_DELAY")
            ),
            MAX_AFTER_SUBMIT_DELAY: Durations.from(
                stdToml.readUint(tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MAX_AFTER_SUBMIT_DELAY")
            ),
            AFTER_SCHEDULE_DELAY: Durations.from(
                stdToml.readUint(tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.AFTER_SCHEDULE_DELAY")
            ),
            MAX_AFTER_SCHEDULE_DELAY: Durations.from(
                stdToml.readUint(tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MAX_AFTER_SCHEDULE_DELAY")
            ),
            EMERGENCY_MODE_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.EMERGENCY_MODE_DURATION")
            ),
            MAX_EMERGENCY_MODE_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MAX_EMERGENCY_MODE_DURATION")
            ),
            EMERGENCY_PROTECTION_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.EMERGENCY_PROTECTION_DURATION")
            ),
            MAX_EMERGENCY_PROTECTION_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MAX_EMERGENCY_PROTECTION_DURATION")
            ),
            TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER: stdToml.readAddress(
                tomlConfig, ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER"
            ),
            // DUAL_GOVERNANCE_CONFIG
            EMERGENCY_ACTIVATION_COMMITTEE: stdToml.readAddress(
                tomlConfig, ".DUAL_GOVERNANCE_CONFIG.EMERGENCY_ACTIVATION_COMMITTEE"
            ),
            EMERGENCY_EXECUTION_COMMITTEE: stdToml.readAddress(
                tomlConfig, ".DUAL_GOVERNANCE_CONFIG.EMERGENCY_EXECUTION_COMMITTEE"
            ),
            tiebreakerConfig: tiebreakerConfig,
            RESEAL_COMMITTEE: stdToml.readAddress(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.RESEAL_COMMITTEE"),
            MIN_WITHDRAWALS_BATCH_SIZE: stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.MIN_WITHDRAWALS_BATCH_SIZE"),
            MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT: stdToml.readUint(
                tomlConfig, ".DUAL_GOVERNANCE_CONFIG.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT"
            ),
            FIRST_SEAL_RAGE_QUIT_SUPPORT: PercentsD16.fromBasisPoints(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.FIRST_SEAL_RAGE_QUIT_SUPPORT")
            ),
            SECOND_SEAL_RAGE_QUIT_SUPPORT: PercentsD16.fromBasisPoints(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.SECOND_SEAL_RAGE_QUIT_SUPPORT")
            ),
            MIN_ASSETS_LOCK_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.MIN_ASSETS_LOCK_DURATION")
            ),
            MAX_MIN_ASSETS_LOCK_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.MAX_MIN_ASSETS_LOCK_DURATION")
            ),
            VETO_SIGNALLING_MIN_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.VETO_SIGNALLING_MIN_DURATION")
            ),
            VETO_SIGNALLING_MAX_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.VETO_SIGNALLING_MAX_DURATION")
            ),
            VETO_SIGNALLING_MIN_ACTIVE_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.VETO_SIGNALLING_MIN_ACTIVE_DURATION")
            ),
            VETO_SIGNALLING_DEACTIVATION_MAX_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION")
            ),
            VETO_COOLDOWN_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.VETO_COOLDOWN_DURATION")
            ),
            RAGE_QUIT_EXTENSION_PERIOD_DURATION: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.RAGE_QUIT_EXTENSION_PERIOD_DURATION")
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY")
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY")
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH: Durations.from(
                stdToml.readUint(tomlConfig, ".DUAL_GOVERNANCE_CONFIG.RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH")
            )
        });

        _validateConfig(config);
        _printConfigAndCommittees(config, tomlConfig);
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
            string memory tomlConfig = _loadConfigFile();

            return LidoContracts({
                chainId: 17000,
                stETH: IStETH(stdToml.readAddress(tomlConfig, ".HOLESKY_MOCK_CONTRACTS.ST_ETH")),
                wstETH: IWstETH(stdToml.readAddress(tomlConfig, ".HOLESKY_MOCK_CONTRACTS.WST_ETH")),
                withdrawalQueue: IWithdrawalQueue(
                    stdToml.readAddress(tomlConfig, ".HOLESKY_MOCK_CONTRACTS.WITHDRAWAL_QUEUE")
                ),
                voting: stdToml.readAddress(tomlConfig, ".HOLESKY_MOCK_CONTRACTS.DAO_VOTING")
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

    function _validateConfig(DeployConfig memory config) internal pure {
        if (config.tiebreakerConfig.quorum == 0 || config.tiebreakerConfig.quorum > TIEBREAKER_SUB_COMMITTEES_COUNT) {
            revert InvalidQuorum("TIEBREAKER_CORE", config.tiebreakerConfig.quorum);
        }

        _checkCommitteeQuorum(config.tiebreakerConfig.influencers, "TIEBREAKER_CONFIG.INFLUENCERS");

        _checkCommitteeQuorum(config.tiebreakerConfig.nodeOperators, "TIEBREAKER_CONFIG.NODE_OPERATORS");

        _checkCommitteeQuorum(config.tiebreakerConfig.protocols, "TIEBREAKER_CONFIG.PROTOCOLS");

        if (config.AFTER_SUBMIT_DELAY > config.MAX_AFTER_SUBMIT_DELAY) {
            revert InvalidParameter("AFTER_SUBMIT_DELAY");
        }

        if (config.AFTER_SCHEDULE_DELAY > config.MAX_AFTER_SCHEDULE_DELAY) {
            revert InvalidParameter("AFTER_SCHEDULE_DELAY");
        }

        if (config.EMERGENCY_MODE_DURATION > config.MAX_EMERGENCY_MODE_DURATION) {
            revert InvalidParameter("EMERGENCY_MODE_DURATION");
        }

        if (config.tiebreakerConfig.minActivationTimeout > config.tiebreakerConfig.activationTimeout) {
            revert InvalidParameter("TIEBREAKER_CONFIG.MIN_ACTIVATION_TIMEOUT");
        }

        if (config.tiebreakerConfig.activationTimeout > config.tiebreakerConfig.maxActivationTimeout) {
            revert InvalidParameter("TIEBREAKER_CONFIG.ACTIVATION_TIMEOUT");
        }

        if (config.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT == 0) {
            revert InvalidParameter("MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT");
        }

        if (config.VETO_SIGNALLING_MIN_DURATION > config.VETO_SIGNALLING_MAX_DURATION) {
            revert InvalidParameter("VETO_SIGNALLING_MIN_DURATION");
        }
    }

    function _checkCommitteeQuorum(
        TiebreakerSubCommitteeDeployConfig memory committee,
        string memory message
    ) internal pure {
        if (committee.quorum == 0 || committee.quorum > committee.members.length) {
            revert InvalidQuorum(message, committee.quorum);
        }
    }

    function _printConfigAndCommittees(DeployConfig memory config, string memory tomlConfig) internal pure {
        console.log("=================================================");
        console.log("Loaded valid config file:");
        console.log(tomlConfig);
        console.log("=================================================");
        console.log("The Tiebreaker committee in the config consists of the following subcommittees:");

        _printCommittee(config.tiebreakerConfig.influencers, "TiebreakerSubCommittee #1 (influencers) members, quorum");

        _printCommittee(
            config.tiebreakerConfig.nodeOperators, "TiebreakerSubCommittee #2 (nodeOperators) members, quorum"
        );

        _printCommittee(config.tiebreakerConfig.protocols, "TiebreakerSubCommittee #3 (protocols) members, quorum");

        console.log("=================================================");
    }

    function _printCommittee(
        TiebreakerSubCommitteeDeployConfig memory committee,
        string memory message
    ) internal pure {
        console.log(message, committee.quorum, "of", committee.members.length);
        for (uint256 k = 0; k < committee.members.length; ++k) {
            console.log(">> #", k, address(committee.members[k]));
        }
    }

    function _loadConfigFile() internal view returns (string memory tomlConfig) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", CONFIG_FILES_DIR, "/", _configFileName);
        tomlConfig = vm.readFile(path);
    }

    function writeDeployedAddressesToConfigFile(string memory deployedAddrsJson) external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", CONFIG_FILES_DIR, "/", _configFileName);

        stdToml.write(deployedAddrsJson, path, ".DEPLOYED_CONTRACTS");
        console.log(
            "The deployed contracts' addresses are written in the _config_ file",
            path,
            "to the 'DEPLOYED_CONTRACTS' section"
        );
    }
}
