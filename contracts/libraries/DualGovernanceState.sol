// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";
import {ISealable} from "../interfaces/ISealable.sol";
import {IDualGovernanceConfiguration as IConfiguration, DualGovernanceConfig} from "../interfaces/IConfiguration.sol";

import {TimeUtils} from "../utils/time.sol";

enum State {
    Normal,
    VetoSignalling,
    VetoSignallingDeactivation,
    VetoCooldown,
    RageQuit
}

library DualGovernanceState {
    // TODO: Optimize storage layout efficiency
    struct Store {
        State state;
        uint40 enteredAt;
        // the time the veto signalling state was entered
        uint40 vetoSignallingActivationTime;
        IEscrow signallingEscrow;
        // the time the Deactivation sub-state was last exited without exiting the parent Veto Signalling state
        uint40 vetoSignallingReactivationTime;
        // the last time a proposal was submitted to the DG subsystem
        uint40 lastAdoptableStateExitedAt;
        IEscrow rageQuitEscrow;
        uint8 rageQuitRound;
    }

    error NotTie();
    error AlreadyInitialized();
    error ProposalsCreationSuspended();
    error ProposalsAdoptionSuspended();
    error ResealIsNotAllowedInNormalState();

    event NewSignallingEscrowDeployed(address indexed escrow);
    event DualGovernanceStateChanged(State oldState, State newState);

    function initialize(Store storage self, address escrowMasterCopy) internal {
        if (address(self.signallingEscrow) != address(0)) {
            revert AlreadyInitialized();
        }
        _deployNewSignallingEscrow(self, escrowMasterCopy);
    }

    function activateNextState(
        Store storage self,
        DualGovernanceConfig memory config
    ) internal returns (State newState) {
        State oldState = self.state;
        if (oldState == State.Normal) {
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
            self.state = newState;
            _handleStateTransitionSideEffects(self, config, oldState, newState);
            emit DualGovernanceStateChanged(oldState, newState);
        }
    }

    // ---
    // View Methods
    // ---

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

    function checkCanScheduleProposal(Store storage self, uint256 proposalSubmittedAt) internal view {
        if (!canScheduleProposal(self, proposalSubmittedAt)) {
            revert ProposalsAdoptionSuspended();
        }
    }

    function checkTiebreak(Store storage self, IConfiguration config) internal view {
        if (!isTiebreak(self, config)) {
            revert NotTie();
        }
    }

    function checkResealState(Store storage self) internal view {
        if (self.state == State.Normal) {
            revert ResealIsNotAllowedInNormalState();
        }
    }

    function currentState(Store storage self) internal view returns (State) {
        return self.state;
    }

    function canScheduleProposal(Store storage self, uint256 proposalSubmissionTime) internal view returns (bool) {
        State state = self.state;
        if (state == State.Normal) return true;
        if (state == State.VetoCooldown) {
            return proposalSubmissionTime <= self.vetoSignallingActivationTime;
        }
        return false;
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
            if (ISealable(sealableWithdrawalBlockers[i]).isPaused()) return true;
        }
        return false;
    }

    function getVetoSignallingState(
        Store storage self,
        DualGovernanceConfig memory config
    ) internal view returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt) {
        isActive = self.state == State.VetoSignalling;
        duration = isActive ? getVetoSignallingDuration(self, config) : 0;
        enteredAt = isActive ? self.enteredAt : 0;
        activatedAt = isActive ? self.vetoSignallingActivationTime : 0;
    }

    function getVetoSignallingDuration(
        Store storage self,
        DualGovernanceConfig memory config
    ) internal view returns (uint256) {
        uint256 totalSupport = self.signallingEscrow.getRageQuitSupport();
        return _calcDynamicTimelockDuration(config, totalSupport);
    }

    struct VetoSignallingDeactivationState {
        uint256 duration;
        uint256 enteredAt;
    }

    function getVetoSignallingDeactivationState(
        Store storage self,
        DualGovernanceConfig memory config
    ) internal view returns (bool isActive, uint256 duration, uint256 enteredAt) {
        isActive = self.state == State.VetoSignallingDeactivation;
        duration = config.vetoSignallingDeactivationMaxDuration;
        enteredAt = isActive ? self.enteredAt : 0;
    }

    // ---
    // State Transitions
    // ---

    function _fromNormalState(Store storage self, DualGovernanceConfig memory config) private view returns (State) {
        return _isFirstSealRageQuitSupportCrossed(config, self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.Normal;
    }

    function _fromVetoSignallingState(
        Store storage self,
        DualGovernanceConfig memory config
    ) private view returns (State) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!_isDynamicTimelockDurationPassed(self, config, rageQuitSupport)) {
            return State.VetoSignalling;
        }

        if (_isSecondSealRageQuitSupportCrossed(config, rageQuitSupport)) {
            return State.RageQuit;
        }

        return _isVetoSignallingReactivationDurationPassed(self, config)
            ? State.VetoSignallingDeactivation
            : State.VetoSignalling;
    }

    function _fromVetoSignallingDeactivationState(
        Store storage self,
        DualGovernanceConfig memory config
    ) private view returns (State) {
        uint256 rageQuitSupport = self.signallingEscrow.getRageQuitSupport();

        if (!_isDynamicTimelockDurationPassed(self, config, rageQuitSupport)) {
            return State.VetoSignalling;
        }

        if (_isSecondSealRageQuitSupportCrossed(config, rageQuitSupport)) {
            return State.RageQuit;
        }

        if (_isVetoSignallingDeactivationMaxDurationPassed(self, config)) {
            return State.VetoCooldown;
        }

        return State.VetoSignallingDeactivation;
    }

    function _fromVetoCooldownState(
        Store storage self,
        DualGovernanceConfig memory config
    ) private view returns (State) {
        if (!_isVetoCooldownDurationPassed(self, config)) {
            return State.VetoCooldown;
        }
        return _isFirstSealRageQuitSupportCrossed(config, self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.Normal;
    }

    function _fromRageQuitState(Store storage self, DualGovernanceConfig memory config) private view returns (State) {
        if (!self.rageQuitEscrow.isRageQuitFinalized()) {
            return State.RageQuit;
        }
        return _isFirstSealRageQuitSupportCrossed(config, self.signallingEscrow.getRageQuitSupport())
            ? State.VetoSignalling
            : State.VetoCooldown;
    }

    // ---
    // Helper Methods
    // ---

    function _handleStateTransitionSideEffects(
        Store storage self,
        DualGovernanceConfig memory config,
        State oldState,
        State newState
    ) private {
        uint40 timestamp = TimeUtils.timestamp();
        self.enteredAt = timestamp;
        // track the time when the governance state allowed execution
        if (oldState == State.Normal || oldState == State.VetoCooldown) {
            self.lastAdoptableStateExitedAt = timestamp;
        }

        if (newState == State.Normal && self.rageQuitRound != 0) {
            self.rageQuitRound = 0;
        }

        if (newState == State.VetoSignalling && oldState != State.VetoSignallingDeactivation) {
            self.vetoSignallingActivationTime = timestamp;
        }

        if (oldState == State.VetoSignallingDeactivation && newState == State.VetoSignalling) {
            self.vetoSignallingReactivationTime = timestamp;
        }

        if (newState == State.RageQuit) {
            IEscrow signallingEscrow = self.signallingEscrow;
            signallingEscrow.startRageQuit(
                config.rageQuitExtensionDelay, _calcRageQuitWithdrawalsTimelock(config, self.rageQuitRound)
            );
            self.rageQuitEscrow = signallingEscrow;
            _deployNewSignallingEscrow(self, signallingEscrow.MASTER_COPY());
            self.rageQuitRound += 1;
        }
    }

    function _isFirstSealRageQuitSupportCrossed(
        DualGovernanceConfig memory config,
        uint256 rageQuitSupport
    ) private pure returns (bool) {
        return rageQuitSupport > config.firstSealRageQuitSupport;
    }

    function _isSecondSealRageQuitSupportCrossed(
        DualGovernanceConfig memory config,
        uint256 rageQuitSupport
    ) private pure returns (bool) {
        return rageQuitSupport > config.secondSealRageQuitSupport;
    }

    function _isDynamicTimelockMaxDurationPassed(
        Store storage self,
        DualGovernanceConfig memory config
    ) private view returns (bool) {
        return block.timestamp - self.vetoSignallingActivationTime > config.dynamicTimelockMaxDuration;
    }

    function _isDynamicTimelockDurationPassed(
        Store storage self,
        DualGovernanceConfig memory config,
        uint256 rageQuitSupport
    ) private view returns (bool) {
        uint256 vetoSignallingDurationPassed = block.timestamp - self.vetoSignallingActivationTime;
        return vetoSignallingDurationPassed > _calcDynamicTimelockDuration(config, rageQuitSupport);
    }

    function _isVetoSignallingReactivationDurationPassed(
        Store storage self,
        DualGovernanceConfig memory config
    ) private view returns (bool) {
        return block.timestamp - self.vetoSignallingReactivationTime > config.vetoSignallingMinActiveDuration;
    }

    function _isVetoSignallingDeactivationMaxDurationPassed(
        Store storage self,
        DualGovernanceConfig memory config
    ) private view returns (bool) {
        return block.timestamp - self.enteredAt > config.vetoSignallingDeactivationMaxDuration;
    }

    function _isVetoCooldownDurationPassed(
        Store storage self,
        DualGovernanceConfig memory config
    ) private view returns (bool) {
        return block.timestamp - self.enteredAt > config.vetoCooldownDuration;
    }

    function _deployNewSignallingEscrow(Store storage self, address escrowMasterCopy) private {
        IEscrow clone = IEscrow(Clones.clone(escrowMasterCopy));
        clone.initialize(address(this));
        self.signallingEscrow = clone;
        emit NewSignallingEscrowDeployed(address(clone));
    }

    function _calcRageQuitWithdrawalsTimelock(
        DualGovernanceConfig memory config,
        uint256 rageQuitRound
    ) private pure returns (uint256) {
        if (rageQuitRound < config.rageQuitEthClaimTimelockGrowthStartSeqNumber) {
            return config.rageQuitEthClaimMinTimelock;
        }
        return config.rageQuitEthClaimMinTimelock
            + (
                config.rageQuitEthClaimTimelockGrowthCoeffs[0] * rageQuitRound * rageQuitRound
                    + config.rageQuitEthClaimTimelockGrowthCoeffs[1] * rageQuitRound
                    + config.rageQuitEthClaimTimelockGrowthCoeffs[2]
            ) / 10 ** 18; // TODO: rewrite in a prettier way
    }

    function _calcDynamicTimelockDuration(
        DualGovernanceConfig memory config,
        uint256 rageQuitSupport
    ) internal pure returns (uint256 duration_) {
        uint256 firstSealRageQuitSupport = config.firstSealRageQuitSupport;
        uint256 secondSealRageQuitSupport = config.secondSealRageQuitSupport;
        uint256 dynamicTimelockMinDuration = config.dynamicTimelockMinDuration;
        uint256 dynamicTimelockMaxDuration = config.dynamicTimelockMaxDuration;

        if (rageQuitSupport < firstSealRageQuitSupport) {
            return 0;
        }

        if (rageQuitSupport >= secondSealRageQuitSupport) {
            return dynamicTimelockMaxDuration;
        }

        duration_ = dynamicTimelockMinDuration
            + (rageQuitSupport - firstSealRageQuitSupport) * (dynamicTimelockMaxDuration - dynamicTimelockMinDuration)
                / (secondSealRageQuitSupport - firstSealRageQuitSupport);
    }
}
