// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";
import {ISealable} from "../interfaces/ISealable.sol";

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";
import {TiebreakConfig, DualGovernanceConfig, DualGovernanceConfigUtils} from "./DualGovernanceConfig.sol";

enum State {
    Unset,
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

library DualGovernanceState {
    using DualGovernanceConfigUtils for DualGovernanceConfig;

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
    }

    error AlreadyInitialized();

    event NewSignallingEscrowDeployed(address indexed escrow);
    event DualGovernanceStateChanged(State from, State to, Context state);

    function initialize(Context storage self, address escrowMasterCopy) internal {
        if (self.state != State.Unset) {
            revert AlreadyInitialized();
        }

        self.state = State.Normal;
        self.enteredAt = Timestamps.now();
        _deployNewSignallingEscrow(self, escrowMasterCopy);

        emit DualGovernanceStateChanged(State.Unset, State.Normal, self);
    }

    function activateNextState(Context storage self, DualGovernanceConfig memory config) internal {
        (State currentStatus, State newStatus) = DualGovernanceStateTransitions.getStateTransition(self, config);

        if (currentStatus == newStatus) {
            return;
        }

        self.state = newStatus;
        self.enteredAt = Timestamps.now();

        if (currentStatus == State.Normal || currentStatus == State.VetoCooldown) {
            self.normalOrVetoCooldownExitedAt = Timestamps.now();
        }

        if (newStatus == State.Normal && self.rageQuitRound != 0) {
            self.rageQuitRound = 0;
        } else if (newStatus == State.VetoSignalling) {
            if (currentStatus == State.VetoSignallingDeactivation) {
                self.vetoSignallingReactivationTime = Timestamps.now();
            } else {
                self.vetoSignallingActivatedAt = Timestamps.now();
            }
        } else if (newStatus == State.RageQuit) {
            IEscrow signallingEscrow = self.signallingEscrow;
            uint256 rageQuitRound = Math.min(self.rageQuitRound + 1, type(uint8).max);
            self.rageQuitRound = uint8(rageQuitRound);
            signallingEscrow.startRageQuit(
                config.rageQuitExtensionDelay, config.calcRageQuitWithdrawalsTimelock(rageQuitRound)
            );
            self.rageQuitEscrow = signallingEscrow;
            _deployNewSignallingEscrow(self, signallingEscrow.MASTER_COPY());
        }

        emit DualGovernanceStateChanged(currentStatus, newStatus, self);
    }

    function getCurrentContext(Context storage self) internal pure returns (Context memory) {
        return self;
    }

    function getCurrentState(Context storage self) internal view returns (State) {
        return self.state;
    }

    function getDynamicDelayDuration(
        Context storage self,
        DualGovernanceConfig memory config
    ) internal view returns (Duration) {
        return config.calcDynamicDelayDuration(self.signallingEscrow.getRageQuitSupport());
    }

    function canSubmitProposal(Context storage self) internal view returns (bool) {
        State state = self.state;
        return state != State.VetoSignallingDeactivation && state != State.VetoCooldown;
    }

    function canScheduleProposal(Context storage self, Timestamp proposalSubmissionTime) internal view returns (bool) {
        State state = self.state;
        if (state == State.Normal) return true;
        if (state == State.VetoCooldown) {
            return proposalSubmissionTime <= self.vetoSignallingActivatedAt;
        }
        return false;
    }

    function isDeadlock(Context storage self, TiebreakConfig memory config) internal view returns (bool) {
        State state = self.state;
        if (state == State.Normal || state == State.VetoCooldown) return false;

        // when the governance is locked for long period of time
        if (Timestamps.now() >= config.tiebreakActivationTimeout.addTo(self.normalOrVetoCooldownExitedAt)) {
            return true;
        }

        if (self.state != State.RageQuit) return false;

        uint256 potentialDeadlockSealablesCount = config.potentialDeadlockSealables.length;
        for (uint256 i = 0; i < potentialDeadlockSealablesCount; ++i) {
            if (ISealable(config.potentialDeadlockSealables[i]).isPaused()) return true;
        }
        return false;
    }

    function _deployNewSignallingEscrow(Context storage self, address escrowMasterCopy) private {
        IEscrow clone = IEscrow(Clones.clone(escrowMasterCopy));
        clone.initialize(address(this));
        self.signallingEscrow = clone;
        emit NewSignallingEscrowDeployed(address(clone));
    }
}

library DualGovernanceStateTransitions {
    using DualGovernanceConfigUtils for DualGovernanceConfig;

    function getStateTransition(
        DualGovernanceState.Context storage self,
        DualGovernanceConfig memory config
    ) internal view returns (State currentStatus, State nextStatus) {
        currentStatus = self.state;
        if (currentStatus == State.Normal) {
            nextStatus = _fromNormalState(self, config);
        } else if (currentStatus == State.VetoSignalling) {
            nextStatus = _fromVetoSignallingState(self, config);
        } else if (currentStatus == State.VetoSignallingDeactivation) {
            nextStatus = _fromVetoSignallingDeactivationState(self, config);
        } else if (currentStatus == State.VetoCooldown) {
            nextStatus = _fromVetoCooldownState(self, config);
        } else if (currentStatus == State.RageQuit) {
            nextStatus = _fromRageQuitState(self, config);
        } else {
            assert(false);
        }
    }

    function _fromNormalState(
        DualGovernanceState.Context storage self,
        DualGovernanceConfig memory config
    ) private view returns (State) {
        return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.Normal;
    }

    function _fromVetoSignallingState(
        DualGovernanceState.Context storage self,
        DualGovernanceConfig memory config
    ) private view returns (State) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!config.isDynamicTimelockDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
            return State.VetoSignalling;
        }

        if (config.isSecondSealRageQuitSupportCrossed(rageQuitSupport)) {
            return State.RageQuit;
        }

        return config.isVetoSignallingReactivationDurationPassed(self.vetoSignallingReactivationTime)
            ? State.VetoSignallingDeactivation
            : State.VetoSignalling;
    }

    function _fromVetoSignallingDeactivationState(
        DualGovernanceState.Context storage self,
        DualGovernanceConfig memory config
    ) private view returns (State) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!config.isDynamicTimelockDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
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
        DualGovernanceState.Context storage self,
        DualGovernanceConfig memory config
    ) private view returns (State) {
        if (!config.isVetoCooldownDurationPassed(self.enteredAt)) {
            return State.VetoCooldown;
        }
        return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.Normal;
    }

    function _fromRageQuitState(
        DualGovernanceState.Context storage self,
        DualGovernanceConfig memory config
    ) private view returns (State) {
        if (!self.rageQuitEscrow.isRageQuitFinalized()) {
            return State.RageQuit;
        }
        return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.VetoCooldown;
    }
}
