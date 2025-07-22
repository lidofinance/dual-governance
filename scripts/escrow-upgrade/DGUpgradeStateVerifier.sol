// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";

import {IDGLaunchVerifier} from "scripts/launch/interfaces/IDGLaunchVerifier.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IDualGovernance, Proposers} from "contracts/interfaces/IDualGovernance.sol";

contract DGUpgradeStateVerifier is IDGLaunchVerifier {
    error InvalidDualGovernanceAddress(address expectedValue, address actualValue);
    error InvalidTiebreakerActivationTimeout(Duration expectedValue, Duration actualValue);
    error InvalidTiebreakerCommittee(address expectedValue, address actualValue);
    error InvalidTiebreakerSealableWithdrawalBlockersCount(uint256 expectedValue, uint256 actualValue);
    error InvalidTiebreakerSealableWithdrawalBlockers(address expectedValue, address actualValue);
    error InvalidProposer(address expectedValue, address actualValue);
    error InvalidProposerExecutor(address expectedValue, address actualValue);
    error InvalidProposalsCanceller(address expectedValue, address actualValue);
    error InvalidResealCommittee(address expectedValue, address actualValue);
    error InvalidProposesCount(uint256 expectedValue, uint256 actualValue);
    error InvalidConfigProviderForOldDualGovernance(address expectedValue, address actualValue);

    event DGUpgradeConfigurationValidated();

    address public immutable VOTING;
    address public immutable DUAL_GOVERNANCE;
    address public immutable TIMELOCK;
    address public immutable ADMIN_EXECUTOR;
    address public immutable TIEBREAKER_CORE_COMMITTEE;
    Duration public immutable TIEBREAKER_ACTIVATION_TIMEOUT;
    address public immutable ACCOUNTING_ORACLE;
    address public immutable VALIDATORS_EXIT_BUS_ORACLE;
    address public immutable RESEAL_COMMITTEE;
    address public immutable CONFIG_PROVIDER_FOR_OLD_DUAL_GOVERNANCE;

    constructor(
        address _voting,
        address _dualGovernance,
        address _timelock,
        address _adminExecutor,
        address _tiebreakerCoreCommittee,
        Duration _tiebreakerActivationTimeout,
        address _accountingOracle,
        address _validatorsExitBusOracle,
        address _resealCommittee,
        address _configProviderForOldDualGovernance
    ) {
        VOTING = _voting;
        DUAL_GOVERNANCE = _dualGovernance;
        TIMELOCK = _timelock;
        ADMIN_EXECUTOR = _adminExecutor;
        TIEBREAKER_CORE_COMMITTEE = _tiebreakerCoreCommittee;
        TIEBREAKER_ACTIVATION_TIMEOUT = _tiebreakerActivationTimeout;
        ACCOUNTING_ORACLE = _accountingOracle;
        VALIDATORS_EXIT_BUS_ORACLE = _validatorsExitBusOracle;
        RESEAL_COMMITTEE = _resealCommittee;
        CONFIG_PROVIDER_FOR_OLD_DUAL_GOVERNANCE = _configProviderForOldDualGovernance;
    }

    function verify() external {
        if (IEmergencyProtectedTimelock(TIMELOCK).getGovernance() != DUAL_GOVERNANCE) {
            revert InvalidDualGovernanceAddress(DUAL_GOVERNANCE, IEmergencyProtectedTimelock(TIMELOCK).getGovernance());
        }

        ITiebreaker.TiebreakerDetails memory tiebreakerDetails = ITiebreaker(DUAL_GOVERNANCE).getTiebreakerDetails();

        if (tiebreakerDetails.tiebreakerActivationTimeout != TIEBREAKER_ACTIVATION_TIMEOUT) {
            revert InvalidTiebreakerActivationTimeout(
                TIEBREAKER_ACTIVATION_TIMEOUT, tiebreakerDetails.tiebreakerActivationTimeout
            );
        }

        if (tiebreakerDetails.tiebreakerCommittee != TIEBREAKER_CORE_COMMITTEE) {
            revert InvalidTiebreakerCommittee(TIEBREAKER_CORE_COMMITTEE, tiebreakerDetails.tiebreakerCommittee);
        }

        if (tiebreakerDetails.sealableWithdrawalBlockers.length != 2) {
            revert InvalidTiebreakerSealableWithdrawalBlockersCount(
                2, tiebreakerDetails.sealableWithdrawalBlockers.length
            );
        }

        if (tiebreakerDetails.sealableWithdrawalBlockers[0] != ACCOUNTING_ORACLE) {
            revert InvalidTiebreakerSealableWithdrawalBlockers(
                ACCOUNTING_ORACLE, tiebreakerDetails.sealableWithdrawalBlockers[0]
            );
        }

        if (tiebreakerDetails.sealableWithdrawalBlockers[1] != VALIDATORS_EXIT_BUS_ORACLE) {
            revert InvalidTiebreakerSealableWithdrawalBlockers(
                VALIDATORS_EXIT_BUS_ORACLE, tiebreakerDetails.sealableWithdrawalBlockers[1]
            );
        }

        Proposers.Proposer memory proposerDetails = IDualGovernance(DUAL_GOVERNANCE).getProposer(VOTING);

        if (proposerDetails.account != VOTING) {
            revert InvalidProposer(VOTING, proposerDetails.account);
        }

        if (proposerDetails.executor != ADMIN_EXECUTOR) {
            revert InvalidProposerExecutor(ADMIN_EXECUTOR, proposerDetails.executor);
        }

        if (IDualGovernance(DUAL_GOVERNANCE).getProposers().length != 1) {
            revert InvalidProposesCount(1, IDualGovernance(DUAL_GOVERNANCE).getProposers().length);
        }

        if (IDualGovernance(DUAL_GOVERNANCE).getProposalsCanceller() != VOTING) {
            revert InvalidProposalsCanceller(VOTING, IDualGovernance(DUAL_GOVERNANCE).getProposalsCanceller());
        }

        if (IDualGovernance(DUAL_GOVERNANCE).getResealCommittee() != RESEAL_COMMITTEE) {
            revert InvalidResealCommittee(RESEAL_COMMITTEE, IDualGovernance(DUAL_GOVERNANCE).getResealCommittee());
        }

        if (address(IDualGovernance(DUAL_GOVERNANCE).getConfigProvider()) != CONFIG_PROVIDER_FOR_OLD_DUAL_GOVERNANCE) {
            revert InvalidConfigProviderForOldDualGovernance(
                CONFIG_PROVIDER_FOR_OLD_DUAL_GOVERNANCE, address(IDualGovernance(DUAL_GOVERNANCE).getConfigProvider())
            );
        }

        emit DGUpgradeConfigurationValidated();
    }
}
