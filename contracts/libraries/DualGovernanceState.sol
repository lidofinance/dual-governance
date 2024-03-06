// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";
import {IConfiguration} from "../interfaces/IConfiguration.sol";

import {timestamp} from "../utils/time.sol";

interface IPausableUntil {
    function isPaused() external view returns (bool);
}

interface ITimelock {
    function cancelAllCallback() external;
}

enum Status {
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

library DualGovernanceState {
    struct State {
        Status status;
        uint40 enteredAt;
        uint40 signallingActivatedAt;
        uint40 lastAdoptableStateExitedAt;
        IEscrow signallingEscrow;
        IEscrow rageQuitEscrow;
        uint40 lastProposalCreatedAt;
        bool isProposedOnVetoSignalling;
        bool isCallsRevocationScheduled;
    }

    error AlreadyInitialized();

    event NewSignallingEscrowDeployed(address indexed escrow);

    function initialize(State storage self, address escrowMasterCopy) internal {
        if (address(self.signallingEscrow) != address(0)) {
            revert AlreadyInitialized();
        }
        _deployNewSignallingEscrow(self, escrowMasterCopy);
    }

    function activateNextState(
        State storage self,
        IConfiguration config,
        ITimelock timelock
    ) internal returns (Status newStatus) {
        Status oldStatus = self.status;
        if (oldStatus == Status.Normal) {
            newStatus = _fromNormalState(self, config);
        } else if (oldStatus == Status.VetoSignalling) {
            newStatus = _fromVetoSignallingState(self, config);
        } else if (oldStatus == Status.VetoSignallingDeactivation) {
            newStatus = _fromVetoSignallingDeactivationState(self, config);
        } else if (oldStatus == Status.VetoCooldown) {
            newStatus = _fromVetoCooldownState(self, config);
        } else if (oldStatus == Status.RageQuit) {
            newStatus = _fromRageQuitState(self, config);
        } else {
            assert(false);
        }

        if (oldStatus != newStatus) {
            _setStatus(self, oldStatus, newStatus);
            _handleStatusTransitionSideEffects(self, timelock, oldStatus, newStatus);
        }
    }

    function setLastProposalCreationTimestamp(State storage self) internal {
        self.lastProposalCreatedAt = timestamp();
        self.isProposedOnVetoSignalling = self.status == Status.VetoSignalling;
    }

    function scheduleFutureCallsRevocation(State storage self) internal {
        if (self.status == Status.VetoSignalling || self.status == Status.VetoSignallingDeactivation) {
            self.isCallsRevocationScheduled = true;
        }
    }

    function currentState(State storage self) internal view returns (Status) {
        return self.status;
    }

    function isProposalsCreationAllowed(State storage self) internal view returns (bool) {
        Status status = self.status;
        return status != Status.VetoSignallingDeactivation && status != Status.VetoCooldown;
    }

    function isProposalsAdoptionAllowed(State storage self) internal view returns (bool) {
        Status status = self.status;
        return status == Status.Normal || status == Status.VetoCooldown;
    }

    function isTiebreak(State storage self, IConfiguration config) internal view returns (bool) {
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

    function _fromNormalState(State storage self, IConfiguration config) private view returns (Status) {
        (uint256 totalSupport,) = self.signallingEscrow.getSignallingState();
        return totalSupport >= config.FIRST_SEAL_THRESHOLD() ? Status.VetoSignalling : Status.Normal;
    }

    function _fromVetoSignallingState(State storage self, IConfiguration config) private view returns (Status) {
        (uint256 totalSupport,) = self.signallingEscrow.getSignallingState();

        if (totalSupport < config.FIRST_SEAL_THRESHOLD()) {
            return Status.VetoSignallingDeactivation;
        }

        uint256 currentDuration = block.timestamp - self.signallingActivatedAt;
        uint256 targetDuration = _calcVetoSignallingTargetDuration(config, totalSupport);

        if (currentDuration < targetDuration) {
            return Status.VetoSignalling;
        }

        return _isSecondThresholdReached(self, config) ? Status.RageQuit : Status.VetoSignallingDeactivation;
    }

    function _fromVetoSignallingDeactivationState(
        State storage self,
        IConfiguration config
    ) private view returns (Status) {
        if (_isVetoSignallingDeactivationPhasePassed(self, config)) return Status.VetoCooldown;

        (uint256 totalSupport, uint256 rageQuitSupport) = self.signallingEscrow.getSignallingState();
        uint256 currentSignallingDuration = block.timestamp - self.signallingActivatedAt;
        uint256 targetSignallingDuration = _calcVetoSignallingTargetDuration(config, totalSupport);

        if (currentSignallingDuration >= targetSignallingDuration) {
            if (rageQuitSupport >= config.SECOND_SEAL_THRESHOLD()) {
                return Status.RageQuit;
            }
        } else if (totalSupport >= config.FIRST_SEAL_THRESHOLD()) {
            return Status.VetoSignalling;
        }
        return Status.VetoSignallingDeactivation;
    }

    function _fromVetoCooldownState(State storage self, IConfiguration config) private view returns (Status) {
        uint256 duration_ = block.timestamp - self.enteredAt;
        if (duration_ < config.SIGNALLING_COOLDOWN_DURATION()) {
            return Status.VetoCooldown;
        }
        return _isFirstThresholdReached(self, config) ? Status.VetoSignalling : Status.Normal;
    }

    function _fromRageQuitState(State storage self, IConfiguration config) private view returns (Status) {
        if (!self.rageQuitEscrow.isRageQuitFinalized()) {
            return Status.RageQuit;
        }
        return _isFirstThresholdReached(self, config) ? Status.VetoSignalling : Status.Normal;
    }

    function _setStatus(State storage self, Status oldStatus, Status newStatus) private {
        assert(oldStatus != newStatus);
        assert(self.status == oldStatus);

        self.status = newStatus;

        uint40 currentTime = timestamp();
        self.enteredAt = currentTime;
    }

    function _handleStatusTransitionSideEffects(
        State storage self,
        ITimelock timelock,
        Status oldStatus,
        Status newStatus
    ) private {
        uint40 currentTime = timestamp();
        // track the time when the governance state allowed execution
        if (oldStatus == Status.Normal || oldStatus == Status.VetoCooldown) {
            self.lastAdoptableStateExitedAt = currentTime;
        }

        if (newStatus == Status.VetoSignalling && oldStatus != Status.VetoSignallingDeactivation) {
            self.signallingActivatedAt = currentTime;
        }
        if (newStatus == Status.RageQuit) {
            IEscrow signallingEscrow = self.signallingEscrow;
            signallingEscrow.startRageQuit();
            self.rageQuitEscrow = signallingEscrow;
            _deployNewSignallingEscrow(self, signallingEscrow.MASTER_COPY());
        }
        // when the governance was set on halt, remove self-limit after the veto signalling state is left
        if (self.isCallsRevocationScheduled) {
            if (newStatus != Status.VetoSignalling && newStatus != Status.VetoSignallingDeactivation) {
                self.isCallsRevocationScheduled = false;
                timelock.cancelAllCallback();
            }
        }
    }

    // ---
    // Helper Methods
    // ---

    function _isFirstThresholdReached(State storage self, IConfiguration config) private view returns (bool) {
        (uint256 totalSupport,) = self.signallingEscrow.getSignallingState();
        return totalSupport >= config.FIRST_SEAL_THRESHOLD();
    }

    function _isSecondThresholdReached(State storage self, IConfiguration config) private view returns (bool) {
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

    function _isVetoSignallingDeactivationPhasePassed(
        State storage self,
        IConfiguration config
    ) private view returns (bool) {
        uint256 currentDeactivationDuration = block.timestamp - self.enteredAt;

        if (currentDeactivationDuration < config.SIGNALLING_DEACTIVATION_DURATION()) return false;

        uint256 timePassedFromLastProposalCreation = block.timestamp - self.lastProposalCreatedAt;

        return self.isProposedOnVetoSignalling
            ? timePassedFromLastProposalCreation >= config.SIGNALLING_MIN_PROPOSAL_REVIEW_DURATION()
            : true;
    }

    function _deployNewSignallingEscrow(State storage self, address escrowMasterCopy) private {
        IEscrow clone = IEscrow(Clones.clone(escrowMasterCopy));
        clone.initialize(address(this));
        self.signallingEscrow = clone;
        emit NewSignallingEscrowDeployed(address(clone));
    }
}
