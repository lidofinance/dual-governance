// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";
import {IDualGovernanceConfiguration as IConfiguration} from "../interfaces/IConfiguration.sol";

import {TimeUtils} from "../utils/time.sol";

interface IPausableUntil {
    function isPaused() external view returns (bool);
}

enum State {
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

library DualGovernanceState {
    struct Store {
        State state;
        uint40 enteredAt;
        //
        uint40 vetoSignallingFirstActivation;
        uint40 vetoSignallingLastActivation;
        //
        uint40 lastAdoptableStateExitedAt;
        IEscrow signallingEscrow;
        IEscrow rageQuitEscrow;
        uint8 rageQuitRound;
    }
    // uint40 vetoAccumulationDuration;
    // uint40 vetoDeactivationDuration;

    error NotTie();
    error AlreadyInitialized();
    error ProposalsCreationSuspended();
    error ProposalsAdoptionSuspended();

    event NewSignallingEscrowDeployed(address indexed escrow);
    event DualGovernanceStateChanged(State oldState, State newState);

    function initialize(Store storage self, address escrowMasterCopy) internal {
        if (address(self.signallingEscrow) != address(0)) {
            revert AlreadyInitialized();
        }
        _deployNewSignallingEscrow(self, escrowMasterCopy);
    }

    function activateNextState(Store storage self, IConfiguration config) internal returns (State newState) {
        State oldState = self.state;
        // TODO: Currently doesn't match spec precisely because not only Normal or VetoSignalling states are bounded.
        // But it seems like there are no states that may last shorter than MIN_STATE_DURATION
        if (block.timestamp < self.enteredAt + config.MIN_STATE_DURATION()) {
            newState = oldState;
        } else if (oldState == State.Normal) {
            newState = _fromNormalState(self, config);
        } else if (oldState == State.VetoSignalling) {
            newState = _fromVetoSignallingState(self, config);
        } else if (oldState == State.VetoSignallingDeactivation) {
            newState = _fromVetoSignallingDeactivationState(self, config);
        } else if (oldState == State.VetoCooldown) {
            newState = _fromVetoCooldownState(self, config);
        } else if (oldState == State.RageQuit) {
            newState = _fromRageQuitState(self, config);
        } else {
            assert(false);
        }

        if (oldState != newState) {
            _setState(self, oldState, newState);
            _handleStateTransitionSideEffects(self, config, oldState, newState);
            emit DualGovernanceStateChanged(oldState, newState);
        }
    }

    // TODO: Consider this code as possible option. Delete if not needed
    // function onNewProposal(Store storage self, IConfiguration config) internal {
    //     uint256 accumulationMaxDuration = config.SIGNALLING_MAX_DURATION();
    //     uint256 deactivationMinDuration = config.SIGNALLING_DEACTIVATION_DURATION();

    //     if (self.state == State.Normal || self.state == State.RageQuit) {
    //         self.vetoAccumulationDuration = TimeUtils.timestamp(accumulationMaxDuration);
    //         self.vetoDeactivationDuration = TimeUtils.timestamp(deactivationMinDuration);
    //     } else if (self.state == State.VetoAccumulation) {
    //         // when the proposal submitted during the veto accumulation phase
    //         uint256 enteredAt = self.enteredAt;
    //         uint256 vetoAccumulationDurationPassed = block.timestamp - enteredAt;
    //         // now we have to decrease veto accumulation duration on passed time and increase the
    //         // deactivation duration
    //         uint256 vetoAccumulationDurationNew = self.vetoAccumulationDuration > vetoAccumulationDurationPassed
    //             ? self.vetoAccumulationDuration - vetoAccumulationDurationPassed
    //             : 0;
    //         uint256 vetoDeactivationDurationNew =
    //             deactivationMinDuration + accumulationMaxDuration - vetoAccumulationDurationNew;

    //         self.vetoAccumulationDuration = TimeUtils.timestamp(vetoAccumulationDurationNew);
    //         self.vetoDeactivationDuration = TimeUtils.timestamp(vetoDeactivationDurationNew);
    //         // when the durations were updated, assuming that vet signalling was reactivated
    //         // at this point.
    //         self.enteredAt = TimeUtils.timestamp();
    //     } else {
    //         // in any other cases, proposal can't be submitted
    //         assert(false);
    //     }
    // }

    function setLastProposalCreationTimestamp(Store storage self) internal {
        if (self.state == State.VetoSignalling) {
            self.vetoSignallingLastActivation = TimeUtils.timestamp();
        }
    }

    function checkProposalsCreationAllowed(Store storage self) internal view {
        if (!isProposalsCreationAllowed(self)) {
            revert ProposalsCreationSuspended();
        }
    }

    function checkProposalsAdoptionAllowed(Store storage self) internal view {
        if (!isProposalsAdoptionAllowed(self)) {
            revert ProposalsAdoptionSuspended();
        }
    }

    function checkTiebreak(Store storage self, IConfiguration config) internal view {
        if (!isTiebreak(self, config)) {
            revert NotTie();
        }
    }

    function currentState(Store storage self) internal view returns (State) {
        return self.state;
    }

    function isProposalsCreationAllowed(Store storage self) internal view returns (bool) {
        State state = self.state;
        return state != State.VetoSignallingDeactivation && state != State.VetoCooldown;
    }

    function isProposalsAdoptionAllowed(Store storage self) internal view returns (bool) {
        State state = self.state;
        return state == State.Normal || state == State.VetoCooldown;
    }

    function isTiebreak(Store storage self, IConfiguration config) internal view returns (bool) {
        if (isProposalsAdoptionAllowed(self)) return false;

        // for the governance is locked for long period of time
        if (block.timestamp - self.lastAdoptableStateExitedAt >= config.TIE_BREAK_ACTIVATION_TIMEOUT()) return true;

        if (self.state != State.RageQuit) return false;

        address[] memory sealableWithdrawalBlockers = config.sealableWithdrawalBlockers();
        for (uint256 i = 0; i < sealableWithdrawalBlockers.length; ++i) {
            if (IPausableUntil(sealableWithdrawalBlockers[i]).isPaused()) return true;
        }
        return false;
    }

    function getVetoSignallingState(
        Store storage self,
        IConfiguration config
    ) internal view returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt) {
        isActive = self.state == State.VetoSignalling;
        duration = isActive ? getVetoSignallingDuration(self, config) : 0;
        enteredAt = isActive ? self.enteredAt : 0;
        activatedAt = isActive ? self.vetoSignallingLastActivation : 0;
    }

