// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../contracts/libraries/Proposers.sol";
import "../../contracts/DualGovernance.sol";
import {Status as ProposalStatus} from "../../contracts/libraries/ExecutableProposals.sol";
import {Proposal} from "../../contracts/libraries/EnumerableProposals.sol";
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
        ExternalDependencies memory dependencies,
        SanityCheckParams memory sanityCheckParams
    ) DualGovernance(dependencies, sanityCheckParams) {}

    // Return is uint32 which is the same as IndexOneBased
    function getProposerIndexFromExecutor(address proposer) external view returns (uint32) {
        return IndexOneBased.unwrap(_proposers.executors[proposer].proposerIndex);
    }

    function getProposalInfoHarnessed(uint256 proposalId)
        external
        view
        returns (uint256 id, ProposalStatus status, address executor, Timestamp submittedAt, Timestamp scheduledAt)
    {
        return TIMELOCK.getProposalInfo(proposalId);
    }

    function getProposalHarnessed(uint256 proposalId) external view returns (ITimelock.Proposal memory proposal) {
        return TIMELOCK.getProposal(proposalId);
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
        return PercentD16.unwrap(_configProvider.getDualGovernanceConfig().firstSealRageQuitSupport);
    }

    function getSecondSeal() external view returns (uint256) {
        return PercentD16.unwrap(_configProvider.getDualGovernanceConfig().secondSealRageQuitSupport);
    }

    function getFirstSealRageQuitSupportCrossed() external view returns (bool) {
        return _configProvider.getDualGovernanceConfig().isFirstSealRageQuitSupportCrossed(
            _stateMachine.signallingEscrow.getRageQuitSupport()
        );
    }

    function getSecondSealRageQuitSupportCrossed() external view returns (bool) {
        return _configProvider.getDualGovernanceConfig().isSecondSealRageQuitSupportCrossed(
            _stateMachine.signallingEscrow.getRageQuitSupport()
        );
    }

    function getRageQuitSupportHarnessed() external view returns (PercentD16) {
        return _stateMachine.signallingEscrow.getRageQuitSupport();
    }

    function isDynamicTimelockPassed(uint256 rageQuitSupport) public returns (bool) {
        return _configProvider.getDualGovernanceConfig().isDynamicTimelockDurationPassed(
            _stateMachine.vetoSignallingActivatedAt, PercentD16.wrap(rageQuitSupport)
        );
    }

    function isVetoSignallingReactivationPassed() public returns (bool) {
        return _configProvider.getDualGovernanceConfig().isVetoSignallingReactivationDurationPassed(
            Timestamps.max(_stateMachine.vetoSignallingReactivationTime, _stateMachine.vetoSignallingActivatedAt)
        );
    }

    function isVetoSignallingDeactivationPassed() public returns (bool) {
        return _configProvider.getDualGovernanceConfig().isVetoSignallingDeactivationMaxDurationPassed(
            _stateMachine.enteredAt
        );
    }

    function isVetoSignallingDeactivationMaxDurationPassed() public returns (bool) {
        return _configProvider.getDualGovernanceConfig().isVetoSignallingDeactivationMaxDurationPassed(
            _stateMachine.enteredAt
        );
    }

    function isVetoCooldownDurationPassed() public returns (bool) {
        return _configProvider.getDualGovernanceConfig().isVetoCooldownDurationPassed(_stateMachine.enteredAt);
    }

    function isUnset(DGHarnessState state) public returns (bool) {
        return state == DGHarnessState.Unset;
    }

    function isNormal(DGHarnessState state) public returns (bool) {
        return state == DGHarnessState.Normal;
    }

    function isVetoSignalling(DGHarnessState state) public returns (bool) {
        return state == DGHarnessState.VetoSignalling;
    }

    function isVetoSignallingDeactivation(DGHarnessState state) public returns (bool) {
        return state == DGHarnessState.VetoSignallingDeactivation;
    }

    function isVetoCooldown(DGHarnessState state) public returns (bool) {
        return state == DGHarnessState.VetoCooldown;
    }

    function isRageQuit(DGHarnessState state) public returns (bool) {
        return state == DGHarnessState.RageQuit;
    }
}
