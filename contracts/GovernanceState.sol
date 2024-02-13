// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {Configuration} from "./Configuration.sol";
import {Escrow} from "./Escrow.sol";

import "forge-std/console.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
}

contract GovernanceState {
    error Unauthorized();

    event StateTransition(uint256 indexed fromState, uint256 indexed toState);
    event NewSignallingEscrowDeployed(address indexed escrow, uint256 indexed index);

    enum State {
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
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

    uint16 internal constant MAX_BASIS_POINTS = 10_000;

    constructor(address config, address governance, address escrowImpl) {
        CONFIG = Configuration(config);
        GOVERNANCE = governance;
        ESCROW_IMPL = escrowImpl;
        _deployNewSignallingEscrow();
        _stateEnteredAt = _getTime();
    }

    function currentState() external view returns (State) {
        return _state;
    }

    function signallingEscrow() external view returns (address) {
        return address(_signallingEscrow);
    }

    function rageQuitEscrow() external view returns (address) {
        return address(_rageQuitEscrow);
    }

    function killAllPendingProposals() external {
        if (msg.sender != GOVERNANCE) {
            revert Unauthorized();
        }
        _proposalsKilledUntil = _getTime();
    }

    function isExecutionEnabled() external view returns (bool) {
        return _isExecutionEnabled();
    }

    function isProposalExecutable(uint256 submittedAt, uint256 decidedAt) external view returns (bool) {
        return _isExecutionEnabled() && submittedAt > _proposalsKilledUntil
            && _getTime() >= decidedAt + CONFIG.minProposalExecutionTimelock();
    }

    function isProposalSubmissionAllowed() public view returns (bool) {
        State state = _state;
        return state != State.VetoSignallingDeactivation && state != State.VetoCooldown;
    }

    function _isExecutionEnabled() internal view returns (bool) {
        State state = _state;
        return state == State.Normal || state == State.VetoCooldown;
    }

    function activateNextState() public returns (State) {
        State state = _state;
        if (state == State.Normal) {
            _activateNextStateFromNormal();
        } else if (state == State.VetoSignalling) {
            _activateNextStateFromVetoSignalling();
        } else if (state == State.VetoSignallingDeactivation) {
            _activateNextStateFromVetoSignallingDeactivation();
        } else if (state == State.VetoCooldown) {
            _activateNextStateFromVetoCooldown();
        } else if (state == State.RageQuit) {
            _activateNextStateFromRageQuit();
        } else {
            assert(false);
        }
        return _state;
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
        Escrow escrow = Escrow(payable(Clones.cloneDeterministic(ESCROW_IMPL, bytes32(escrowIndex))));
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
        (uint256 totalSupport,) = _signallingEscrow.getSignallingState();
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
            _activateRageQuit();
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
                _activateRageQuit();
            }
        } else if (totalSupport >= CONFIG.firstSealThreshold()) {
            _exitVetoSignallingDeactivationSubState();
        }
    }

    function _calcVetoSignallingTargetDuration(uint256 totalSupport) internal view returns (uint256 duration) {
        (uint256 firstSealThreshold, uint256 secondSealThreshold, uint256 minDuration, uint256 maxDuration) =
            CONFIG.getSignallingThresholdData();

        if (totalSupport < firstSealThreshold) {
            return 0;
        }

        if (totalSupport >= secondSealThreshold) {
            return maxDuration;
        }

        duration = minDuration
            + (totalSupport - firstSealThreshold) * (maxDuration - minDuration) / (secondSealThreshold - firstSealThreshold);
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
        uint256 stateDuration = _getTime() - _stateEnteredAt;
        if (stateDuration < CONFIG.signallingCooldownDuration()) {
            return;
        }
        if (_isFirstThresholdReached()) {
            _transitionVetoCooldownToVetoSignalling();
        } else {
            _transitionVetoCooldownToNormal();
        }
    }

    //
    // State: RageQuit
    //
    function _activateRageQuit() internal {
        _setState(State.RageQuit);
        _rageQuitEscrow = _signallingEscrow;
        _rageQuitEscrow.startRageQuit();
        _deployNewSignallingEscrow();
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
    function _getTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
