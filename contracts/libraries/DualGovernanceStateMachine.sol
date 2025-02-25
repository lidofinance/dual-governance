// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

import {IEscrowBase} from "../interfaces/IEscrowBase.sol";
import {ISignallingEscrow} from "../interfaces/ISignallingEscrow.sol";
import {IRageQuitEscrow} from "../interfaces/IRageQuitEscrow.sol";
import {IDualGovernance} from "../interfaces/IDualGovernance.sol";
import {IDualGovernanceConfigProvider} from "../interfaces/IDualGovernanceConfigProvider.sol";

import {DualGovernanceConfig} from "./DualGovernanceConfig.sol";
import {DualGovernanceStateTransitions} from "./DualGovernanceStateTransitions.sol";

/// @notice Enum describing the state of the Dual Governance State Machine
/// @param NotInitialized The initial (uninitialized) state of the Dual Governance State Machine. The state machine cannot
///     operate in this state and must be initialized before use.
/// @param Normal The default state where the system is expected to remain most of the time. In this state, proposals
///     can be both submitted and scheduled for execution.
/// @param VetoSignalling Represents active opposition to DAO decisions. In this state, the scheduling of proposals
///     is blocked, but the submission of new proposals is still allowed.
/// @param VetoSignallingDeactivation A sub-state of VetoSignalling, allowing users to observe the deactivation process
///     and react before non-cancelled proposals are scheduled for execution. Both proposal submission and scheduling
///     are prohibited in this state.
/// @param VetoCooldown A state where the DAO can execute non-cancelled proposals but is prohibited from submitting
///     new proposals.
/// @param RageQuit Represents the process where users opting to leave the protocol can withdraw their funds. This state
///     is triggered when the Second Seal Threshold is reached. During this state, the scheduling of proposals for
///     execution is forbidden, but new proposals can still be submitted.
enum State {
    NotInitialized,
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

/// @title Dual Governance State Machine Library
/// @notice Library containing the core logic for managing the states of the Dual Governance system
library DualGovernanceStateMachine {
    using DualGovernanceStateTransitions for Context;
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    // ---
    // Data types
    // ---

    /// @notice Represents the context of the Dual Governance State Machine.
    /// @param state The last recorded state of the Dual Governance State Machine.
    /// @param enteredAt The timestamp when the current `persisted` `state` was entered.
    /// @param vetoSignallingActivatedAt The timestamp when the VetoSignalling state was last activated.
    /// @param signallingEscrow The address of the Escrow contract used for VetoSignalling.
    /// @param rageQuitRound The number of continuous Rage Quit rounds, starting at 0 and capped at MAX_RAGE_QUIT_ROUND.
    /// @param vetoSignallingReactivationTime The timestamp of the last transition from VetoSignallingDeactivation to VetoSignalling.
    /// @param normalOrVetoCooldownExitedAt The timestamp of the last exit from either the Normal or VetoCooldown state.
    /// @param rageQuitEscrow The address of the Escrow contract used during the most recent (or ongoing) Rage Quit process.
    /// @param configProvider The address of the contract providing the current configuration for the Dual Governance State Machine.
    struct Context {
        /// @dev slot 0: [0..7]
        State state;
        /// @dev slot 0: [8..47]
        Timestamp enteredAt;
        /// @dev slot 0: [48..87]
        Timestamp vetoSignallingActivatedAt;
        /// @dev slot 0: [88..247]
        ISignallingEscrow signallingEscrow;
        /// @dev slot 0: [248..255]
        uint8 rageQuitRound;
        /// @dev slot 1: [0..39]
        Timestamp vetoSignallingReactivationTime;
        /// @dev slot 1: [40..79]
        Timestamp normalOrVetoCooldownExitedAt;
        /// @dev slot 1: [80..239]
        IRageQuitEscrow rageQuitEscrow;
        /// @dev slot 2: [0..159]
        IDualGovernanceConfigProvider configProvider;
    }

    // ---
    // Errors
    // ---

    error AlreadyInitialized();
    error InvalidConfigProvider(IDualGovernanceConfigProvider configProvider);

    // ---
    // Events
    // ---

    event NewSignallingEscrowDeployed(ISignallingEscrow indexed escrow);
    event DualGovernanceStateChanged(State indexed from, State indexed to, Context state);
    event ConfigProviderSet(IDualGovernanceConfigProvider newConfigProvider);

    // ---
    // Constants
    // ---

    /// @dev The upper limit for the maximum possible continuous RageQuit rounds. Once this limit is reached,
    ///      the `rageQuitRound` value is capped at 255 until the system returns to the Normal or VetoCooldown state.
    uint256 internal constant MAX_RAGE_QUIT_ROUND = type(uint8).max;

    // ---
    // Main Functionality
    // ---

    /// @notice Initializes the Dual Governance State Machine context.
    /// @param self The context of the Dual Governance State Machine to be initialized.
    /// @param configProvider The address of the Dual Governance State Machine configuration provider.
    /// @param escrowMasterCopy The address of the master copy used as the implementation for the minimal proxy deployment
    ///     of a Signalling Escrow instance.
    function initialize(
        Context storage self,
        IDualGovernanceConfigProvider configProvider,
        IEscrowBase escrowMasterCopy
    ) internal {
        if (self.state != State.NotInitialized) {
            revert AlreadyInitialized();
        }

        self.state = State.Normal;
        self.enteredAt = Timestamps.now();

        _setConfigProvider(self, configProvider);

        DualGovernanceConfig.Context memory config = configProvider.getDualGovernanceConfig();
        _deployNewSignallingEscrow(self, escrowMasterCopy, config.minAssetsLockDuration);

        emit DualGovernanceStateChanged(State.NotInitialized, State.Normal, self);
    }

    /// @notice Executes a state transition for the Dual Governance State Machine, if applicable.
    ///     If no transition is possible from the current `persisted` state, no changes are applied to the context.
    /// @dev If the state transitions to RageQuit, a new instance of the Signalling Escrow is deployed using
    ///     `signallingEscrow.ESCROW_MASTER_COPY()` as the implementation for the minimal proxy,
    ///     while the previous Signalling Escrow instance is converted into the RageQuit escrow.
    /// @param self The context of the Dual Governance State Machine.
    function activateNextState(Context storage self) internal {
        DualGovernanceConfig.Context memory config = getDualGovernanceConfig(self);
        (State currentState, State newState) = self.getStateTransition(config);

        if (currentState == newState) {
            return;
        }

        Timestamp newStateEnteredAt = Timestamps.now();

        self.state = newState;
        self.enteredAt = newStateEnteredAt;

        if (currentState == State.Normal || currentState == State.VetoCooldown) {
            self.normalOrVetoCooldownExitedAt = newStateEnteredAt;
        }

        if (newState == State.VetoCooldown && self.rageQuitRound != 0) {
            self.rageQuitRound = 0;
        } else if (newState == State.VetoSignalling) {
            if (currentState == State.VetoSignallingDeactivation) {
                self.vetoSignallingReactivationTime = newStateEnteredAt;
            } else {
                self.vetoSignallingActivatedAt = newStateEnteredAt;
            }
        } else if (newState == State.RageQuit) {
            ISignallingEscrow signallingEscrow = self.signallingEscrow;

            uint256 currentRageQuitRound = self.rageQuitRound;

            /// @dev Limits the maximum value of the rage quit round to prevent failures due to arithmetic overflow
            ///     if the number of continuous rage quits reaches MAX_RAGE_QUIT_ROUND.
            uint256 newRageQuitRound = Math.min(currentRageQuitRound + 1, MAX_RAGE_QUIT_ROUND);
            self.rageQuitRound = uint8(newRageQuitRound);

            signallingEscrow.startRageQuit(
                config.rageQuitExtensionPeriodDuration, config.calcRageQuitWithdrawalsDelay(newRageQuitRound)
            );
            self.rageQuitEscrow = IRageQuitEscrow(address(signallingEscrow));
            _deployNewSignallingEscrow(self, signallingEscrow.ESCROW_MASTER_COPY(), config.minAssetsLockDuration);
        }

        emit DualGovernanceStateChanged(currentState, newState, self);
    }

    /// @notice Updates the address of the configuration provider for the Dual Governance State Machine.
    /// @param self The context of the Dual Governance State Machine.
    /// @param newConfigProvider The address of the new configuration provider.
    function setConfigProvider(Context storage self, IDualGovernanceConfigProvider newConfigProvider) internal {
        _setConfigProvider(self, newConfigProvider);

        ISignallingEscrow signallingEscrow = self.signallingEscrow;
        Duration newMinAssetsLockDuration = newConfigProvider.getDualGovernanceConfig().minAssetsLockDuration;

        /// @dev minAssetsLockDuration is stored as a storage variable in the Signalling Escrow instance.
        ///      To synchronize the new value with the current Signalling Escrow, it must be manually updated.
        if (signallingEscrow.getMinAssetsLockDuration() != newMinAssetsLockDuration) {
            signallingEscrow.setMinAssetsLockDuration(newMinAssetsLockDuration);
        }
    }

    // ---
    // Getters
    // ---

    /// @notice Returns detailed information about the state of the Dual Governance State Machine.
    /// @param self The context of the Dual Governance State Machine.
    /// @return stateDetails A struct containing detailed information about the state of
    ///     the Dual Governance State Machine.
    function getStateDetails(Context storage self)
        internal
        view
        returns (IDualGovernance.StateDetails memory stateDetails)
    {
        DualGovernanceConfig.Context memory config = getDualGovernanceConfig(self);
        (stateDetails.persistedState, stateDetails.effectiveState) = self.getStateTransition(config);

        stateDetails.persistedStateEnteredAt = self.enteredAt;
        stateDetails.vetoSignallingActivatedAt = self.vetoSignallingActivatedAt;
        stateDetails.vetoSignallingReactivationTime = self.vetoSignallingReactivationTime;
        stateDetails.normalOrVetoCooldownExitedAt = self.normalOrVetoCooldownExitedAt;
        stateDetails.rageQuitRound = self.rageQuitRound;
        stateDetails.vetoSignallingDuration =
            config.calcVetoSignallingDuration(self.signallingEscrow.getRageQuitSupport());
    }

    /// @notice Returns the most recently persisted state of the Dual Governance State Machine.
    /// @param self The context of the Dual Governance State Machine.
    /// @return persistedState The state of the Dual Governance State Machine as last stored.
    function getPersistedState(Context storage self) internal view returns (State persistedState) {
        persistedState = self.state;
    }

    /// @notice Returns the effective state of the Dual Governance State Machine.
    /// @dev The effective state refers to the state the Dual Governance State Machine would transition to
    ///     upon calling `activateNextState()`.
    /// @param self The context of the Dual Governance State Machine.
    /// @return effectiveState The state that will become active after the next state transition.
    ///     If the `activateNextState` call does not trigger a state transition, `effectiveState`
    ///     will be the same as `persistedState`.
    function getEffectiveState(Context storage self) internal view returns (State effectiveState) {
        ( /* persistedState */ , effectiveState) = self.getStateTransition(getDualGovernanceConfig(self));
    }

    /// @notice Returns whether the submission of proposals is allowed based on the `persisted` or `effective` state,
    ///     depending on the `useEffectiveState` value.
    /// @param self The context of the Dual Governance State Machine.
    /// @param useEffectiveState If `true`, the check is performed against the `effective` state, which represents the state
    ///     the Dual Governance State Machine will enter after the next `activateNextState` call. If `false`, the check is
    ///     performed against the `persisted` state, which is the currently stored state of the system.
    /// @return bool A boolean indicating whether the submission of proposals is allowed in the selected state.
    function canSubmitProposal(Context storage self, bool useEffectiveState) internal view returns (bool) {
        State state = useEffectiveState ? getEffectiveState(self) : getPersistedState(self);
        return state != State.VetoSignallingDeactivation && state != State.VetoCooldown;
    }

    /// @notice Determines whether scheduling a proposal for execution is allowed, based on either the `persisted`
    ///     or `effective` state, depending on the `useEffectiveState` flag.
    /// @param self The context of the Dual Governance State Machine.
    /// @param useEffectiveState If `true`, the check is performed against the `effective` state, which represents the state
    ///     the Dual Governance State Machine will enter after the next `activateNextState` call. If `false`, the check is
    ///     performed against the `persisted` state, which is the currently stored state of the system.
    /// @param proposalSubmittedAt The timestamp indicating when the proposal to be scheduled was originally submitted.
    /// @return bool A boolean indicating whether scheduling the proposal is allowed in the chosen state.
    function canScheduleProposal(
        Context storage self,
        bool useEffectiveState,
        Timestamp proposalSubmittedAt
    ) internal view returns (bool) {
        State state = useEffectiveState ? getEffectiveState(self) : getPersistedState(self);
        if (state == State.Normal) return true;

        /// @dev The `vetoSignallingActivatedAt` timestamp is only updated when the state transitions into `VetoSignalling`.
        ///     This ensures that, when checking the effective state, the expression below uses the most up-to-date
        ///     `vetoSignallingActivatedAt`. If checking against the persisted state, it is assumed that `activateNextState()`
        ///     has been invoked beforehand to ensure the persisted state is current.
        if (state == State.VetoCooldown) return proposalSubmittedAt <= self.vetoSignallingActivatedAt;
        return false;
    }

    /// @notice Returns whether the cancelling of the proposals is allowed based on the `persisted` or `effective`
    ///     state, depending on the `useEffectiveState` value.
    /// @param self The context of the Dual Governance State Machine.
    /// @param useEffectiveState If `true`, the check is performed against the `effective` state, which represents the state
    ///     the Dual Governance State Machine will enter after the next `activateNextState` call. If `false`, the check is
    ///     performed against the `persisted` state, which is the currently stored state of the system.
    /// @return bool A boolean indicating whether the cancelling of proposals is allowed in the selected state.
    function canCancelAllPendingProposals(Context storage self, bool useEffectiveState) internal view returns (bool) {
        State state = useEffectiveState ? getEffectiveState(self) : getPersistedState(self);
        return state == State.VetoSignalling || state == State.VetoSignallingDeactivation;
    }

    /// @notice Returns the configuration of the Dual Governance State Machine as provided by
    ///     the Dual Governance Config Provider.
    /// @param self The context of the Dual Governance State Machine.
    /// @return config The current configuration of the Dual Governance State
    function getDualGovernanceConfig(Context storage self)
        internal
        view
        returns (DualGovernanceConfig.Context memory config)
    {
        config = self.configProvider.getDualGovernanceConfig();
    }

    // ---
    // Private Methods
    // ---

    function _setConfigProvider(Context storage self, IDualGovernanceConfigProvider newConfigProvider) private {
        if (address(newConfigProvider) == address(0) || newConfigProvider == self.configProvider) {
            revert InvalidConfigProvider(newConfigProvider);
        }

        newConfigProvider.getDualGovernanceConfig().validate();

        self.configProvider = newConfigProvider;
        emit ConfigProviderSet(newConfigProvider);
    }

    function _deployNewSignallingEscrow(
        Context storage self,
        IEscrowBase escrowMasterCopy,
        Duration minAssetsLockDuration
    ) private {
        ISignallingEscrow newSignallingEscrow = ISignallingEscrow(Clones.clone(address(escrowMasterCopy)));
        newSignallingEscrow.initialize(minAssetsLockDuration);
        self.signallingEscrow = newSignallingEscrow;
        emit NewSignallingEscrowDeployed(newSignallingEscrow);
    }
}
