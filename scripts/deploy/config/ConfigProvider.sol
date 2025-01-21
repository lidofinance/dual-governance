// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, var-name-mixedcase */

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
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
import {SerializedJson, SerializedJsonLib} from "../../utils/SerializedJson.sol";
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
import {ConfigFileReader} from "./ConfigFileReader.sol";

string constant CONFIG_FILES_DIR = "deploy-config";

contract DGDeployConfigProvider {
    using ConfigFileReader for ConfigFileReader.Context;
    using SerializedJsonLib for SerializedJson;

    // solhint-disable-next-line const-name-snakecase
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error InvalidQuorum(string committee, uint256 quorum);
    error InvalidParameter(string parameter);
    error InvalidChain(string chainName);

    string private _configFileName;

    constructor(string memory configFileName) {
        _configFileName = configFileName;
    }

    function loadAndValidate() external view returns (DeployConfig memory config) {
        ConfigFileReader.Context memory configFile = _loadConfigFile();

        config = _parse(configFile);

        _validateConfig(config);
        _printConfigAndCommittees(config, configFile.content);
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
            ConfigFileReader.Context memory configFile = _loadConfigFile();

            return _getHoleskyMockLidoAddresses(configFile);
        }

        return LidoContracts({
            chainId: 17000,
            stETH: IStETH(HOLESKY_ST_ETH),
            wstETH: IWstETH(HOLESKY_WST_ETH),
            withdrawalQueue: IWithdrawalQueue(HOLESKY_WITHDRAWAL_QUEUE),
            voting: HOLESKY_DAO_VOTING
        });
    }

    function _parse(ConfigFileReader.Context memory configFile) internal pure returns (DeployConfig memory config) {
        TiebreakerSubCommitteeDeployConfig memory influencersSubCommitteeConfig = TiebreakerSubCommitteeDeployConfig({
            members: configFile.readAddressArray(".TIEBREAKER_CONFIG.INFLUENCERS.MEMBERS"),
            quorum: configFile.readUint(".TIEBREAKER_CONFIG.INFLUENCERS.QUORUM")
        });

        TiebreakerSubCommitteeDeployConfig memory nodeOperatorsSubCommitteeConfig = TiebreakerSubCommitteeDeployConfig({
            members: configFile.readAddressArray(".TIEBREAKER_CONFIG.NODE_OPERATORS.MEMBERS"),
            quorum: configFile.readUint(".TIEBREAKER_CONFIG.NODE_OPERATORS.QUORUM")
        });

        TiebreakerSubCommitteeDeployConfig memory protocolsSubCommitteeConfig = TiebreakerSubCommitteeDeployConfig({
            members: configFile.readAddressArray(".TIEBREAKER_CONFIG.PROTOCOLS.MEMBERS"),
            quorum: configFile.readUint(".TIEBREAKER_CONFIG.PROTOCOLS.QUORUM")
        });

        TiebreakerDeployConfig memory tiebreakerConfig = TiebreakerDeployConfig({
            activationTimeout: configFile.readDuration(".TIEBREAKER_CONFIG.ACTIVATION_TIMEOUT"),
            minActivationTimeout: configFile.readDuration(".TIEBREAKER_CONFIG.MIN_ACTIVATION_TIMEOUT"),
            maxActivationTimeout: configFile.readDuration(".TIEBREAKER_CONFIG.MAX_ACTIVATION_TIMEOUT"),
            executionDelay: configFile.readDuration(".TIEBREAKER_CONFIG.EXECUTION_DELAY"),
            influencers: influencersSubCommitteeConfig,
            nodeOperators: nodeOperatorsSubCommitteeConfig,
            protocols: protocolsSubCommitteeConfig,
            quorum: configFile.readUint(".TIEBREAKER_CONFIG.QUORUM"),
            sealableWithdrawalBlockers: configFile.readAddressArray(".TIEBREAKER_CONFIG.SEALABLE_WITHDRAWAL_BLOCKERS")
        });

        config = DeployConfig({
            //
            // EMERGENCY_PROTECTED_TIMELOCK_CONFIG
            //
            MIN_EXECUTION_DELAY: configFile.readDuration(".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MIN_EXECUTION_DELAY"),
            AFTER_SUBMIT_DELAY: configFile.readDuration(".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.AFTER_SUBMIT_DELAY"),
            MAX_AFTER_SUBMIT_DELAY: configFile.readDuration(".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MAX_AFTER_SUBMIT_DELAY"),
            AFTER_SCHEDULE_DELAY: configFile.readDuration(".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.AFTER_SCHEDULE_DELAY"),
            MAX_AFTER_SCHEDULE_DELAY: configFile.readDuration(
                ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MAX_AFTER_SCHEDULE_DELAY"
            ),
            EMERGENCY_MODE_DURATION: configFile.readDuration(".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.EMERGENCY_MODE_DURATION"),
            MAX_EMERGENCY_MODE_DURATION: configFile.readDuration(
                ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MAX_EMERGENCY_MODE_DURATION"
            ),
            EMERGENCY_PROTECTION_END_DATE: configFile.readTimestamp(
                ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.EMERGENCY_PROTECTION_END_DATE"
            ),
            MAX_EMERGENCY_PROTECTION_DURATION: configFile.readDuration(
                ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.MAX_EMERGENCY_PROTECTION_DURATION"
            ),
            TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER: configFile.readAddress(
                ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER"
            ),
            //
            // DUAL_GOVERNANCE_CONFIG
            //
            EMERGENCY_ACTIVATION_COMMITTEE: configFile.readAddress(".DUAL_GOVERNANCE_CONFIG.EMERGENCY_ACTIVATION_COMMITTEE"),
            EMERGENCY_EXECUTION_COMMITTEE: configFile.readAddress(".DUAL_GOVERNANCE_CONFIG.EMERGENCY_EXECUTION_COMMITTEE"),
            tiebreakerConfig: tiebreakerConfig,
            RESEAL_COMMITTEE: configFile.readAddress(".DUAL_GOVERNANCE_CONFIG.RESEAL_COMMITTEE"),
            MIN_WITHDRAWALS_BATCH_SIZE: configFile.readUint(".DUAL_GOVERNANCE_CONFIG.MIN_WITHDRAWALS_BATCH_SIZE"),
            MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT: configFile.readUint(
                ".DUAL_GOVERNANCE_CONFIG.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT"
            ),
            FIRST_SEAL_RAGE_QUIT_SUPPORT: configFile.readPercentD16BP(
                ".DUAL_GOVERNANCE_CONFIG.FIRST_SEAL_RAGE_QUIT_SUPPORT"
            ),
            SECOND_SEAL_RAGE_QUIT_SUPPORT: configFile.readPercentD16BP(
                ".DUAL_GOVERNANCE_CONFIG.SECOND_SEAL_RAGE_QUIT_SUPPORT"
            ),
            MIN_ASSETS_LOCK_DURATION: configFile.readDuration(".DUAL_GOVERNANCE_CONFIG.MIN_ASSETS_LOCK_DURATION"),
            MAX_MIN_ASSETS_LOCK_DURATION: configFile.readDuration(".DUAL_GOVERNANCE_CONFIG.MAX_MIN_ASSETS_LOCK_DURATION"),
            VETO_SIGNALLING_MIN_DURATION: configFile.readDuration(".DUAL_GOVERNANCE_CONFIG.VETO_SIGNALLING_MIN_DURATION"),
            VETO_SIGNALLING_MAX_DURATION: configFile.readDuration(".DUAL_GOVERNANCE_CONFIG.VETO_SIGNALLING_MAX_DURATION"),
            VETO_SIGNALLING_MIN_ACTIVE_DURATION: configFile.readDuration(
                ".DUAL_GOVERNANCE_CONFIG.VETO_SIGNALLING_MIN_ACTIVE_DURATION"
            ),
            VETO_SIGNALLING_DEACTIVATION_MAX_DURATION: configFile.readDuration(
                ".DUAL_GOVERNANCE_CONFIG.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION"
            ),
            VETO_COOLDOWN_DURATION: configFile.readDuration(".DUAL_GOVERNANCE_CONFIG.VETO_COOLDOWN_DURATION"),
            RAGE_QUIT_EXTENSION_PERIOD_DURATION: configFile.readDuration(
                ".DUAL_GOVERNANCE_CONFIG.RAGE_QUIT_EXTENSION_PERIOD_DURATION"
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY: configFile.readDuration(
                ".DUAL_GOVERNANCE_CONFIG.RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY"
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY: configFile.readDuration(
                ".DUAL_GOVERNANCE_CONFIG.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY"
            ),
            RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH: configFile.readDuration(
                ".DUAL_GOVERNANCE_CONFIG.RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH"
            )
        });
    }

    function _getHoleskyMockLidoAddresses(ConfigFileReader.Context memory configFile)
        internal
        pure
        returns (LidoContracts memory)
    {
        return LidoContracts({
            chainId: 17000,
            stETH: IStETH(configFile.readAddress(".HOLESKY_MOCK_CONTRACTS.ST_ETH")),
            wstETH: IWstETH(configFile.readAddress(".HOLESKY_MOCK_CONTRACTS.WST_ETH")),
            withdrawalQueue: IWithdrawalQueue(configFile.readAddress(".HOLESKY_MOCK_CONTRACTS.WITHDRAWAL_QUEUE")),
            voting: configFile.readAddress(".HOLESKY_MOCK_CONTRACTS.DAO_VOTING")
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

        if (config.tiebreakerConfig.sealableWithdrawalBlockers.length > config.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT) {
            revert InvalidParameter("TIEBREAKER_CONFIG.SEALABLE_WITHDRAWAL_BLOCKERS");
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

    function _printConfigAndCommittees(DeployConfig memory config, string memory configFile) internal pure {
        console.log("=================================================");
        console.log("Loaded valid config file:");
        console.log(configFile);
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

    function _loadConfigFile() internal view returns (ConfigFileReader.Context memory configFile) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", CONFIG_FILES_DIR, "/", _configFileName);
        configFile = ConfigFileReader.load(path);
    }

    function serialize(
        DeployConfig memory config,
        SerializedJson memory json
    ) external returns (SerializedJson memory) {
        SerializedJson memory emergencyProtectedTimelockConfig = SerializedJsonLib.getInstance();
        emergencyProtectedTimelockConfig.set("MIN_EXECUTION_DELAY", config.MIN_EXECUTION_DELAY);
        emergencyProtectedTimelockConfig.set("AFTER_SUBMIT_DELAY", config.AFTER_SUBMIT_DELAY);
        emergencyProtectedTimelockConfig.set("MAX_AFTER_SUBMIT_DELAY", config.MAX_AFTER_SUBMIT_DELAY);
        emergencyProtectedTimelockConfig.set("AFTER_SCHEDULE_DELAY", config.AFTER_SCHEDULE_DELAY);
        emergencyProtectedTimelockConfig.set("MAX_AFTER_SCHEDULE_DELAY", config.MAX_AFTER_SCHEDULE_DELAY);
        emergencyProtectedTimelockConfig.set("EMERGENCY_MODE_DURATION", config.EMERGENCY_MODE_DURATION);
        emergencyProtectedTimelockConfig.set("MAX_EMERGENCY_MODE_DURATION", config.MAX_EMERGENCY_MODE_DURATION);
        emergencyProtectedTimelockConfig.set("EMERGENCY_PROTECTION_END_DATE", config.EMERGENCY_PROTECTION_END_DATE);
        emergencyProtectedTimelockConfig.set(
            "MAX_EMERGENCY_PROTECTION_DURATION", config.MAX_EMERGENCY_PROTECTION_DURATION
        );
        emergencyProtectedTimelockConfig.set(
            "TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER", config.TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER
        );
        json.set("EMERGENCY_PROTECTED_TIMELOCK_CONFIG", emergencyProtectedTimelockConfig.str);

        SerializedJson memory dualGovernanceConfig = SerializedJsonLib.getInstance();
        dualGovernanceConfig.set("EMERGENCY_ACTIVATION_COMMITTEE", config.EMERGENCY_ACTIVATION_COMMITTEE);
        dualGovernanceConfig.set("EMERGENCY_EXECUTION_COMMITTEE", config.EMERGENCY_EXECUTION_COMMITTEE);
        dualGovernanceConfig.set("RESEAL_COMMITTEE", config.RESEAL_COMMITTEE);
        dualGovernanceConfig.set("MIN_WITHDRAWALS_BATCH_SIZE", config.MIN_WITHDRAWALS_BATCH_SIZE);
        dualGovernanceConfig.set(
            "MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT", config.MAX_SEALABLE_WITHDRAWAL_BLOCKERS_COUNT
        );
        dualGovernanceConfig.setPercentD16BP("FIRST_SEAL_RAGE_QUIT_SUPPORT", config.FIRST_SEAL_RAGE_QUIT_SUPPORT);
        dualGovernanceConfig.setPercentD16BP("SECOND_SEAL_RAGE_QUIT_SUPPORT", config.SECOND_SEAL_RAGE_QUIT_SUPPORT);
        dualGovernanceConfig.set("MIN_ASSETS_LOCK_DURATION", config.MIN_ASSETS_LOCK_DURATION);
        dualGovernanceConfig.set("MAX_MIN_ASSETS_LOCK_DURATION", config.MAX_MIN_ASSETS_LOCK_DURATION);
        dualGovernanceConfig.set("VETO_SIGNALLING_MIN_DURATION", config.VETO_SIGNALLING_MIN_DURATION);
        dualGovernanceConfig.set("VETO_SIGNALLING_MAX_DURATION", config.VETO_SIGNALLING_MAX_DURATION);
        dualGovernanceConfig.set("VETO_SIGNALLING_MIN_ACTIVE_DURATION", config.VETO_SIGNALLING_MIN_ACTIVE_DURATION);
        dualGovernanceConfig.set(
            "VETO_SIGNALLING_DEACTIVATION_MAX_DURATION", config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION
        );
        dualGovernanceConfig.set("VETO_COOLDOWN_DURATION", config.VETO_COOLDOWN_DURATION);
        dualGovernanceConfig.set("RAGE_QUIT_EXTENSION_PERIOD_DURATION", config.RAGE_QUIT_EXTENSION_PERIOD_DURATION);
        dualGovernanceConfig.set("RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY", config.RAGE_QUIT_ETH_WITHDRAWALS_MIN_DELAY);
        dualGovernanceConfig.set("RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY", config.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY);
        dualGovernanceConfig.set(
            "RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH", config.RAGE_QUIT_ETH_WITHDRAWALS_DELAY_GROWTH
        );
        json.set("DUAL_GOVERNANCE_CONFIG", dualGovernanceConfig.str);

        SerializedJson memory tiebreakerInfluencers = SerializedJsonLib.getInstance();
        tiebreakerInfluencers.set("MEMBERS", config.tiebreakerConfig.influencers.members);
        tiebreakerInfluencers.set("QUORUM", config.tiebreakerConfig.influencers.quorum);

        SerializedJson memory tiebreakerNodeOperators = SerializedJsonLib.getInstance();
        tiebreakerNodeOperators.set("MEMBERS", config.tiebreakerConfig.nodeOperators.members);
        tiebreakerNodeOperators.set("QUORUM", config.tiebreakerConfig.nodeOperators.quorum);

        SerializedJson memory tiebreakerProtocols = SerializedJsonLib.getInstance();
        tiebreakerProtocols.set("MEMBERS", config.tiebreakerConfig.protocols.members);
        tiebreakerProtocols.set("QUORUM", config.tiebreakerConfig.protocols.quorum);

        SerializedJson memory tiebreakerConfig = SerializedJsonLib.getInstance();
        tiebreakerConfig.set("INFLUENCERS", tiebreakerInfluencers.str);
        tiebreakerConfig.set("NODE_OPERATORS", tiebreakerNodeOperators.str);
        tiebreakerConfig.set("PROTOCOLS", tiebreakerProtocols.str);
        tiebreakerConfig.set("ACTIVATION_TIMEOUT", config.tiebreakerConfig.activationTimeout);
        tiebreakerConfig.set("MIN_ACTIVATION_TIMEOUT", config.tiebreakerConfig.minActivationTimeout);
        tiebreakerConfig.set("MAX_ACTIVATION_TIMEOUT", config.tiebreakerConfig.maxActivationTimeout);
        tiebreakerConfig.set("EXECUTION_DELAY", config.tiebreakerConfig.executionDelay);
        tiebreakerConfig.set("QUORUM", config.tiebreakerConfig.quorum);
        tiebreakerConfig.set("SEALABLE_WITHDRAWAL_BLOCKERS", config.tiebreakerConfig.sealableWithdrawalBlockers);

        json.set("TIEBREAKER_CONFIG", tiebreakerConfig.str);

        return json;
    }

    function serializeLidoAddresses(
        string memory chainName,
        LidoContracts memory lidoContracts,
        SerializedJson memory json
    ) external returns (SerializedJson memory) {
        if (keccak256(bytes(chainName)) == CHAIN_NAME_HOLESKY_MOCKS_HASH) {
            SerializedJson memory holeskyMocks = SerializedJsonLib.getInstance();

            holeskyMocks.set("ST_ETH", address(lidoContracts.stETH));
            holeskyMocks.set("WST_ETH", address(lidoContracts.wstETH));
            holeskyMocks.set("WITHDRAWAL_QUEUE", address(lidoContracts.withdrawalQueue));
            holeskyMocks.set("DAO_VOTING", address(lidoContracts.voting));

            json.set("HOLESKY_MOCK_CONTRACTS", holeskyMocks.str);
        }
        return json;
    }
}
