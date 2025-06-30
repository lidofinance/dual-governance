// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../contracts/libraries/Proposers.sol";
import "../../contracts/DualGovernance.sol";
import {Status as ProposalStatus} from "../../contracts/libraries/ExecutableProposals.sol";
import {Proposal} from "../../contracts/libraries/EnumerableProposals.sol";
import "../../contracts/libraries/ExecutableProposals.sol";
// This is to make a type available for a NONDET summary
import {IExternalExecutor} from "../../contracts/interfaces/IExternalExecutor.sol";
import {State, DualGovernanceStateMachine} from "../../contracts/libraries/DualGovernanceStateMachine.sol";

// The following are for methods about checking if max durations have passed
import {DualGovernanceConfig} from "../../contracts/libraries/DualGovernanceConfig.sol";
import {PercentD16} from "../../contracts/types/PercentD16.sol";
import {Timestamp, Timestamps} from "../../contracts/types/Timestamp.sol";

contract DualGovernanceHarness is DualGovernance {
    using Proposers for Proposers.Context;
    using Proposers for Proposers.Proposer;
    using Tiebreaker for Tiebreaker.Context;
    using DualGovernanceStateMachine for DualGovernanceStateMachine.Context;
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    // Needed because DualGovernanceStateMachine.State is not
    // referrable without redeclaring this here.
    enum DGHarnessState {
        Unset,
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
        RageQuit
    }

    constructor(
        DualGovernanceComponents memory components,
        SignallingTokens memory signallingTokens,
        SanityCheckParams memory sanityCheckParams
    ) DualGovernance(components, signallingTokens, sanityCheckParams) {}

    // Return is uint32 which is the same as IndexOneBased
    function getProposerIndexFromExecutor(address proposer) external view returns (uint32) {
        return IndexOneBased.unwrap(_proposers.executors[proposer].proposerIndex);
    }

    function getProposalInfoHarnessed(uint256 proposalId)
        external
        view
        returns (uint256 id, ProposalStatus status, address executor, Timestamp submittedAt, Timestamp scheduledAt)
    {
        ITimelock.ProposalDetails memory proposalDetails = getProposalHarnessed(proposalId);
        (id, status, executor, submittedAt, scheduledAt) = (
            proposalDetails.id,
            proposalDetails.status,
            proposalDetails.executor,
            proposalDetails.submittedAt,
            proposalDetails.scheduledAt
        );
    }

    function getProposalHarnessed(uint256 proposalId) public view returns (ITimelock.ProposalDetails memory proposal) {
        ITimelock.ProposalDetails memory defaultProposalDetails;
        try TIMELOCK.getProposalDetails(proposalId) returns (ITimelock.ProposalDetails memory proposal) {
            return proposal;
        } catch {
            return defaultProposalDetails;
        }
    }

    function getVetoSignallingActivatedAt() external view returns (Timestamp) {
        return _stateMachine.vetoSignallingActivatedAt;
    }

    function asDGHarnessState(State state) public returns (DGHarnessState) {
        uint256 state_underlying = uint256(state);
        return DGHarnessState(state_underlying);
    }

    function getState() external returns (DGHarnessState) {
        return asDGHarnessState(_stateMachine.state);
    }

    function getFirstSeal() external view returns (uint256) {
        return PercentD16.unwrap(_stateMachine.configProvider.getDualGovernanceConfig().firstSealRageQuitSupport);
    }

    function getSecondSeal() external view returns (uint256) {
        return PercentD16.unwrap(_stateMachine.configProvider.getDualGovernanceConfig().secondSealRageQuitSupport);
    }

    function getFirstSealRageQuitSupportCrossed() external view returns (bool) {
        return _stateMachine.configProvider.getDualGovernanceConfig().isFirstSealRageQuitSupportReached(
            _stateMachine.signallingEscrow.getRageQuitSupport()
        );
    }

    function getSecondSealRageQuitSupportCrossed() external view returns (bool) {
        return _stateMachine.configProvider.getDualGovernanceConfig().isSecondSealRageQuitSupportReached(
            _stateMachine.signallingEscrow.getRageQuitSupport()
        );
    }

    function getRageQuitSupportHarnessed() external view returns (PercentD16) {
        return _stateMachine.signallingEscrow.getRageQuitSupport();
    }

    function isDynamicTimelockPassed(uint128 rageQuitSupport) public view returns (bool) {
        return _stateMachine.configProvider.getDualGovernanceConfig().isVetoSignallingDurationPassed(
            _stateMachine.vetoSignallingActivatedAt, PercentD16.wrap(rageQuitSupport)
        );
    }

    function isVetoSignallingReactivationPassed() public view returns (bool) {
        return _stateMachine.configProvider.getDualGovernanceConfig().isVetoSignallingReactivationDurationPassed(
            Timestamps.max(_stateMachine.vetoSignallingReactivationTime, _stateMachine.vetoSignallingActivatedAt)
        );
    }

    function isVetoSignallingDeactivationPassed() public view returns (bool) {
        return _stateMachine.configProvider.getDualGovernanceConfig().isVetoSignallingDeactivationMaxDurationPassed(
            _stateMachine.enteredAt
        );
    }

    function isVetoSignallingDeactivationMaxDurationPassed() public view returns (bool) {
        return _stateMachine.configProvider.getDualGovernanceConfig().isVetoSignallingDeactivationMaxDurationPassed(
            _stateMachine.enteredAt
        );
    }

    function isVetoCooldownDurationPassed() public view returns (bool) {
        return
            _stateMachine.configProvider.getDualGovernanceConfig().isVetoCooldownDurationPassed(_stateMachine.enteredAt);
    }

    function isUnset(DGHarnessState state) public view returns (bool) {
        return state == DGHarnessState.Unset;
    }

    function isNormal(DGHarnessState state) public view returns (bool) {
        return state == DGHarnessState.Normal;
    }

    function isVetoSignalling(DGHarnessState state) public view returns (bool) {
        return state == DGHarnessState.VetoSignalling;
    }

    function isVetoSignallingDeactivation(DGHarnessState state) public view returns (bool) {
        return state == DGHarnessState.VetoSignallingDeactivation;
    }

    function isVetoCooldown(DGHarnessState state) public view returns (bool) {
        return state == DGHarnessState.VetoCooldown;
    }

    function isRageQuit(DGHarnessState state) public view returns (bool) {
        return state == DGHarnessState.RageQuit;
    }
}
