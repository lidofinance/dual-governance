// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";
import {ISealable} from "../interfaces/ISealable.sol";
import {IDualGovernanceConfiguration} from "../interfaces/IConfiguration.sol";

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";
import {DualGovernanceConfig, DualGovernanceConfigUtils} from "./DualGovernanceConfig.sol";

enum Status {
    Unset,
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

library DualGovernanceStateMachine {
    using DualGovernanceConfigUtils for DualGovernanceConfig;
    using DualGovernanceStateTransitions for State;

    struct State {
        ///
        /// @dev slot 0: [0..7]
        /// The current state of the Dual Governance FSM
        Status status;
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
    event DualGovernanceStateChanged(Status from, Status to, State state);

    function initialize(State storage self, address escrowMasterCopy) internal {
        if (self.status != Status.Unset) {
            revert AlreadyInitialized();
        }

        self.status = Status.Normal;
        self.enteredAt = Timestamps.now();
        _deployNewSignallingEscrow(self, escrowMasterCopy);

        emit DualGovernanceStateChanged(Status.Unset, Status.Normal, self);
    }

    function activateNextState(State storage self, DualGovernanceConfig memory config) internal {
        (Status currentStatus, Status newStatus) = self.getStateTransition(config);

        if (currentStatus == newStatus) {
            return;
        }

        self.status = newStatus;
        self.enteredAt = Timestamps.now();

        if (currentStatus == Status.Normal || currentStatus == Status.VetoCooldown) {
            self.normalOrVetoCooldownExitedAt = Timestamps.now();
        }

        if (newStatus == Status.Normal && self.rageQuitRound != 0) {
            self.rageQuitRound = 0;
        } else if (newStatus == Status.VetoSignalling) {
            if (currentStatus == Status.VetoSignallingDeactivation) {
                self.vetoSignallingReactivationTime = Timestamps.now();
            } else {
                self.vetoSignallingActivatedAt = Timestamps.now();
            }
        } else if (newStatus == Status.RageQuit) {
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

    function getCurrentState(State storage self) internal pure returns (State memory) {
        return self;
    }

    function getCurrentStatus(State storage self) internal view returns (Status) {
        return self.status;
    }

    function getDynamicTimelockDuration(
        State storage self,
        DualGovernanceConfig memory config
    ) internal view returns (Duration) {
        return config.calcDynamicTimelockDuration(self.signallingEscrow.getRageQuitSupport());
    }

    function canSubmitProposal(State storage self) internal view returns (bool) {
        Status state = self.status;
        return state != Status.VetoSignallingDeactivation && state != Status.VetoCooldown;
    }

    function canScheduleProposal(State storage self, Timestamp proposalSubmissionTime) internal view returns (bool) {
        Status state = self.status;
        if (state == Status.Normal) return true;
        if (state == Status.VetoCooldown) {
            return proposalSubmissionTime <= self.vetoSignallingActivatedAt;
        }
        return false;
    }

    function isTiebreak(State storage self, IDualGovernanceConfiguration config) internal view returns (bool) {
        Status state = self.status;
        if (state == Status.Normal || state == Status.VetoCooldown) return false;

        // when the governance is locked for long period of time
        if (Timestamps.now() >= config.TIE_BREAK_ACTIVATION_TIMEOUT().addTo(self.normalOrVetoCooldownExitedAt)) {
            return true;
        }

        if (self.status != Status.RageQuit) return false;

        address[] memory sealableWithdrawalBlockers = config.sealableWithdrawalBlockers();
        for (uint256 i = 0; i < sealableWithdrawalBlockers.length; ++i) {
            if (ISealable(sealableWithdrawalBlockers[i]).isPaused()) return true;
        }
        return false;
    }

    function _deployNewSignallingEscrow(State storage self, address escrowMasterCopy) private {
        IEscrow clone = IEscrow(Clones.clone(escrowMasterCopy));
        clone.initialize(address(this));
        self.signallingEscrow = clone;
        emit NewSignallingEscrowDeployed(address(clone));
    }
}

library DualGovernanceStateTransitions {
    using DualGovernanceConfigUtils for DualGovernanceConfig;

    function getStateTransition(
        DualGovernanceStateMachine.State storage self,
        DualGovernanceConfig memory config
    ) internal view returns (Status currentStatus, Status nextStatus) {
        currentStatus = self.status;
        if (currentStatus == Status.Normal) {
            nextStatus = _fromNormalState(self, config);
        } else if (currentStatus == Status.VetoSignalling) {
            nextStatus = _fromVetoSignallingState(self, config);
        } else if (currentStatus == Status.VetoSignallingDeactivation) {
            nextStatus = _fromVetoSignallingDeactivationState(self, config);
        } else if (currentStatus == Status.VetoCooldown) {
            nextStatus = _fromVetoCooldownState(self, config);
        } else if (currentStatus == Status.RageQuit) {
            nextStatus = _fromRageQuitState(self, config);
        } else {
            assert(false);
        }
    }

    function _fromNormalState(
        DualGovernanceStateMachine.State storage self,
        DualGovernanceConfig memory config
    ) private view returns (Status) {
        return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? Status.VetoSignalling
            : Status.Normal;
    }

    function _fromVetoSignallingState(
        DualGovernanceStateMachine.State storage self,
        DualGovernanceConfig memory config
    ) private view returns (Status) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!config.isDynamicTimelockDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
            return Status.VetoSignalling;
        }

        if (config.isSecondSealRageQuitSupportCrossed(rageQuitSupport)) {
            return Status.RageQuit;
        }

        return config.isVetoSignallingReactivationDurationPassed(self.vetoSignallingReactivationTime)
            ? Status.VetoSignallingDeactivation
            : Status.VetoSignalling;
    }

    function _fromVetoSignallingDeactivationState(
        DualGovernanceStateMachine.State storage self,
        DualGovernanceConfig memory config
    ) private view returns (Status) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!config.isDynamicTimelockDurationPassed(self.vetoSignallingActivatedAt, rageQuitSupport)) {
            return Status.VetoSignalling;
        }

        if (config.isSecondSealRageQuitSupportCrossed(rageQuitSupport)) {
            return Status.RageQuit;
        }

        if (config.isVetoSignallingDeactivationMaxDurationPassed(self.enteredAt)) {
            return Status.VetoCooldown;
        }

        return Status.VetoSignallingDeactivation;
    }

    function _fromVetoCooldownState(
        DualGovernanceStateMachine.State storage self,
        DualGovernanceConfig memory config
    ) private view returns (Status) {
        if (!config.isVetoCooldownDurationPassed(self.enteredAt)) {
            return Status.VetoCooldown;
        }
        return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? Status.VetoSignalling
            : Status.Normal;
    }

    function _fromRageQuitState(
        DualGovernanceStateMachine.State storage self,
        DualGovernanceConfig memory config
    ) private view returns (Status) {
        if (!self.rageQuitEscrow.isRageQuitFinalized()) {
            return Status.RageQuit;
        }
        return config.isFirstSealRageQuitSupportCrossed(self.signallingEscrow.getRageQuitSupport())
            ? Status.VetoSignalling
            : Status.VetoCooldown;
    }
}
