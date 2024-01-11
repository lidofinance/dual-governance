// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {Configuration} from "./Configuration.sol";
import {Escrow} from "./Escrow.sol";


contract GovernanceState {
    error Unauthorized();

    event StateTransition(uint256 indexed fromState, uint256 indexed toState);
    event NewSignallingEscrowDeployed(address indexed escrow, uint256 indexed index);

    enum State {
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
        RageQuitAccumulation,
        RageQuit
    }

    Configuration internal immutable CONFIG;
    address internal immutable GOVERNANCE;
    address internal immutable ESCROW_IMPL;

    uint256 internal _escrowIndex;
    Escrow internal _signallingEscrow;
    Escrow internal _rageQuitEscrow;

    State internal _state;
    uint256 internal _stateEnteredAt;
    uint256 internal _signallingActivatedAt;

    uint256 internal _proposalsKilledUntil;

    constructor(address config, address governance, address escrowImpl) {
        CONFIG = Configuration(config);
        GOVERNANCE = governance;
        ESCROW_IMPL = escrowImpl;
        _deployNewSignallingEscrow();
        _stateEnteredAt = _getTime();
    }

    function killAllPendingProposals() external {
        if (msg.sender != GOVERNANCE) {
            revert Unauthorized();
        }
        _proposalsKilledUntil = _getTime();
    }

    function isProposalExecutable(uint256 submittedAt, uint256 decidedAt) external view returns (bool) {
        return _isExecutionEnabled()
            && submittedAt > _proposalsKilledUntil
            && _getTime() > decidedAt + CONFIG.minProposalExecutionTimelock();
    }

    function isProposalSubmissionAllowed() public view returns (bool) {
        State state = _state;
        return state != State.VetoSignallingDeactivation && state != State.VetoCooldown;
    }

    function _isExecutionEnabled() internal view returns (bool) {
        State state = _state;
        return state == State.Normal || state == State.VetoCooldown;
    }

    function activateNextState() public {
        State state = _state;
        if (state == State.Normal) {
            _activateNextStateFromNormal();
        } else if (state == State.VetoSignalling) {
            _activateNextStateFromVetoSignalling();
        } else if (state == State.VetoSignallingDeactivation) {
            _activateNextStateFromVetoSignallingDeactivation();
        } else if (state == State.VetoCooldown) {
            _activateNextStateFromVetoCooldown();
        } else if (state == State.RageQuitAccumulation) {
            _activateNextStateFromRageQuitAccumulation();
        } else if (state == State.RageQuit) {
            _activateNextStateFromRageQuit();
        } else {
            assert(false);
        }
    }

    function _setState(State newState) internal {
        State state = _state;
        assert(newState != state);
        _state = newState;
        _stateEnteredAt = _getTime();
        emit StateTransition(uint256(state), uint256(newState));
    }

    function _deployNewSignallingEscrow() internal {
        uint256 escrowIndex = _escrowIndex++;
        Escrow escrow = Escrow(Clones.cloneDeterministic(ESCROW_IMPL, bytes32(escrowIndex)));
        escrow.initialize(address(this));
        _signallingEscrow = escrow;
        emit NewSignallingEscrowDeployed(address(escrow), escrowIndex);
    }

    //
    // State: Normal
    //

    function _transitionVetoCooldownToNormal() internal {
        _activateNormal();
    }

    function _transitionRageQuitToNormal() internal {
        _activateNormal();
    }

    function _activateNormal() internal {
        _setState(State.Normal);
    }

    function _activateNextStateFromNormal() internal {
        if (_isFirstThresholdReached()) {
            _transitionNormalToVetoSignalling();
        }
    }

    function _isFirstThresholdReached() internal view returns (bool) {
        (uint256 totalSupport, ) = _signallingEscrow.getSignallingState();
        return totalSupport >= CONFIG.firstSealThreshold();
    }

    //
    // State: VetoSignalling
    //

    function _transitionNormalToVetoSignalling() internal {
        _activateVetoSignalling();
    }

    function _transitionVetoCooldownToVetoSignalling() internal {
        _activateVetoSignalling();
    }

    function _transitionRageQuitToVetoSignalling() internal {
        _activateVetoSignalling();
    }

    function _activateVetoSignalling() internal {
        _setState(State.VetoSignalling);
        _signallingActivatedAt = _getTime();
    }

    function _activateNextStateFromVetoSignalling() internal {
        (uint256 totalSupport, uint256 rageQuitSupport) = _signallingEscrow.getSignallingState();
        if (totalSupport < CONFIG.firstSealThreshold()) {
            _enterVetoSignallingDeactivationSubState();
            return;
        }

        uint256 currentDuration = _getTime() - _signallingActivatedAt;
        uint256 targetDuration = _calcVetoSignallingTargetDuration(totalSupport);

        if (currentDuration < targetDuration) {
            return;
        }

        if (rageQuitSupport >= CONFIG.secondSealThreshold()) {
            _transitionVetoSignallingToRageQuitAccumulation();
        } else {
            _enterVetoSignallingDeactivationSubState();
        }
    }

    function _activateNextStateFromVetoSignallingDeactivation() internal {
        uint256 timestamp = _getTime();

        uint256 currentDeactivationDuration = timestamp - _stateEnteredAt;
        if (currentDeactivationDuration >= CONFIG.signallingDeactivationDuration()) {
            _transitionVetoSignallingToVetoCooldown();
            return;
        }

        (uint256 totalSupport, uint256 rageQuitSupport) = _signallingEscrow.getSignallingState();
        uint256 currentSignallingDuration = timestamp - _signallingActivatedAt;
        uint256 targetSignallingDuration = _calcVetoSignallingTargetDuration(totalSupport);

        if (currentSignallingDuration >= targetSignallingDuration) {
            if (rageQuitSupport >= CONFIG.secondSealThreshold()) {
                _transitionVetoSignallingToRageQuitAccumulation();
            }
        } else if (totalSupport >= CONFIG.firstSealThreshold()) {
            _exitVetoSignallingDeactivationSubState();
        }
    }

    function _calcVetoSignallingTargetDuration(uint256 totalSupport) internal view returns (uint256) {
        // TODO
        return 0;
    }

    function _enterVetoSignallingDeactivationSubState() internal {
        _setState(State.VetoSignallingDeactivation);
    }

    function _exitVetoSignallingDeactivationSubState() internal {
        _setState(State.VetoSignalling);
    }

    //
    // State: VetoCooldown
    //

    function _transitionVetoSignallingToVetoCooldown() internal {
        _setState(State.VetoCooldown);
    }

    function _activateNextStateFromVetoCooldown() internal {
        if (_isFirstThresholdReached()) {
            _transitionVetoCooldownToVetoSignalling();
        } else {
            _transitionVetoCooldownToNormal();
        }
    }

    //
    // State: RageQuitAccumulation
    //

    function _transitionVetoSignallingToRageQuitAccumulation() internal {
        _setState(State.RageQuitAccumulation);
        _signallingEscrow.startRageQuitAccumulation();
        _rageQuitEscrow = _signallingEscrow;
        _deployNewSignallingEscrow();
    }

    function _activateNextStateFromRageQuitAccumulation() internal {
        uint256 accumulationDuration = _getTime() - _stateEnteredAt;
        if (accumulationDuration >= CONFIG.rageQuitAccumulationDuration()) {
            _transitionRageQuitAccumulationToRageQuit();
        }
    }

    //
    // State: RageQuit
    //

    function _transitionRageQuitAccumulationToRageQuit() internal {
        _setState(State.RageQuit);
        _rageQuitEscrow.startRageQuit();
    }

    function _activateNextStateFromRageQuit() internal {
        if (!_rageQuitEscrow.isRageQuitFinalized()) {
            return;
        }
        if (_isFirstThresholdReached()) {
            _transitionRageQuitToVetoSignalling();
        } else {
            _transitionRageQuitToNormal();
        }
    }

    //
    // Utils
    //

    function _getTime() internal virtual view returns (uint256) {
        return block.timestamp;
    }
}
