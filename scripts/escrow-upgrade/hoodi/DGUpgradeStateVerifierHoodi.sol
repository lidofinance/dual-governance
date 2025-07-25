// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";

import {IDGLaunchVerifier} from "scripts/launch/interfaces/IDGLaunchVerifier.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IDualGovernance, Proposers} from "contracts/interfaces/IDualGovernance.sol";
import {UpgradeConstantsHoodi} from "./UpgradeConstantsHoodi.sol";

contract DGUpgradeStateVerifierHoodi is IDGLaunchVerifier, UpgradeConstantsHoodi {
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
    error InvalidConfigProviderForDisconnectedDualGovernance(address expectedValue, address actualValue);

    event DGUpgradeConfigurationValidated();

    address public immutable NEW_DUAL_GOVERNANCE;
    address public immutable NEW_TIEBREAKER_CORE_COMMITTEE;
    address public immutable CONFIG_PROVIDER_FOR_DISCONNECTED_DUAL_GOVERNANCE;

    constructor(
        address newDualGovernance,
        address newTiebreakerCoreCommittee,
        address configProviderForDisconnectedDualGovernance
    ) {
        NEW_DUAL_GOVERNANCE = newDualGovernance;
        NEW_TIEBREAKER_CORE_COMMITTEE = newTiebreakerCoreCommittee;
        CONFIG_PROVIDER_FOR_DISCONNECTED_DUAL_GOVERNANCE = configProviderForDisconnectedDualGovernance;
    }

    function verify() external {
        if (IEmergencyProtectedTimelock(TIMELOCK).getGovernance() != NEW_DUAL_GOVERNANCE) {
            revert InvalidDualGovernanceAddress(
                NEW_DUAL_GOVERNANCE, IEmergencyProtectedTimelock(TIMELOCK).getGovernance()
            );
        }

        ITiebreaker.TiebreakerDetails memory tiebreakerDetails = ITiebreaker(NEW_DUAL_GOVERNANCE).getTiebreakerDetails();

        if (tiebreakerDetails.tiebreakerActivationTimeout != TIEBREAKER_ACTIVATION_TIMEOUT) {
            revert InvalidTiebreakerActivationTimeout(
                TIEBREAKER_ACTIVATION_TIMEOUT, tiebreakerDetails.tiebreakerActivationTimeout
            );
        }

        if (tiebreakerDetails.tiebreakerCommittee != NEW_TIEBREAKER_CORE_COMMITTEE) {
            revert InvalidTiebreakerCommittee(NEW_TIEBREAKER_CORE_COMMITTEE, tiebreakerDetails.tiebreakerCommittee);
        }

        if (tiebreakerDetails.sealableWithdrawalBlockers.length != 3) {
            revert InvalidTiebreakerSealableWithdrawalBlockersCount(
                3, tiebreakerDetails.sealableWithdrawalBlockers.length
            );
        }

        if (tiebreakerDetails.sealableWithdrawalBlockers[0] != WITHDRAWAL_QUEUE) {
            revert InvalidTiebreakerSealableWithdrawalBlockers(
                WITHDRAWAL_QUEUE, tiebreakerDetails.sealableWithdrawalBlockers[0]
            );
        }

        if (tiebreakerDetails.sealableWithdrawalBlockers[1] != VALIDATORS_EXIT_BUS_ORACLE) {
            revert InvalidTiebreakerSealableWithdrawalBlockers(
                VALIDATORS_EXIT_BUS_ORACLE, tiebreakerDetails.sealableWithdrawalBlockers[1]
            );
        }

        if (tiebreakerDetails.sealableWithdrawalBlockers[2] != TRIGGERABLE_WITHDRAWALS_GATEWAY) {
            revert InvalidTiebreakerSealableWithdrawalBlockers(
                TRIGGERABLE_WITHDRAWALS_GATEWAY, tiebreakerDetails.sealableWithdrawalBlockers[2]
            );
        }

        Proposers.Proposer[] memory proposers = IDualGovernance(NEW_DUAL_GOVERNANCE).getProposers();

        if (proposers.length != 1) {
            revert InvalidProposesCount(1, proposers.length);
        }

        if (proposers[0].account != VOTING) {
            revert InvalidProposer(VOTING, proposers[0].account);
        }

        if (proposers[0].executor != ADMIN_EXECUTOR) {
            revert InvalidProposerExecutor(ADMIN_EXECUTOR, proposers[0].executor);
        }

        if (IDualGovernance(NEW_DUAL_GOVERNANCE).getProposalsCanceller() != VOTING) {
            revert InvalidProposalsCanceller(VOTING, IDualGovernance(NEW_DUAL_GOVERNANCE).getProposalsCanceller());
        }

        if (IDualGovernance(NEW_DUAL_GOVERNANCE).getResealCommittee() != RESEAL_COMMITTEE) {
            revert InvalidResealCommittee(RESEAL_COMMITTEE, IDualGovernance(NEW_DUAL_GOVERNANCE).getResealCommittee());
        }

        if (
            address(IDualGovernance(DUAL_GOVERNANCE).getConfigProvider())
                != CONFIG_PROVIDER_FOR_DISCONNECTED_DUAL_GOVERNANCE
        ) {
            revert InvalidConfigProviderForDisconnectedDualGovernance(
                CONFIG_PROVIDER_FOR_DISCONNECTED_DUAL_GOVERNANCE,
                address(IDualGovernance(DUAL_GOVERNANCE).getConfigProvider())
            );
        }

        emit DGUpgradeConfigurationValidated();
    }
}
