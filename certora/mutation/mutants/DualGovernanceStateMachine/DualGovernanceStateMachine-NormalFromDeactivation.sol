// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";

import {Duration} from "../types/Duration.sol";
import {PercentD16} from "../types/PercentD16.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

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
    }

    error AlreadyInitialized();

    event NewSignallingEscrowDeployed(IEscrow indexed escrow);
    event DualGovernanceStateChanged(State from, State to, Context state);

    function initialize(
        Context storage self,
        DualGovernanceConfig.Context memory config,
        address escrowMasterCopy
    ) internal {
        if (self.state != State.Unset) {
            revert AlreadyInitialized();
        }

        self.state = State.Normal;
        self.enteredAt = Timestamps.now();
        _deployNewSignallingEscrow(self, escrowMasterCopy, config.minAssetsLockDuration);

        emit DualGovernanceStateChanged(State.Unset, State.Normal, self);
    }

    function activateNextState(
        Context storage self,
        DualGovernanceConfig.Context memory config,
        address escrowMasterCopy
    ) internal {
        (State currentState, State newState) = DualGovernanceStateTransitions.getStateTransition(self, config);

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
            uint256 rageQuitRound = Math.min(self.rageQuitRound + 1, type(uint8).max);
            self.rageQuitRound = uint8(rageQuitRound);
            signallingEscrow.startRageQuit(
                config.rageQuitExtensionDelay, config.calcRageQuitWithdrawalsTimelock(rageQuitRound)
            );
            self.rageQuitEscrow = signallingEscrow;
            _deployNewSignallingEscrow(self, escrowMasterCopy, config.minAssetsLockDuration);
        }

        emit DualGovernanceStateChanged(currentState, newState, self);
    }

    function getCurrentContext(Context storage self) internal pure returns (Context memory) {
        return self;
    }

    function getCurrentState(Context storage self) internal view returns (State) {
        return self.state;
    }

    function getNormalOrVetoCooldownStateExitedAt(Context storage self) internal view returns (Timestamp) {
        return self.normalOrVetoCooldownExitedAt;
    }

    function getDynamicDelayDuration(
        Context storage self,
        DualGovernanceConfig.Context memory config
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

    function _deployNewSignallingEscrow(
        Context storage self,
        address escrowMasterCopy,
        Duration minAssetsLockDuration
    ) private {
        IEscrow newSignallingEscrow = IEscrow(Clones.clone(escrowMasterCopy));
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
        // MUTATION
        // go to ragequit always
        return State.RageQuit;
        // return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
        //     ? State.RageQuit
        //     : State.Normal;
        // return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
        //     ? State.VetoSignalling
        //     : State.Normal;
    }

    function _fromVetoSignallingState(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config
    ) private view returns (State) {
        PercentD16 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!config.isDynamicTimelockDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
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

        // MUTATION: always go to normal state
        // if (!config.isDynamicTimelockDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
        //     return State.VetoSignalling;
        // }

        // if (config.isSecondSealRageQuitSupportCrossed(rageQuitSupport)) {
        //     return State.RageQuit;
        // }

        // if (config.isVetoSignallingDeactivationMaxDurationPassed(self.enteredAt)) {
        //     return State.VetoCooldown;
        // }

        // return State.VetoSignallingDeactivation;
        return State.Normal;
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
