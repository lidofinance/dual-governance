// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable var-name-mixedcase */

import {stdJson} from "forge-std/stdJson.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

import {JsonParser} from "../../utils/JsonParser.sol";
import {DeployConfig, LidoContracts, TiebreakerDeployConfig, TiebreakerSubCommitteeDeployConfig} from "./Config.sol";

contract JsonDeployConfigParser {
    using stdJson for string;
    using JsonParser for string;

    function parse(string memory configFile) external pure returns (DeployConfig memory config) {
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
            EMERGENCY_PROTECTION_DURATION: configFile.readDuration(
                ".EMERGENCY_PROTECTED_TIMELOCK_CONFIG.EMERGENCY_PROTECTION_DURATION"
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

    function getHoleskyMockLidoAddresses(string memory configFile) external pure returns (LidoContracts memory) {
        return LidoContracts({
            chainId: 17000,
            stETH: IStETH(configFile.readAddress(".HOLESKY_MOCK_CONTRACTS.ST_ETH")),
            wstETH: IWstETH(configFile.readAddress(".HOLESKY_MOCK_CONTRACTS.WST_ETH")),
            withdrawalQueue: IWithdrawalQueue(configFile.readAddress(".HOLESKY_MOCK_CONTRACTS.WITHDRAWAL_QUEUE")),
            voting: configFile.readAddress(".HOLESKY_MOCK_CONTRACTS.DAO_VOTING")
        });
    }
}
