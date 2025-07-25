// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IGovernance} from "contracts/interfaces/IGovernance.sol";
import {IDualGovernanceConfigProvider} from "contracts/interfaces/IDualGovernanceConfigProvider.sol";
import {IDGLaunchVerifier} from "scripts/launch/interfaces/IDGLaunchVerifier.sol";

import {ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";
import {UpgradeConstantsHoodi} from "./UpgradeConstantsHoodi.sol";

import {OmnibusBase} from "../../utils/OmnibusBase.sol";

/// @title DGUpgradeOmnibusHoodi
/// @notice Contains vote items for execution via Dual Governance to upgrade Dual Governance contract.
/// Provides a mechanism for validating an Aragon vote against the actions in this contract, by passing the vote ID.
///
/// @dev This contract defines the complete set of governance actions required to upgrade Dual Governance contract.
///
/// It provides:
/// - A list of 11 vote items that must be submitted and executed through an Aragon vote to perform the upgrade.
/// - Includes:
///     - Setting new Dual Governance contract with Tiebreaker configuration
///     - Setting new Dual Governance contract with reseal committee
///     - Setting new Dual Governance contract with Proposals canceller
///     - Connecting new Dual Governance contract to the Emergency Protected Timelock
///     - Setting config provider for old Dual Governance contract to prevent it from being used in Rage Quit
///     - Verifying Dual Governance state
contract DGUpgradeOmnibusHoodi is OmnibusBase, UpgradeConstantsHoodi {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    uint256 public constant VOTE_ITEMS_COUNT = 1;
    uint256 public constant DG_PROPOSAL_CALLS_COUNT = 11;

    address public immutable NEW_DUAL_GOVERNANCE;
    address public immutable NEW_TIEBREAKER_CORE_COMMITTEE;

    address public immutable DG_UPGRADE_STATE_VERIFIER;
    address public immutable CONFIG_PROVIDER_FOR_DISCONNECTED_DUAL_GOVERNANCE;

    constructor(
        address dgUpgradeStateVerifier,
        address newDualGovernance,
        address newTiebreakerCoreCommittee,
        address configProviderForDisconnectedDualGovernance
    ) OmnibusBase(VOTING) {
        DG_UPGRADE_STATE_VERIFIER = dgUpgradeStateVerifier;
        NEW_DUAL_GOVERNANCE = newDualGovernance;
        NEW_TIEBREAKER_CORE_COMMITTEE = newTiebreakerCoreCommittee;
        CONFIG_PROVIDER_FOR_DISCONNECTED_DUAL_GOVERNANCE = configProviderForDisconnectedDualGovernance;
    }

    function getVoteItems() public view override returns (VoteItem[] memory voteItems) {
        voteItems = new VoteItem[](VOTE_ITEMS_COUNT);

        {
            ExternalCallsBuilder.Context memory dgProposalCallsBuilder =
                ExternalCallsBuilder.create({callsCount: DG_PROPOSAL_CALLS_COUNT});

            // 1. Set Tiebreaker activation timeout
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE,
                abi.encodeCall(ITiebreaker.setTiebreakerActivationTimeout, TIEBREAKER_ACTIVATION_TIMEOUT)
            );

            // 2. Set Tiebreaker committee
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE, abi.encodeCall(ITiebreaker.setTiebreakerCommittee, NEW_TIEBREAKER_CORE_COMMITTEE)
            );

            // 3. Add Withdrawal Queue as Tiebreaker withdrawal blocker
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE,
                abi.encodeCall(ITiebreaker.addTiebreakerSealableWithdrawalBlocker, WITHDRAWAL_QUEUE)
            );

            // 4. Add Validators Exit Bus Oracle as Tiebreaker withdrawal blocker
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE,
                abi.encodeCall(ITiebreaker.addTiebreakerSealableWithdrawalBlocker, VALIDATORS_EXIT_BUS_ORACLE)
            );

            // 5. Add Triggerable Withdrawals Gateway as Tiebreaker withdrawal blocker
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE,
                abi.encodeCall(ITiebreaker.addTiebreakerSealableWithdrawalBlocker, TRIGGERABLE_WITHDRAWALS_GATEWAY)
            );

            // 6. Register Aragon Voting as admin proposer
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE, abi.encodeCall(IDualGovernance.registerProposer, (VOTING, ADMIN_EXECUTOR))
            );

            // 7. Set Aragon Voting as proposals canceller
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE, abi.encodeCall(IDualGovernance.setProposalsCanceller, VOTING)
            );

            // 8. Set reseal committee
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE, abi.encodeCall(IDualGovernance.setResealCommittee, RESEAL_COMMITTEE)
            );

            // 9. Set Emergency Protected Timelock governance to new Dual Governance contract
            dgProposalCallsBuilder.addCall(TIMELOCK, abi.encodeCall(ITimelock.setGovernance, (NEW_DUAL_GOVERNANCE)));

            // 10. Set config provider for old Dual Governance contract
            dgProposalCallsBuilder.addCall(
                DUAL_GOVERNANCE,
                abi.encodeCall(
                    IDualGovernance.setConfigProvider,
                    (IDualGovernanceConfigProvider(CONFIG_PROVIDER_FOR_DISCONNECTED_DUAL_GOVERNANCE))
                )
            );

            // 11. Verify Dual Governance state
            dgProposalCallsBuilder.addCall(DG_UPGRADE_STATE_VERIFIER, abi.encodeCall(IDGLaunchVerifier.verify, ()));

            voteItems[0] = VoteItem({
                description: "1. Submit Dual Governance proposal to upgrade Dual Governance contract on Hoodi testnet (Immunefi reported vulnerability fix)",
                call: _votingCall(
                    DUAL_GOVERNANCE,
                    abi.encodeCall(
                        IGovernance.submitProposal,
                        (
                            dgProposalCallsBuilder.getResult(),
                            string(
                                "1.1 - 1.11 Proposal to upgrade Dual Governance contract on Hoodi testnet (Immunefi reported vulnerability fix)"
                            )
                        )
                    )
                )
            });
        }
    }
}
