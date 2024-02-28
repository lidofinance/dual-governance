// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";

import {timestamp, duration} from "../utils/time.sol";

interface IPausableUntil {
    function isPaused() external view returns (bool);
}

struct DualGovernanceConfig {
    uint256 firstSealThreshold;
    uint256 secondSealThreshold;
    uint256 signalingMaxDuration;
    uint256 signalingMinDuration;
    uint256 signalingCooldownDuration;
    uint256 signalingDeactivationDuration;
    uint256 tiebreakActivationTimeout;
}

enum Status {
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

library DualGovernanceState {
    using SafeCast for uint256;

    struct DualGovernanceConfigPacked {
        uint128 firstSealThreshold;
        uint128 secondSealThreshold;
        uint32 signalingMaxDuration;
        uint32 signalingMinDuration;
        uint32 signalingCooldownDuration;
        uint32 signalingDeactivationDuration;
        uint32 tiebreakActivationTimeout;
    }

    struct State {
        Status status;
        uint40 enteredAt;
        uint40 signalingActivatedAt;
        uint40 lastAdoptableStateExitedAt;
        DualGovernanceConfigPacked config;
        IEscrow signallingEscrow;
        IEscrow rageQuitEscrow;
        bool isProposalsCreationOnHalt;
        address[] sealableWithdrawalBlockers;
    }

    function setEscrow(State storage self, address escrow) internal {
        self.signallingEscrow = IEscrow(escrow);
    }

    function setConfig(State storage self, DualGovernanceConfig memory config) internal {
        self.config = DualGovernanceConfigPacked({
            firstSealThreshold: config.firstSealThreshold.toUint128(),
            secondSealThreshold: config.secondSealThreshold.toUint128(),
            signalingMaxDuration: duration(config.signalingMaxDuration),
            signalingMinDuration: duration(config.signalingMinDuration),
            signalingCooldownDuration: duration(config.signalingCooldownDuration),
            signalingDeactivationDuration: duration(config.signalingDeactivationDuration),
            tiebreakActivationTimeout: duration(config.tiebreakActivationTimeout)
        });
    }

    function setSealableWithdrawalBlockers(State storage self, address[] memory sealableWithdrawalBlockers) internal {
        self.sealableWithdrawalBlockers = sealableWithdrawalBlockers;
    }

    function activateNextState(State storage self) internal {
        Status status = self.status;
        if (status == Status.Normal) {
            _fromNormalState(self);
        } else if (status == Status.VetoSignalling) {
            _fromVetoSignalingState(self);
        } else if (status == Status.VetoSignallingDeactivation) {
            _fromVetoSignalingDeactivationState(self);
        } else if (status == Status.VetoCooldown) {
            _fromVetoCooldownState(self);
        } else if (status == Status.RageQuit) {
            _fromRageQuitState(self);
        } else {
            assert(false);
        }
    }

    function haltProposalsCreation(State storage self) internal {
        if (self.status == Status.VetoSignalling || self.status == Status.VetoSignallingDeactivation) {
            self.isProposalsCreationOnHalt = true;
        }
    }

    function getConfig(State storage self) internal view returns (DualGovernanceConfig memory config) {
        DualGovernanceConfigPacked memory packed = self.config;
        config.firstSealThreshold = packed.firstSealThreshold;
        config.secondSealThreshold = packed.secondSealThreshold;
        config.signalingCooldownDuration = packed.signalingCooldownDuration;
        config.signalingDeactivationDuration = packed.signalingDeactivationDuration;
        config.signalingMaxDuration = packed.signalingMaxDuration;
        config.signalingMinDuration = packed.signalingMinDuration;
        config.tiebreakActivationTimeout = packed.tiebreakActivationTimeout;
    }

    function isProposalsCreationAllowed(State storage self) internal view returns (bool) {
        if (self.isProposalsCreationOnHalt) return false;
        Status status = self.status;
        return status != Status.VetoSignallingDeactivation && status != Status.VetoCooldown;
    }

    function isProposalsAdoptionAllowed(State storage self) internal view returns (bool) {
        if (self.isProposalsCreationOnHalt) return false;
        Status status = self.status;
        return status == Status.Normal || status == Status.VetoCooldown;
    }

    function isDeadLockedOrFrozen(State storage self) internal view returns (bool) {
        if (isProposalsAdoptionAllowed(self)) return false;

        // for the governance is locked for long period of time
        if (block.timestamp - self.lastAdoptableStateExitedAt >= self.config.tiebreakActivationTimeout) return true;

        if (self.status != Status.RageQuit) return false;

        for (uint256 i = 0; i < self.sealableWithdrawalBlockers.length; ++i) {
            if (IPausableUntil(self.sealableWithdrawalBlockers[i]).isPaused()) return true;
        }
        return false;
    }

    // ---
    // State Transitions
    // ---

    function _fromNormalState(State storage self) private {
        (uint256 totalSupport,) = self.signallingEscrow.getSignallingState();
        if (totalSupport >= self.config.firstSealThreshold) {
            _set(self, Status.VetoSignalling);
        }
    }

    function _fromVetoSignalingState(State storage self) private {
        (uint256 totalSupport,) = self.signallingEscrow.getSignallingState();

        if (totalSupport < self.config.firstSealThreshold) {
            return _set(self, Status.VetoSignallingDeactivation);
        }

        uint256 currentDuration = block.timestamp - self.signalingActivatedAt;
        uint256 targetDuration = _calcVetoSignallingTargetDuration(self, totalSupport);

        if (currentDuration < targetDuration) {
            return;
        }

        _set(self, _isSecondThresholdReached(self) ? Status.RageQuit : Status.VetoSignallingDeactivation);
    }

    function _fromVetoSignalingDeactivationState(State storage self) private {
        uint256 currentDeactivationDuration = block.timestamp - self.enteredAt;
        if (currentDeactivationDuration >= self.config.signalingDeactivationDuration) {
            return _set(self, Status.VetoCooldown);
        }

        (uint256 totalSupport, uint256 rageQuitSupport) = self.signallingEscrow.getSignallingState();
        uint256 currentSignallingDuration = block.timestamp - self.signalingActivatedAt;
        uint256 targetSignallingDuration = _calcVetoSignallingTargetDuration(self, totalSupport);

        if (currentSignallingDuration >= targetSignallingDuration) {
            if (rageQuitSupport >= self.config.secondSealThreshold) {
                _set(self, Status.RageQuit);
            }
        } else if (totalSupport >= self.config.firstSealThreshold) {
            _set(self, Status.VetoSignalling);
        }
    }

    function _fromVetoCooldownState(State storage self) private {
        uint256 duration_ = block.timestamp - self.enteredAt;
        if (duration_ < self.config.signalingCooldownDuration) {
            return;
        }
        _set(self, _isFirstThresholdReached(self) ? Status.VetoSignalling : Status.Normal);
    }

    function _fromRageQuitState(State storage self) private {
        if (!self.rageQuitEscrow.isRageQuitFinalized()) {
            return;
        }
        _set(self, _isFirstThresholdReached(self) ? Status.VetoSignalling : Status.Normal);
    }

    function _set(State storage self, Status newStatus) private {
        uint40 currentTime = timestamp();

        Status oldStatus = self.status;

        assert(oldStatus != newStatus);
        self.status = newStatus;
        self.enteredAt = currentTime;

        // track the time when the governance state allowed execution
        if (oldStatus == Status.Normal || oldStatus == Status.VetoCooldown) {
            self.lastAdoptableStateExitedAt = currentTime;
        }

        if (newStatus == Status.VetoSignalling && oldStatus != Status.VetoSignallingDeactivation) {
            self.signalingActivatedAt = currentTime;
        }
        if (newStatus == Status.RageQuit) {
            self.rageQuitEscrow = self.signallingEscrow;
            self.signallingEscrow = self.signallingEscrow.startRageQuit();
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

    function _isFirstThresholdReached(State storage self) internal view returns (bool) {
        (uint256 totalSupport,) = self.signallingEscrow.getSignallingState();
        return totalSupport >= self.config.firstSealThreshold;
    }

    function _isSecondThresholdReached(State storage self) internal view returns (bool) {
        (, uint256 rageQuitSupport) = self.signallingEscrow.getSignallingState();
        return rageQuitSupport >= self.config.secondSealThreshold;
    }

    function _calcVetoSignallingTargetDuration(
        State storage self,
        uint256 totalSupport
    ) private view returns (uint256 duration_) {
        DualGovernanceConfigPacked memory config = self.config;
        uint256 firstSealThreshold = config.firstSealThreshold;
        uint256 secondSealThreshold = config.secondSealThreshold;
        uint256 minDuration = config.signalingMinDuration;
        uint256 maxDuration = config.signalingMaxDuration;

        if (totalSupport < firstSealThreshold) {
            return 0;
        }

        if (totalSupport >= secondSealThreshold) {
            return maxDuration;
        }

        duration_ = minDuration
            + (totalSupport - firstSealThreshold) * (maxDuration - minDuration) / (secondSealThreshold - firstSealThreshold);
    }
}
