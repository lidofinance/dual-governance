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
        /// The current state of the Dual Governance state machine
        State state;
        ///
        /// @dev slot 0: [8..47]
        /// The timestamp when the Dual Governance state machine entered the current state
        Timestamp enteredAt;
        ///
        /// @dev slot 0: [48..87]
        /// The time the VetoSignalling state machine state was entered the last time
        Timestamp vetoSignallingActivatedAt;
        ///
        /// @dev slot 0: [88..127]
        /// The last time VetoSignallingDeactivation -> VetoSignalling transition happened
        Timestamp vetoSignallingReactivationTime;
        ///
        /// @dev slot 1: [128..168]
        /// The last time when the Dual Governance state machine exited Normal or VetoCooldown state
        Timestamp normalOrVetoCooldownExitedAt;
        ///
        /// @dev slot 0: [168..175]
        /// The number of the Rage Quit round. Initial value is 0.
        uint8 rageQuitRound;
        ///
        /// @dev slot 0: [176..255]
        uint80 currentSignallingEscrowIndex;
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
        (State currentState, State newState) =
            DualGovernanceStateTransitions.getStateTransition(self, config, escrowMasterCopy);

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
            IEscrow signallingEscrow = getSignallingEscrow(self, escrowMasterCopy);
            uint256 rageQuitRound = Math.min(self.rageQuitRound + 1, type(uint8).max);
            self.rageQuitRound = uint8(rageQuitRound);
            signallingEscrow.startRageQuit(
                config.rageQuitExtensionDelay, config.calcRageQuitWithdrawalsTimelock(rageQuitRound)
            );
            self.currentSignallingEscrowIndex += 1;
            _deployNewSignallingEscrow(self, escrowMasterCopy, config.minAssetsLockDuration);
        }

        emit DualGovernanceStateChanged(currentState, newState, self);
    }

    function getSignallingEscrow(
        Context memory self,
        address escrowMasterCopy
    ) internal view returns (IEscrow signallingEscrow) {
        signallingEscrow = IEscrow(
            Clones.predictDeterministicAddress(
                escrowMasterCopy, bytes32(uint256(self.currentSignallingEscrowIndex)), address(this)
            )
        );
    }

    function getLastRageQuitEscrow(
        Context memory self,
        address escrowMasterCopy
    ) internal view returns (IEscrow rageQuitEscrow) {
        rageQuitEscrow = IEscrow(
            Clones.predictDeterministicAddress(
                escrowMasterCopy, bytes32(uint256(self.currentSignallingEscrowIndex - 1)), address(this)
            )
        );
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
        DualGovernanceConfig.Context memory config,
        address escrowMasterCopy
    ) internal view returns (Duration) {
        return config.calcDynamicDelayDuration(getSignallingEscrow(self, escrowMasterCopy).getRageQuitSupport());
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
        IEscrow newSignallingEscrow =
            IEscrow(Clones.cloneDeterministic(escrowMasterCopy, bytes32(uint256(self.currentSignallingEscrowIndex))));
        newSignallingEscrow.initialize(minAssetsLockDuration);
        emit NewSignallingEscrowDeployed(newSignallingEscrow);
    }
}

library DualGovernanceStateTransitions {
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    function getStateTransition(
        DualGovernanceStateMachine.Context storage self,
        DualGovernanceConfig.Context memory config,
        address escrowMasterCopy
    ) internal view returns (State currentState, State nextState) {
        currentState = self.state;
        if (currentState == State.Normal) {
            nextState = _fromNormalState(self, config, escrowMasterCopy);
        } else if (currentState == State.VetoSignalling) {
            nextState = _fromVetoSignallingState(self, config, escrowMasterCopy);
        } else if (currentState == State.VetoSignallingDeactivation) {
            nextState = _fromVetoSignallingDeactivationState(self, config, escrowMasterCopy);
        } else if (currentState == State.VetoCooldown) {
            nextState = _fromVetoCooldownState(self, config, escrowMasterCopy);
        } else if (currentState == State.RageQuit) {
            nextState = _fromRageQuitState(self, config, escrowMasterCopy);
        } else {
            assert(false);
        }
    }

    function _fromNormalState(
        DualGovernanceStateMachine.Context memory self,
        DualGovernanceConfig.Context memory config,
        address escrowMasterCopy
    ) private view returns (State) {
        return config.isFirstSealRageQuitSupportCrossed(
            DualGovernanceStateMachine.getSignallingEscrow(self, escrowMasterCopy).getRageQuitSupport()
        ) ? State.VetoSignalling : State.Normal;
    }

    function _fromVetoSignallingState(
        DualGovernanceStateMachine.Context memory self,
        DualGovernanceConfig.Context memory config,
        address escrowMasterCopy
    ) private view returns (State) {
        PercentD16 rageQuitSupport =
            DualGovernanceStateMachine.getSignallingEscrow(self, escrowMasterCopy).getRageQuitSupport();

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
        DualGovernanceStateMachine.Context memory self,
        DualGovernanceConfig.Context memory config,
        address escrowMasterCopy
    ) private view returns (State) {
        PercentD16 rageQuitSupport =
            DualGovernanceStateMachine.getSignallingEscrow(self, escrowMasterCopy).getRageQuitSupport();

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
        DualGovernanceStateMachine.Context memory self,
        DualGovernanceConfig.Context memory config,
        address escrowMasterCopy
    ) private view returns (State) {
        if (!config.isVetoCooldownDurationPassed(self.enteredAt)) {
            return State.VetoCooldown;
        }
        return config.isFirstSealRageQuitSupportCrossed(
            DualGovernanceStateMachine.getSignallingEscrow(self, escrowMasterCopy).getRageQuitSupport()
        ) ? State.VetoSignalling : State.Normal;
    }

    function _fromRageQuitState(
        DualGovernanceStateMachine.Context memory self,
        DualGovernanceConfig.Context memory config,
        address escrowMasterCopy
    ) private view returns (State) {
        if (!DualGovernanceStateMachine.getLastRageQuitEscrow(self, escrowMasterCopy).isRageQuitFinalized()) {
            return State.RageQuit;
        }
        return config.isFirstSealRageQuitSupportCrossed(
            DualGovernanceStateMachine.getSignallingEscrow(self, escrowMasterCopy).getRageQuitSupport()
        ) ? State.VetoSignalling : State.VetoCooldown;
    }
}