    function getVetoSignallingDuration(Store storage self, IConfiguration config) internal view returns (uint256) {
        uint256 totalSupport = self.signallingEscrow.getRageQuitSupport();
        return _calcVetoSignallingTargetDuration(config, totalSupport);
    }

    struct VetoSignallingDeactivationState {
        uint256 duration;
        uint256 enteredAt;
    }

    function getVetoSignallingDeactivationState(
        Store storage self,
        IConfiguration config
    ) internal view returns (bool isActive, uint256 duration, uint256 enteredAt) {
        isActive = self.state == State.VetoSignallingDeactivation;
        duration = config.VETO_SIGNALLING_DEACTIVATION_DURATION();
        enteredAt = isActive ? self.enteredAt : 0;
    }

    // ---
    // Store Transitions
    // ---

    function _fromNormalState(Store storage self, IConfiguration config) private view returns (State) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();
        return rageQuitSupport >= config.FIRST_SEAL_RAGE_QUIT_SUPPORT() ? State.VetoSignalling : State.Normal;
    }

    function _fromVetoSignallingState(Store storage self, IConfiguration config) private view returns (State) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (rageQuitSupport < config.FIRST_SEAL_RAGE_QUIT_SUPPORT()) {
            return State.VetoSignallingDeactivation;
        }

        uint256 vetoSignallingTotalDuration = block.timestamp - self.vetoSignallingFirstActivation;

        if (
            vetoSignallingTotalDuration >= config.DYNAMIC_TIMELOCK_MAX_DURATION()
                && _isSecondThresholdReached(self, config)
        ) {
            return State.RageQuit;
        }

        uint256 vetoSignallingCurrentDuration = block.timestamp - self.vetoSignallingLastActivation;
        uint256 targetDuration = _calcVetoSignallingTargetDuration(config, rageQuitSupport);

        // spent in the VetoAccumulation state longer than needed
        if (vetoSignallingCurrentDuration >= targetDuration) {
            return State.VetoSignallingDeactivation;
        }

        return State.VetoSignalling;
    }

    function _fromVetoSignallingDeactivationState(
        Store storage self,
        IConfiguration config
    ) private view returns (State) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();
        uint256 vetoSignallingCurrentDuration = block.timestamp - self.vetoSignallingLastActivation;
        uint256 targetDuration = _calcVetoSignallingTargetDuration(config, rageQuitSupport);

        if (targetDuration > vetoSignallingCurrentDuration) {
            return State.VetoSignalling;
        }

        if (block.timestamp - self.enteredAt <= config.VETO_SIGNALLING_DEACTIVATION_DURATION()) {
            return State.VetoSignallingDeactivation;
        }

        return _isSecondThresholdReached(self, config) ? State.RageQuit : State.VetoCooldown;
    }

    function _fromVetoCooldownState(Store storage self, IConfiguration config) private view returns (State) {
        uint256 duration_ = block.timestamp - self.enteredAt;
        if (duration_ < config.VETO_COOLDOWN_DURATION()) {
            return State.VetoCooldown;
        }
        return _isFirstThresholdReached(self, config) ? State.VetoSignalling : State.Normal;
    }

    function _fromRageQuitState(Store storage self, IConfiguration config) private view returns (State) {
        if (!self.rageQuitEscrow.isRageQuitFinalized()) {
            return State.RageQuit;
        }
        return _isFirstThresholdReached(self, config) ? State.VetoSignalling : State.VetoCooldown;
    }

    function _setState(Store storage self, State oldState, State newState) private {
        assert(oldState != newState);
        assert(self.state == oldState);

        self.state = newState;

        uint40 currentTime = TimeUtils.timestamp();
        self.enteredAt = currentTime;
    }

    function _handleStateTransitionSideEffects(
        Store storage self,
        IConfiguration config,
        State oldState,
        State newState
    ) private {
        uint40 currentTime = TimeUtils.timestamp();
        // track the time when the governance state allowed execution
        if (oldState == State.Normal || oldState == State.VetoCooldown) {
            self.lastAdoptableStateExitedAt = currentTime;
        }
        if (newState == State.Normal && self.rageQuitRound != 0) {
            self.rageQuitRound = 0;
        }
        if (newState == State.VetoSignalling && oldState != State.VetoSignallingDeactivation) {
            self.vetoSignallingFirstActivation = currentTime;
            self.vetoSignallingLastActivation = currentTime;
        }
        if (newState == State.RageQuit) {
            IEscrow signallingEscrow = self.signallingEscrow;
            signallingEscrow.startRageQuit(
                config.RAGE_QUIT_EXTRA_TIMELOCK(), _calcRageQuitWithdrawalsTimelock(config, self.rageQuitRound)
            );
            self.rageQuitEscrow = signallingEscrow;
            _deployNewSignallingEscrow(self, signallingEscrow.MASTER_COPY());
            self.rageQuitRound += 1;
        }
    }

    // ---
    // Helper Methods
    // ---

    function _isFirstThresholdReached(Store storage self, IConfiguration config) private view returns (bool) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();
        return rageQuitSupport >= config.FIRST_SEAL_RAGE_QUIT_SUPPORT();
    }

    function _isSecondThresholdReached(Store storage self, IConfiguration config) private view returns (bool) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();
        return rageQuitSupport >= config.SECOND_SEAL_RAGE_QUIT_SUPPORT();
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

    function _deployNewSignallingEscrow(Store storage self, address escrowMasterCopy) private {
        IEscrow clone = IEscrow(Clones.clone(escrowMasterCopy));
        clone.initialize(address(this));
        self.signallingEscrow = clone;
        emit NewSignallingEscrowDeployed(address(clone));
    }

    function _calcRageQuitWithdrawalsTimelock(
        IConfiguration config,
        uint256 rageQuitRound
    ) private view returns (uint256) {
        // TODO: implement proper function
        return config.RAGE_QUIT_ETH_CLAIM_MIN_TIMELOCK() * config.RAGE_QUIT_EXTENSION_DELAY() * rageQuitRound;
    }
}
