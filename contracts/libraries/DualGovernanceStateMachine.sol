// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";

import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

enum State {
    Unset,
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

library DualGovernanceStateMachine {
    using DualGovernanceStateMachineConfig for Config;

    struct Config {
        /// @dev slot 0: [0..63]
        uint64 firstSealRageQuitSupport;
        /// @dev slot 0: [64..127]
        uint64 secondSealRageQuitSupport;
        /// @dev slot 0: [128..159]
        Duration dynamicTimelockMaxDuration;
        /// @dev slot 0: [160..191]
        Duration dynamicTimelockMinDuration;
        /// @dev slot 0: [192..223]
        Duration vetoSignallingMinActiveDuration;
        /// @dev slot 0: [224..255]
        Duration vetoSignallingDeactivationMaxDuration;
        /// @dev slot 1: [0..31]
        Duration vetoCooldownDuration;
        /// @dev slot 1: [32..63]
        Duration rageQuitExtensionDelay;
        /// @dev slot 1: [64..95]
        Duration rageQuitEthWithdrawalsMinTimelock;
        /// @dev slot 1: [96..103]
        uint8 rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber;
        /// @dev slot 2-5
        uint256[3] rageQuitEthWithdrawalsTimelockGrowthCoeffs;
    }

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
        Config config;
    }

    error AlreadyInitialized();

    event NewSignallingEscrowDeployed(address indexed escrow);
    event DualGovernanceStateChanged(State from, State to, Context state);
    event DualGovernanceStateMachineConfigSet(Config newConfig);

    function initialize(Context storage self, address escrowMasterCopy) internal {
        if (self.state != State.Unset) {
            revert AlreadyInitialized();
        }

        self.state = State.Normal;
        self.enteredAt = Timestamps.now();
        _deployNewSignallingEscrow(self, escrowMasterCopy);

        emit DualGovernanceStateChanged(State.Unset, State.Normal, self);
    }

    function activateNextState(Context storage self) internal {
        (State currentStatus, State newStatus) = DualGovernanceStateTransitions.getStateTransition(self);

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
                self.config.rageQuitExtensionDelay, self.config.calcRageQuitWithdrawalsTimelock(rageQuitRound)
            );
            self.rageQuitEscrow = signallingEscrow;
            _deployNewSignallingEscrow(self, signallingEscrow.MASTER_COPY());
        }

        emit DualGovernanceStateChanged(currentStatus, newStatus, self);
    }

    function setConfig(Context storage self, Config calldata config) external {
        self.config = config;
        emit DualGovernanceStateMachineConfigSet(config);
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

    function getDynamicDelayDuration(Context storage self) internal view returns (Duration) {
        return self.config.calcDynamicDelayDuration(self.signallingEscrow.getRageQuitSupport());
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

    function _deployNewSignallingEscrow(Context storage self, address escrowMasterCopy) private {
        IEscrow clone = IEscrow(Clones.clone(escrowMasterCopy));
        clone.initialize(address(this), self.signallingEscrow.getAssetsUnlockDelay());
        self.signallingEscrow = clone;
        emit NewSignallingEscrowDeployed(address(clone));
    }
}

library DualGovernanceStateTransitions {
    using DualGovernanceStateMachineConfig for DualGovernanceStateMachine.Config;

    function getStateTransition(DualGovernanceStateMachine.Context storage self)
        internal
        view
        returns (State currentStatus, State nextStatus)
    {
        currentStatus = self.state;
        if (currentStatus == State.Normal) {
            nextStatus = _fromNormalState(self);
        } else if (currentStatus == State.VetoSignalling) {
            nextStatus = _fromVetoSignallingState(self);
        } else if (currentStatus == State.VetoSignallingDeactivation) {
            nextStatus = _fromVetoSignallingDeactivationState(self);
        } else if (currentStatus == State.VetoCooldown) {
            nextStatus = _fromVetoCooldownState(self);
        } else if (currentStatus == State.RageQuit) {
            nextStatus = _fromRageQuitState(self);
        } else {
            assert(false);
        }
    }

    function _fromNormalState(DualGovernanceStateMachine.Context storage self) private view returns (State) {
        return self.config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.Normal;
    }

    function _fromVetoSignallingState(DualGovernanceStateMachine.Context storage self) private view returns (State) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!self.config.isDynamicTimelockDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
            return State.VetoSignalling;
        }

        if (self.config.isSecondSealRageQuitSupportCrossed(rageQuitSupport)) {
            return State.RageQuit;
        }

        return self.config.isVetoSignallingReactivationDurationPassed(self.vetoSignallingReactivationTime)
            ? State.VetoSignallingDeactivation
            : State.VetoSignalling;
    }

    function _fromVetoSignallingDeactivationState(DualGovernanceStateMachine.Context storage self)
        private
        view
        returns (State)
    {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!self.config.isDynamicTimelockDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
            return State.VetoSignalling;
        }

        if (self.config.isSecondSealRageQuitSupportCrossed(rageQuitSupport)) {
            return State.RageQuit;
        }

        if (self.config.isVetoSignallingDeactivationMaxDurationPassed(self.enteredAt)) {
            return State.VetoCooldown;
        }

        return State.VetoSignallingDeactivation;
    }

    function _fromVetoCooldownState(DualGovernanceStateMachine.Context storage self) private view returns (State) {
        if (!self.config.isVetoCooldownDurationPassed(self.enteredAt)) {
            return State.VetoCooldown;
        }
        return self.config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.Normal;
    }

    function _fromRageQuitState(DualGovernanceStateMachine.Context storage self) private view returns (State) {
        if (!self.rageQuitEscrow.isRageQuitFinalized()) {
            return State.RageQuit;
        }
        return self.config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.VetoCooldown;
    }
}

