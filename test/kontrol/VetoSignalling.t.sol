pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import {State} from "contracts/libraries/DualGovernanceState.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract VetoSignallingTest is DualGovernanceSetUp {
    /**
     * Test that the Normal state transitions to VetoSignalling if the total
     * veto power in the signalling escrow exceeds the first seal threshold.
     */
    function testTransitionNormalToVetoSignalling() external {
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
        vm.assume(rageQuitSupport > config.FIRST_SEAL_RAGE_QUIT_SUPPORT());
        vm.assume(dualGovernance.currentState() == State.Normal);
        dualGovernance.activateNextState();
        assert(dualGovernance.currentState() == State.VetoSignalling);
    }

    struct StateRecord {
        State state;
        uint256 timestamp;
        uint256 rageQuitSupport;
        uint256 maxRageQuitSupport;
        uint256 activationTime;
        uint256 reactivationTime;
    }

    /**
     * Invariants that should hold while in the Veto Signalling state
     * (including Deactivation sub-state)
     */
    function _vetoSignallingInvariants(Mode mode, StateRecord memory sr) internal view {
        require(
            sr.state != State.Normal && sr.state != State.VetoCooldown && sr.state != State.RageQuit,
            "Invariants only apply to the Veto Signalling states."
        );

        _vetoSignallingTimesInvariant(mode, sr);
        _vetoSignallingRageQuitInvariant(mode, sr);
        _vetoSignallingDeactivationInvariant(mode, sr);
        _vetoSignallingMaxDelayInvariant(mode, sr);
    }

    /**
     * Veto Signalling Invariant: At any given point t up to the present time,
     * the Veto Signalling activation and reactivation times must be before t.
     */
    function _vetoSignallingTimesInvariant(Mode mode, StateRecord memory sr) internal view {
        _establish(mode, sr.timestamp <= block.timestamp);
        _establish(mode, sr.activationTime <= sr.timestamp);
        _establish(mode, sr.reactivationTime <= sr.timestamp);
    }

    /**
     * Veto Signalling Invariant: The rage quit support cannot be greater than
     * the maximum rage quit support since entering the Veto Signalling state,
     * and the maximum rage quit support must be greater than the first seal
     * threshold.
     */
    function _vetoSignallingRageQuitInvariant(Mode mode, StateRecord memory sr) internal view {
        _establish(mode, sr.rageQuitSupport <= sr.maxRageQuitSupport);
        _establish(mode, config.FIRST_SEAL_RAGE_QUIT_SUPPORT() < sr.maxRageQuitSupport);
    }

    function _calculateDynamicTimelock(Configuration _config, uint256 rageQuitSupport) public view returns (uint256) {
        if (rageQuitSupport <= _config.FIRST_SEAL_RAGE_QUIT_SUPPORT()) {
            return 0;
        } else if (rageQuitSupport <= _config.SECOND_SEAL_RAGE_QUIT_SUPPORT()) {
            return _linearInterpolation(_config, rageQuitSupport);
        } else {
            return _config.DYNAMIC_TIMELOCK_MAX_DURATION();
        }
    }

    function _linearInterpolation(Configuration _config, uint256 rageQuitSupport) private view returns (uint256) {
        uint256 L_min = _config.DYNAMIC_TIMELOCK_MIN_DURATION();
        uint256 L_max = _config.DYNAMIC_TIMELOCK_MAX_DURATION();
        return L_min
            + ((rageQuitSupport - _config.FIRST_SEAL_RAGE_QUIT_SUPPORT()) * (L_max - L_min))
                / (_config.SECOND_SEAL_RAGE_QUIT_SUPPORT() - _config.FIRST_SEAL_RAGE_QUIT_SUPPORT());
    }

    /**
     * Veto Signalling Invariant: If at a given time both the dynamic timelock
     * for the current rage quit support AND the minimum active duration since
     * the Deactivation sub-state was last exited have passed, the protocol is
     * in the Deactivation sub-state. Otherwise, it is in the parent state.
     */
    function _vetoSignallingDeactivationInvariant(Mode mode, StateRecord memory sr) internal view {
        uint256 dynamicTimelock = _calculateDynamicTimelock(config, sr.rageQuitSupport);

        // Note: creates three branches in symbolic execution
        if (sr.timestamp <= sr.activationTime + dynamicTimelock) {
            _establish(mode, sr.state == State.VetoSignalling);
        } else if (
            sr.timestamp
                <= Math.max(sr.reactivationTime, sr.activationTime) + config.VETO_SIGNALLING_MIN_ACTIVE_DURATION()
        ) {
            _establish(mode, sr.state == State.VetoSignalling);
        } else {
            _establish(mode, sr.state == State.VetoSignallingDeactivation);
        }
    }

    /**
     * Veto Signalling Invariant: If the maximum deactivation delay has passed,
     * then the protocol must be in the Deactivation sub-state.
     *
     * The maximum deactivation delay is defined as T + D, where
     * - T is the dynamic timelock for the maximum rage quit support obtained
     *   since entering the Veto Signalling state, and
     * - D is the minimum active duration before the Deactivation sub-state can
     *   be re-entered.
     */
    function _vetoSignallingMaxDelayInvariant(Mode mode, StateRecord memory sr) internal view {
        // Note: creates two branches in symbolic execution
        if (_maxDeactivationDelayPassed(sr)) {
            _establish(mode, sr.state == State.VetoSignallingDeactivation);
        }
    }

    function _maxDeactivationDelayPassed(StateRecord memory sr) internal view returns (bool) {
        uint256 maxDeactivationDelay =
            _calculateDynamicTimelock(config, sr.maxRageQuitSupport) + config.VETO_SIGNALLING_MIN_ACTIVE_DURATION();

        return sr.activationTime + maxDeactivationDelay < sr.timestamp;
    }

    function _recordPreviousState(
        uint256 lastInteractionTimestamp,
        uint256 previousRageQuitSupport,
        uint256 maxRageQuitSupport
    ) internal view returns (StateRecord memory sr) {
        sr.state = dualGovernance.currentState();
        sr.timestamp = lastInteractionTimestamp;
        sr.rageQuitSupport = previousRageQuitSupport;
        sr.maxRageQuitSupport = maxRageQuitSupport;
        sr.activationTime = _getVetoSignallingActivationTime(dualGovernance);
        sr.reactivationTime = _getVetoSignallingReactivationTime(dualGovernance);
    }

    function _recordCurrentState(uint256 previousMaxRageQuitSupport) internal view returns (StateRecord memory sr) {
        sr.state = dualGovernance.currentState();
        sr.timestamp = block.timestamp;
        sr.rageQuitSupport = signallingEscrow.getRageQuitSupport();
        sr.maxRageQuitSupport =
            previousMaxRageQuitSupport < sr.rageQuitSupport ? sr.rageQuitSupport : previousMaxRageQuitSupport;
        sr.activationTime = _getVetoSignallingActivationTime(dualGovernance);
        sr.reactivationTime = _getVetoSignallingReactivationTime(dualGovernance);
    }

    /**
     * Together, the three tests below verify the following:
     *
     * 1. After entering the Veto Signalling state, the Deactivation sub-state
     *    will be entered in at most time proportional to the maximum rage quit
     *    support observed since entering the Veto Signalling state.
     *
     * 2. If a new maximum rage quit support is not observed after this time,
     *    the Deactivation sub-state will not exit back to the parent state, and
     *    therefore the Veto Cooldown state will be entered after the maximum
     *    deactivation duration has elapsed.
     *
     * This places a bound on the maximum time that the protocol can be forced
     * to stay in the Veto Signalling state.
     */

    /**
     * Test that the Veto Signalling invariants hold when the Veto Signalling
     * state is first entered.
     */
    function testVetoSignallingInvariantsHoldInitially() external {
        vm.assume(block.timestamp < timeUpperBound);

        vm.assume(dualGovernance.currentState() != State.VetoSignalling);
        vm.assume(dualGovernance.currentState() != State.VetoSignallingDeactivation);

        dualGovernance.activateNextState();

        StateRecord memory sr = _recordCurrentState(0);

        // Consider only the case where we have transitioned to Veto Signalling
        if (sr.state == State.VetoSignalling) {
            _vetoSignallingInvariants(Mode.Assert, sr);
        }
    }

    /**
     * Assuming that the previous state of the protocol is consistent with the
     * Veto Signalling invariants, test that when we call activateNextState()
     * the state remains consistent with the invariants.
     */
    function testVetoSignallingInvariantsArePreserved(
        uint256 lastInteractionTimestamp,
        uint256 previousRageQuitSupport,
        uint256 maxRageQuitSupport
    ) external {
        vm.assume(block.timestamp < timeUpperBound);

        vm.assume(lastInteractionTimestamp < timeUpperBound);
        vm.assume(previousRageQuitSupport < ethUpperBound);
        vm.assume(maxRageQuitSupport < ethUpperBound);

        StateRecord memory previous =
            _recordPreviousState(lastInteractionTimestamp, previousRageQuitSupport, maxRageQuitSupport);

        vm.assume(previous.state != State.Normal);
        vm.assume(previous.state != State.VetoCooldown);
        vm.assume(previous.state != State.RageQuit);

        _vetoSignallingInvariants(Mode.Assume, previous);
        dualGovernance.activateNextState();

        StateRecord memory current = _recordCurrentState(maxRageQuitSupport);

        if (current.state != State.Normal && current.state != State.VetoCooldown && current.state != State.RageQuit) {
            _vetoSignallingInvariants(Mode.Assert, current);
        }
    }

    /**
     * Test that, given the Veto Signalling invariants, then if
     * a) the maximum deactivation delay passes, and
     * b) we don't observe a new maximum rage quit support,
     * then the protocol cannot have exited the Deactivation sub-state.
     */
    function testDeactivationNotCancelled(
        uint256 lastInteractionTimestamp,
        uint256 previousRageQuitSupport,
        uint256 maxRageQuitSupport
    ) external {
        vm.assume(block.timestamp < timeUpperBound);

        StateRecord memory previous =
            _recordPreviousState(lastInteractionTimestamp, previousRageQuitSupport, maxRageQuitSupport);

        vm.assume(previous.maxRageQuitSupport <= config.SECOND_SEAL_RAGE_QUIT_SUPPORT());
        vm.assume(_maxDeactivationDelayPassed(previous));
        vm.assume(signallingEscrow.getRageQuitSupport() <= previous.maxRageQuitSupport);

        vm.assume(previous.state == State.VetoSignalling || previous.state == State.VetoSignallingDeactivation);

        _vetoSignallingInvariants(Mode.Assume, previous);

        assert(previous.state == State.VetoSignallingDeactivation);

        dualGovernance.activateNextState();

        StateRecord memory current = _recordCurrentState(maxRageQuitSupport);

        uint256 deactivationStartTime = _getEnteredAt(dualGovernance);
        uint256 deactivationEndTime = deactivationStartTime + config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION();

        // The protocol is either in the Deactivation sub-state, or, if the
        // maximum deactivation duration has passed, in the Veto Cooldown state
        if (deactivationEndTime < block.timestamp) {
            assert(current.state == State.VetoCooldown);
        } else {
            assert(current.state == State.VetoSignallingDeactivation);
        }
    }
}
