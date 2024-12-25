// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PercentD16} from "../types/PercentD16.sol";
import {Timestamps} from "../types/Timestamp.sol";

import {DualGovernanceConfig} from "./DualGovernanceConfig.sol";
import {State, DualGovernanceStateMachine} from "./DualGovernanceStateMachine.sol";

/// @title Dual Governance State Transitions Library
/// @notice Library containing the transition logic for the Dual Governance system.
/// @dev The graph of the state transitions:
///
///        ┌─────────────┐     ┌──────────────────┐
///        │    Normal   ├────>│  VetoSignalling  │<───────┐
///     ┌─>│  [SUB, EXE] │     │      [SUB]       │<────┐  │
///     │  └─────────────┘     │ ┌──────────────┐ │     │  │
///     │                   ┌──┼─┤ Deactivation ├─┼──┐  │  │
///     │                   │  │ │     [ ]      │ │  │  │  │
///     │                   │  │ └──────────────┘ │  │  │  │
///     │                   │  └──────────────────┘  │  │  │
///     │  ┌──────────────┐ │     ┌──────────┐       │  │  │
///     └──┤ VetoCooldown │<┘     │ RageQuit │<──────┘  │  │
///        │     [EXE]    │<──────┤   [SUB]  │<─────────┘  │
///        └──────┬───────┘       └──────────┘             │
///               └────────────────────────────────────────┘
///
///     SUB - Allows proposals submission while the state is active.
///     EXE - Allows scheduling proposals for execution while the state is active.
library DualGovernanceStateTransitions {
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    /// @notice Returns the allowed state transition for the Dual Governance State Machine.
    ///     If no state transition is possible, `currentState` will be equal to `nextState`.
    /// @param self The context of the Dual Governance State Machine.
    /// @param config The configuration of the Dual Governance State Machine to use for determining
    ///     state transitions.
    /// @return currentState The current state of the Dual Governance State Machine.
    /// @return nextState The next state of the Dual Governance State Machine if a transition
    ///     is possible, otherwise it will be the same as `currentState`.
    function getStateTransition(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config
    ) internal view returns (State currentState, State nextState) {
        currentState = self.state;
        if (currentState == State.Normal) {
            nextState = _fromNormalState(self, config);
        } else if (currentState == State.VetoSignalling) {
            nextState = _fromVetoSignallingState(self, config);
        } else if (currentState == State.VetoSignallingDeactivation) {
            nextState = _fromVetoSignallingDeactivationState(self, config);
        } else if (currentState == State.VetoCooldown) {
            nextState = _fromVetoCooldownState(self, config);
        } else if (currentState == State.RageQuit) {
            nextState = _fromRageQuitState(self, config);
        } else {
            assert(false);
        }
    }

    // ---
    // Private Methods
    // ---

    function _fromNormalState(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config
    ) private view returns (State) {
        return config.isFirstSealRageQuitSupportReached(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.Normal;
    }

    function _fromVetoSignallingState(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config
    ) private view returns (State) {
        PercentD16 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!config.isVetoSignallingDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
            return State.VetoSignalling;
        }

        if (config.isSecondSealRageQuitSupportReached(rageQuitSupport)) {
            return State.RageQuit;
        }

        return config.isVetoSignallingReactivationDurationPassed(
            Timestamps.max(self.vetoSignallingReactivationTime, self.vetoSignallingActivatedAt)
        ) ? State.VetoSignallingDeactivation : State.VetoSignalling;
    }

    function _fromVetoSignallingDeactivationState(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config
    ) private view returns (State) {
        PercentD16 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!config.isVetoSignallingDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
            return State.VetoSignalling;
        }

        if (config.isSecondSealRageQuitSupportReached(rageQuitSupport)) {
            return State.RageQuit;
        }

        if (config.isVetoSignallingDeactivationMaxDurationPassed(self.enteredAt)) {
            return State.VetoCooldown;
        }

        return State.VetoSignallingDeactivation;
    }

    function _fromVetoCooldownState(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config
    ) private view returns (State) {
        if (!config.isVetoCooldownDurationPassed(self.enteredAt)) {
            return State.VetoCooldown;
        }
        return config.isFirstSealRageQuitSupportReached(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.Normal;
    }

    function _fromRageQuitState(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config
    ) private view returns (State) {
        if (!self.rageQuitEscrow.isRageQuitFinalized()) {
            return State.RageQuit;
        }
        return config.isFirstSealRageQuitSupportReached(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.VetoCooldown;
    }
}
