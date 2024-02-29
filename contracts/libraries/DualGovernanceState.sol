// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";
import {IConfiguration} from "../interfaces/IConfiguration.sol";

import {timestamp} from "../utils/time.sol";

interface IPausableUntil {
    function isPaused() external view returns (bool);
}

enum Status {
    Normal,
    VetoSignalling,
    VetoSignallingHalted,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

library DualGovernanceState {
    struct State {
        Status status;
        uint40 enteredAt;
        uint40 signalingActivatedAt;
        uint40 lastAdoptableStateExitedAt;
        IEscrow signallingEscrow;
        IEscrow rageQuitEscrow;
        bool isProposalsCreationOnHalt;
    }

    error AlreadyInitialized();

    event NewSignallingEscrowDeployed(address indexed escrow);

    function initialize(State storage self, address escrowMasterCopy) internal {
        if (address(self.signallingEscrow) != address(0)) {
            revert AlreadyInitialized();
        }
        _deployNewSignalingEscrow(self, escrowMasterCopy);
    }

    function activateNextState(State storage self, IConfiguration config) internal returns (Status newStatus) {
        Status oldStatus = self.status;
        if (oldStatus == Status.Normal) {
            _fromNormalState(self, config);
        } else if (oldStatus == Status.VetoSignalling) {
            _fromVetoSignalingState(self, config);
        } else if (oldStatus == Status.VetoSignallingDeactivation) {
            _fromVetoSignalingDeactivationState(self, config);
        } else if (oldStatus == Status.VetoCooldown) {
            _fromVetoCooldownState(self, config);
        } else if (oldStatus == Status.RageQuit) {
            _fromRageQuitState(self, config);
        } else {
            assert(false);
        }

        newStatus = self.status;
        if (oldStatus != newStatus) {
            _handleStatusChangeSideEffects(self, oldStatus, newStatus);
        }
    }

    function haltProposalsCreation(State storage self) internal {
        if (self.status == Status.VetoSignalling || self.status == Status.VetoSignallingDeactivation) {
            self.isProposalsCreationOnHalt = true;
        }
    }

    function currentState(State storage self) internal view returns (Status) {
        Status status = self.status;
        if (self.isProposalsCreationOnHalt && status == Status.VetoSignalling) {
            return Status.VetoSignallingHalted;
        }
        return status;
    }

    function isProposalsCreationAllowed(State storage self) internal view returns (bool) {
        if (self.isProposalsCreationOnHalt) return false;
        Status status = self.status;
        return status != Status.VetoSignallingDeactivation && status != Status.VetoCooldown;
    }

    function isProposalsAdoptionAllowed(State storage self) internal view returns (bool) {
        Status status = self.status;
        return status == Status.Normal || status == Status.VetoCooldown;
    }

    function isDeadLockedOrFrozen(State storage self, IConfiguration config) internal view returns (bool) {
        if (isProposalsAdoptionAllowed(self)) return false;

        // for the governance is locked for long period of time
        if (block.timestamp - self.lastAdoptableStateExitedAt >= config.TIE_BREAK_ACTIVATION_TIMEOUT()) return true;

        if (self.status != Status.RageQuit) return false;

        address[] memory sealableWithdrawalBlockers = config.sealableWithdrawalBlockers();
        for (uint256 i = 0; i < sealableWithdrawalBlockers.length; ++i) {
            if (IPausableUntil(sealableWithdrawalBlockers[i]).isPaused()) return true;
        }
        return false;
    }

    // ---
    // State Transitions
    // ---

    function _fromNormalState(State storage self, IConfiguration config) private {
        (uint256 totalSupport,) = self.signallingEscrow.getSignallingState();
        if (totalSupport >= config.FIRST_SEAL_THRESHOLD()) {
            _set(self, Status.VetoSignalling);
        }
    }

    function _fromVetoSignalingState(State storage self, IConfiguration config) private {
        (uint256 totalSupport,) = self.signallingEscrow.getSignallingState();

        if (totalSupport < config.FIRST_SEAL_THRESHOLD()) {
            return _set(self, Status.VetoSignallingDeactivation);
        }

        uint256 currentDuration = block.timestamp - self.signalingActivatedAt;
        uint256 targetDuration = _calcVetoSignallingTargetDuration(config, totalSupport);

        if (currentDuration < targetDuration) {
            return;
        }

        _set(self, _isSecondThresholdReached(self, config) ? Status.RageQuit : Status.VetoSignallingDeactivation);
    }

    function _fromVetoSignalingDeactivationState(State storage self, IConfiguration config) private {
        uint256 currentDeactivationDuration = block.timestamp - self.enteredAt;
        if (currentDeactivationDuration >= config.SIGNALLING_DEACTIVATION_DURATION()) {
            return _set(self, Status.VetoCooldown);
        }

        (uint256 totalSupport, uint256 rageQuitSupport) = self.signallingEscrow.getSignallingState();
        uint256 currentSignallingDuration = block.timestamp - self.signalingActivatedAt;
        uint256 targetSignallingDuration = _calcVetoSignallingTargetDuration(config, totalSupport);

        if (currentSignallingDuration >= targetSignallingDuration) {
            if (rageQuitSupport >= config.SECOND_SEAL_THRESHOLD()) {
                _set(self, Status.RageQuit);
            }
        } else if (totalSupport >= config.FIRST_SEAL_THRESHOLD()) {
            _set(self, Status.VetoSignalling);
        }
    }

    function _fromVetoCooldownState(State storage self, IConfiguration config) private {
        uint256 duration_ = block.timestamp - self.enteredAt;
        if (duration_ < config.SIGNALING_COOLDOWN_DURATION()) {
            return;
        }
        _set(self, _isFirstThresholdReached(self, config) ? Status.VetoSignalling : Status.Normal);
    }

    function _fromRageQuitState(State storage self, IConfiguration config) private {
        if (!self.rageQuitEscrow.isRageQuitFinalized()) {
            return;
        }
        _set(self, _isFirstThresholdReached(self, config) ? Status.VetoSignalling : Status.Normal);
    }

    function _set(State storage self, Status newStatus) private {
        uint40 currentTime = timestamp();

        Status oldStatus = self.status;

        assert(oldStatus != newStatus);
        self.status = newStatus;
        self.enteredAt = currentTime;
    }

    function _handleStatusChangeSideEffects(State storage self, Status oldStatus, Status newStatus) private {
        uint40 currentTime = timestamp();
        // track the time when the governance state allowed execution
        if (oldStatus == Status.Normal || oldStatus == Status.VetoCooldown) {
            self.lastAdoptableStateExitedAt = currentTime;
        }

        if (newStatus == Status.VetoSignalling && oldStatus != Status.VetoSignallingDeactivation) {
            self.signalingActivatedAt = currentTime;
        }
        if (newStatus == Status.RageQuit) {
            IEscrow signallingEscrow = self.signallingEscrow;
            signallingEscrow.startRageQuit();
            self.rageQuitEscrow = signallingEscrow;
            _deployNewSignalingEscrow(self, signallingEscrow.MASTER_COPY());
        }
        // when the governance was set on halt, remove self-limit after the veto signaling state is left
        if (
            self.isProposalsCreationOnHalt
                && (newStatus != Status.VetoSignalling && newStatus != Status.VetoSignallingDeactivation)
        ) {
            self.isProposalsCreationOnHalt = false;
        }
    }

    // ---
    // Helper Methods
    // ---

    function _isFirstThresholdReached(State storage self, IConfiguration config) internal view returns (bool) {
        (uint256 totalSupport,) = self.signallingEscrow.getSignallingState();
        return totalSupport >= config.FIRST_SEAL_THRESHOLD();
    }

    function _isSecondThresholdReached(State storage self, IConfiguration config) internal view returns (bool) {
        (, uint256 rageQuitSupport) = self.signallingEscrow.getSignallingState();
        return rageQuitSupport >= config.SECOND_SEAL_THRESHOLD();
    }

    function _calcVetoSignallingTargetDuration(
        IConfiguration config,
        uint256 totalSupport
    ) private view returns (uint256 duration_) {
        (uint256 firstSealThreshold, uint256 secondSealThreshold, uint256 minDuration, uint256 maxDuration) =
            config.getSignallingThresholdData();

        if (totalSupport < firstSealThreshold) {
            return 0;
        }

        if (totalSupport >= secondSealThreshold) {
            return maxDuration;
        }

        duration_ = minDuration
            + (totalSupport - firstSealThreshold) * (maxDuration - minDuration) / (secondSealThreshold - firstSealThreshold);
    }

    function _deployNewSignalingEscrow(State storage self, address escrowMasterCopy) internal {
        IEscrow clone = IEscrow(Clones.clone(escrowMasterCopy));
        clone.initialize(address(this));
        self.signallingEscrow = clone;
        emit NewSignallingEscrowDeployed(address(clone));
    }
}
