// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {Duration} from "../types/Duration.sol";
import {PercentD16} from "../types/PercentD16.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";
import {IDualGovernance} from "../interfaces/IDualGovernance.sol";
import {IDualGovernanceConfigProvider} from "../interfaces/IDualGovernanceConfigProvider.sol";

import {DualGovernanceConfig} from "./DualGovernanceConfig.sol";

enum State {
    Unset,
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

library DualGovernanceStateMachine {
    using DualGovernanceStateTransitions for Context;
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    struct Context {
        ///
        /// @dev slot 0: [0..7]
        /// The current state of the Dual Governance FSM
        State state;
        ///
        /// @dev slot 0: [8..47]
        /// The timestamp when the Dual Governance FSM entered the current state
        Timestamp enteredAt;
        ///
        /// @dev slot 0: [48..87]
        /// The time the VetoSignalling FSM state was entered the last time
        Timestamp vetoSignallingActivatedAt;
        ///
        /// @dev slot 0: [88..247]
        /// The address of the currently used Veto Signalling Escrow
        IEscrow signallingEscrow;
        ///
        /// @dev slot 0: [248..255]
        /// The number of the Rage Quit round. Initial value is 0.
        uint8 rageQuitRound;
        ///
        /// @dev slot 1: [0..39]
        /// The last time VetoSignallingDeactivation -> VetoSignalling transition happened
        Timestamp vetoSignallingReactivationTime;
        ///
        /// @dev slot 1: [40..79]
        /// The last time when the Dual Governance FSM exited Normal or VetoCooldown state
        Timestamp normalOrVetoCooldownExitedAt;
        ///
        /// @dev slot 1: [80..239]
        /// The address of the Escrow used during the last (may be ongoing) Rage Quit process
        IEscrow rageQuitEscrow;
        ///
        /// @dev slot 2: [0..159]
        /// The address of the Dual Governance config provider
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

    event NewSignallingEscrowDeployed(IEscrow indexed escrow);
    event DualGovernanceStateChanged(State from, State to, Context state);
    event ConfigProviderSet(IDualGovernanceConfigProvider newConfigProvider);

    // ---
    // Constants
    // ---

    uint256 internal constant MAX_RAGE_QUIT_ROUND = type(uint8).max;

    // ---
    // Main functionality
    // ---

    function initialize(
        Context storage self,
        IDualGovernanceConfigProvider configProvider,
        IEscrow escrowMasterCopy
    ) internal {
        if (self.state != State.Unset) {
            revert AlreadyInitialized();
        }

        self.state = State.Normal;
        self.enteredAt = Timestamps.now();

        _setConfigProvider(self, configProvider);

        DualGovernanceConfig.Context memory config = configProvider.getDualGovernanceConfig();
        _deployNewSignallingEscrow(self, escrowMasterCopy, config.minAssetsLockDuration);

        emit DualGovernanceStateChanged(State.Unset, State.Normal, self);
    }

    function activateNextState(Context storage self, IEscrow escrowMasterCopy) internal {
        DualGovernanceConfig.Context memory config = getDualGovernanceConfig(self);
        (State currentState, State newState) = self.getStateTransition(config);

        if (currentState == newState) {
            return;
        }

        self.state = newState;
        self.enteredAt = Timestamps.now();

        if (currentState == State.Normal || currentState == State.VetoCooldown) {
            self.normalOrVetoCooldownExitedAt = Timestamps.now();
        }

        if (newState == State.Normal && self.rageQuitRound != 0) {
            self.rageQuitRound = 0;
        } else if (newState == State.VetoSignalling) {
            if (currentState == State.VetoSignallingDeactivation) {
                self.vetoSignallingReactivationTime = Timestamps.now();
            } else {
                self.vetoSignallingActivatedAt = Timestamps.now();
            }
        } else if (newState == State.RageQuit) {
            IEscrow signallingEscrow = self.signallingEscrow;

            uint256 currentRageQuitRound = self.rageQuitRound;

            /// @dev Limits the maximum value of the rage quit round to prevent failures due to arithmetic overflow
            /// if the number of consecutive rage quits reaches MAX_RAGE_QUIT_ROUND.
            uint256 newRageQuitRound = Math.min(currentRageQuitRound + 1, MAX_RAGE_QUIT_ROUND);
            self.rageQuitRound = uint8(newRageQuitRound);

            signallingEscrow.startRageQuit(
                config.rageQuitExtensionPeriodDuration, config.calcRageQuitWithdrawalsDelay(newRageQuitRound)
            );
            self.rageQuitEscrow = signallingEscrow;
            _deployNewSignallingEscrow(self, escrowMasterCopy, config.minAssetsLockDuration);
        }

        emit DualGovernanceStateChanged(currentState, newState, self);
    }

    function setConfigProvider(Context storage self, IDualGovernanceConfigProvider newConfigProvider) internal {
        _setConfigProvider(self, newConfigProvider);

        /// @dev minAssetsLockDuration is stored as a storage variable in the Signalling Escrow instance.
        /// To synchronize the new value with the current Signalling Escrow, it must be manually updated.
        self.signallingEscrow.setMinAssetsLockDuration(
            newConfigProvider.getDualGovernanceConfig().minAssetsLockDuration
        );
    }

    // ---
    // Getters
    // ---

    function getStateDetails(Context storage self)
        internal
        view
        returns (IDualGovernance.StateDetails memory stateDetails)
    {
        DualGovernanceConfig.Context memory config = getDualGovernanceConfig(self);
        (State currentState, State nextState) = self.getStateTransition(config);

        stateDetails.state = currentState;
        stateDetails.enteredAt = self.enteredAt;
        stateDetails.nextState = nextState;
        stateDetails.vetoSignallingActivatedAt = self.vetoSignallingActivatedAt;
        stateDetails.vetoSignallingReactivationTime = self.vetoSignallingReactivationTime;
        stateDetails.normalOrVetoCooldownExitedAt = self.normalOrVetoCooldownExitedAt;
        stateDetails.rageQuitRound = self.rageQuitRound;
        stateDetails.vetoSignallingDuration =
            config.calcVetoSignallingDuration(self.signallingEscrow.getRageQuitSupport());
    }

    function getPersistedState(Context storage self) internal view returns (State persistedState) {
        persistedState = self.state;
    }

    function getEffectiveState(Context storage self) internal view returns (State effectiveState) {
        ( /* persistedState */ , effectiveState) = self.getStateTransition(getDualGovernanceConfig(self));
    }

    function getNormalOrVetoCooldownStateExitedAt(Context storage self) internal view returns (Timestamp) {
        return self.normalOrVetoCooldownExitedAt;
    }

    function canSubmitProposal(Context storage self, bool useEffectiveState) internal view returns (bool) {
        State effectiveState = useEffectiveState ? getEffectiveState(self) : getPersistedState(self);
        return effectiveState != State.VetoSignallingDeactivation && effectiveState != State.VetoCooldown;
    }

    function canScheduleProposal(
        Context storage self,
        bool useEffectiveState,
        Timestamp proposalSubmittedAt
    ) internal view returns (bool) {
        State effectiveState = useEffectiveState ? getEffectiveState(self) : getPersistedState(self);
        if (effectiveState == State.Normal) return true;
        if (effectiveState == State.VetoCooldown) return proposalSubmittedAt <= self.vetoSignallingActivatedAt;
        return false;
    }

    function getDualGovernanceConfigProvider(Context storage self)
        internal
        view
        returns (IDualGovernanceConfigProvider)
    {
        return self.configProvider;
    }

    function getDualGovernanceConfig(Context storage self)
        internal
        view
        returns (DualGovernanceConfig.Context memory)
    {
        return self.configProvider.getDualGovernanceConfig();
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
        IEscrow escrowMasterCopy,
        Duration minAssetsLockDuration
    ) private {
        IEscrow newSignallingEscrow = IEscrow(Clones.clone(address(escrowMasterCopy)));
        newSignallingEscrow.initialize(minAssetsLockDuration);
        self.signallingEscrow = newSignallingEscrow;
        emit NewSignallingEscrowDeployed(newSignallingEscrow);
    }
}

library DualGovernanceStateTransitions {
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    function getStateTransition(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config
    ) internal view returns (State currentState, State nextStatus) {
        currentState = self.state;
        if (currentState == State.Normal) {
            nextStatus = _fromNormalState(self, config);
        } else if (currentState == State.VetoSignalling) {
            nextStatus = _fromVetoSignallingState(self, config);
        } else if (currentState == State.VetoSignallingDeactivation) {
            nextStatus = _fromVetoSignallingDeactivationState(self, config);
        } else if (currentState == State.VetoCooldown) {
            nextStatus = _fromVetoCooldownState(self, config);
        } else if (currentState == State.RageQuit) {
            nextStatus = _fromRageQuitState(self, config);
        } else {
            assert(false);
        }
    }

    function _fromNormalState(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config
    ) private view returns (State) {
        return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
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

        if (config.isSecondSealRageQuitSupportCrossed(rageQuitSupport)) {
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

        if (config.isSecondSealRageQuitSupportCrossed(rageQuitSupport)) {
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
        return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
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
        return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.VetoCooldown;
    }
}