library DualGovernanceStateMachineConfig {
    function isFirstSealRageQuitSupportCrossed(
        DualGovernanceStateMachine.Config memory self,
        uint256 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport > self.firstSealRageQuitSupport;
    }

    function isSecondSealRageQuitSupportCrossed(
        DualGovernanceStateMachine.Config memory self,
        uint256 rageQuitSupport
    ) internal pure returns (bool) {
        return rageQuitSupport > self.secondSealRageQuitSupport;
    }

    function isDynamicTimelockMaxDurationPassed(
        DualGovernanceStateMachine.Config memory self,
        Timestamp vetoSignallingActivatedAt
    ) internal view returns (bool) {
        return Timestamps.now() > self.dynamicTimelockMaxDuration.addTo(vetoSignallingActivatedAt);
    }

    function isDynamicTimelockDurationPassed(
        DualGovernanceStateMachine.Config memory self,
        Timestamp vetoSignallingActivatedAt,
        uint256 rageQuitSupport
    ) internal view returns (bool) {
        Duration dynamicTimelock = calcDynamicDelayDuration(self, rageQuitSupport);
        return Timestamps.now() > dynamicTimelock.addTo(vetoSignallingActivatedAt);
    }

    function isVetoSignallingReactivationDurationPassed(
        DualGovernanceStateMachine.Config memory self,
        Timestamp vetoSignallingReactivationTime
    ) internal view returns (bool) {
        return Timestamps.now() > self.vetoSignallingMinActiveDuration.addTo(vetoSignallingReactivationTime);
    }

    function isVetoSignallingDeactivationMaxDurationPassed(
        DualGovernanceStateMachine.Config memory self,
        Timestamp vetoSignallingDeactivationEnteredAt
    ) internal view returns (bool) {
        return Timestamps.now() > self.vetoSignallingDeactivationMaxDuration.addTo(vetoSignallingDeactivationEnteredAt);
    }

    function isVetoCooldownDurationPassed(
        DualGovernanceStateMachine.Config memory self,
        Timestamp vetoCooldownEnteredAt
    ) internal view returns (bool) {
        return Timestamps.now() > self.vetoCooldownDuration.addTo(vetoCooldownEnteredAt);
    }

    function calcDynamicDelayDuration(
        DualGovernanceStateMachine.Config memory self,
        uint256 rageQuitSupport
    ) internal pure returns (Duration duration_) {
        uint256 firstSealRageQuitSupport = self.firstSealRageQuitSupport;
        uint256 secondSealRageQuitSupport = self.secondSealRageQuitSupport;
        Duration dynamicTimelockMinDuration = self.dynamicTimelockMinDuration;
        Duration dynamicTimelockMaxDuration = self.dynamicTimelockMaxDuration;

        if (rageQuitSupport < firstSealRageQuitSupport) {
            return Durations.ZERO;
        }

        if (rageQuitSupport >= secondSealRageQuitSupport) {
            return dynamicTimelockMaxDuration;
        }

        duration_ = dynamicTimelockMinDuration
            + Durations.from(
                (rageQuitSupport - firstSealRageQuitSupport)
                    * (dynamicTimelockMaxDuration - dynamicTimelockMinDuration).toSeconds()
                    / (secondSealRageQuitSupport - firstSealRageQuitSupport)
            );
    }

    function calcRageQuitWithdrawalsTimelock(
        DualGovernanceStateMachine.Config memory self,
        uint256 rageQuitRound
    ) internal pure returns (Duration) {
        if (rageQuitRound < self.rageQuitEthWithdrawalsTimelockGrowthStartSeqNumber) {
            return self.rageQuitEthWithdrawalsMinTimelock;
        }
        return self.rageQuitEthWithdrawalsMinTimelock
            + Durations.from(
                (
                    self.rageQuitEthWithdrawalsTimelockGrowthCoeffs[0] * rageQuitRound * rageQuitRound
                        + self.rageQuitEthWithdrawalsTimelockGrowthCoeffs[1] * rageQuitRound
                        + self.rageQuitEthWithdrawalsTimelockGrowthCoeffs[2]
                ) / 10 ** 18
            ); // TODO: rewrite in a prettier way
    }
}
