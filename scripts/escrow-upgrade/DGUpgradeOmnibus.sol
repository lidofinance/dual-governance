// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IGovernance} from "contracts/interfaces/IGovernance.sol";

import {IDGLaunchVerifier} from "scripts/launch/interfaces/IDGLaunchVerifier.sol";

import {ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";

import {OmnibusBase} from "../utils/OmnibusBase.sol";

/// @title DGUpgradeOmnibus
/// @notice This script provides a proposal calldata and a vote verifier for
///upgrade escrow master copy of Dual Governance
///
/// @dev TODO: add natspecs
contract DGUpgradeOmnibus is OmnibusBase {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    uint256 public constant VOTE_ITEMS_COUNT = 1;
    uint256 public constant DG_PROPOSAL_CALLS_COUNT = 9;

    address public immutable VOTING;
    address public immutable DUAL_GOVERNANCE;

    address public immutable NEW_DUAL_GOVERNANCE;
    address public immutable ACCOUNTING_ORACLE;
    address public immutable VALIDATORS_EXIT_BUS_ORACLE;
    address public immutable RESEAL_COMMITTEE;
    address public immutable ADMIN_EXECUTOR;
    address public immutable DG_UPGRADE_STATE_VERIFIER;
    address public immutable TIMELOCK;
    address public immutable TIEBREAKER_CORE_COMMITTEE;
    Duration public immutable TIEBREAKER_ACTIVATION_TIMEOUT;

    constructor(
        address _voting,
        address _dualGovernance,
        address _adminExecutor,
        address _timelock,
        address _newDualGovernance,
        address _newTiebreakerCoreCommittee,
        Duration _newTiebreakerActivationTimeout,
        address _accountingOracle,
        address _validatorsExitBusOracle,
        address _resealCommittee,
        address _dgUpgradeStateVerifier
    ) OmnibusBase(_voting) {
        VOTING = _voting;
        DUAL_GOVERNANCE = _dualGovernance;
        NEW_DUAL_GOVERNANCE = _newDualGovernance;
        TIEBREAKER_CORE_COMMITTEE = _newTiebreakerCoreCommittee;
        TIEBREAKER_ACTIVATION_TIMEOUT = _newTiebreakerActivationTimeout;
        TIMELOCK = _timelock;
        ADMIN_EXECUTOR = _adminExecutor;
        RESEAL_COMMITTEE = _resealCommittee;
        ACCOUNTING_ORACLE = _accountingOracle;
        VALIDATORS_EXIT_BUS_ORACLE = _validatorsExitBusOracle;
        DG_UPGRADE_STATE_VERIFIER = _dgUpgradeStateVerifier;
    }

    function getVoteItems() public view override returns (VoteItem[] memory voteItems) {
        voteItems = new VoteItem[](VOTE_ITEMS_COUNT);

        // Submit DG proposal to switch Dual Governance contract with new Escrow Master Copy
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
                NEW_DUAL_GOVERNANCE, abi.encodeCall(ITiebreaker.setTiebreakerCommittee, TIEBREAKER_CORE_COMMITTEE)
            );

            // 3. Add Accounting Oracle as Tiebreaker withdrawal blocker
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE,
                abi.encodeCall(ITiebreaker.addTiebreakerSealableWithdrawalBlocker, ACCOUNTING_ORACLE)
            );

            // 4. Add Validators Exit Bus Oracle as Tiebreaker withdrawal blocker
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE,
                abi.encodeCall(ITiebreaker.addTiebreakerSealableWithdrawalBlocker, VALIDATORS_EXIT_BUS_ORACLE)
            );

            // 5. Register Aragon Voting as admin proposer
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE, abi.encodeCall(IDualGovernance.registerProposer, (VOTING, ADMIN_EXECUTOR))
            );

            // 6. Set Aragon Voting as proposals canceller
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE, abi.encodeCall(IDualGovernance.setProposalsCanceller, VOTING)
            );

            // 7. Set reseal committee
            dgProposalCallsBuilder.addCall(
                NEW_DUAL_GOVERNANCE, abi.encodeCall(IDualGovernance.setResealCommittee, RESEAL_COMMITTEE)
            );

            // 8. Set Emergency Protected Timelock governance to new Dual Governance contract
            dgProposalCallsBuilder.addCall(TIMELOCK, abi.encodeCall(ITimelock.setGovernance, (NEW_DUAL_GOVERNANCE)));

            // 9. Verify Dual Governance state
            dgProposalCallsBuilder.addCall(DG_UPGRADE_STATE_VERIFIER, abi.encodeCall(IDGLaunchVerifier.verify, ()));

            voteItems[0] = VoteItem({
                description: "1. Submit DG proposal to switch Dual Governance contract with new Escrow Master Copy",
                call: _votingCall(
                    DUAL_GOVERNANCE,
                    abi.encodeCall(
                        IGovernance.submitProposal,
                        (
                            dgProposalCallsBuilder.getResult(),
                            string("Upgrade Dual Governance contract with new Escrow Master Copy")
                        )
                    )
                )
            });
        }
    }
}
