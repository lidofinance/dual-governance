pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import {State} from "contracts/libraries/DualGovernanceState.sol";
import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract VetoSignallingTest is DualGovernanceSetUp {
    /**
     * Test that the Normal state transitions to VetoSignalling if the total
     * veto power in the signalling escrow exceeds the first seal threshold.
     */
    function testTransitionNormalToVetoSignalling() external {
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
        vm.assume(rageQuitSupport >= config.FIRST_SEAL_RAGE_QUIT_SUPPORT());
        vm.assume(dualGovernance.getCurrentState() == State.Normal);
        dualGovernance.activateNextState();
        assert(dualGovernance.getCurrentState() == State.VetoSignalling);
    }

    struct StateRecord {
        State state;
        Timestamp timestamp;
        uint256 rageQuitSupport;
        uint256 maxRageQuitSupport;
        Timestamp activationTime;
        Timestamp reactivationTime;
    }

    /**
     * Invariants that should hold while in the Veto Signalling state
     * (including Deactivation sub-state)
     */
    function _vetoSignallingInvariants(Mode mode, StateRecord memory sr) internal view returns (bool) {
        require(
            sr.state != State.Normal && sr.state != State.VetoCooldown && sr.state != State.RageQuit,
            "Invariants only apply to the Veto Signalling states."
        );

        return (
            _vetoSignallingTimesInvariant(mode, sr) && _vetoSignallingRageQuitInvariant(mode, sr)
                && _vetoSignallingDeactivationInvariant(mode, sr) && _vetoSignallingMaxDelayInvariant(mode, sr)
        );
    }

    /**
     * Veto Signalling Invariant: At any given point t up to the present time,
     * the Veto Signalling activation and reactivation times must be before t.
     */
    function _vetoSignallingTimesInvariant(Mode mode, StateRecord memory sr) internal view returns (bool) {
        return (
            _establish(mode, sr.timestamp <= Timestamps.now()) && _establish(mode, sr.activationTime <= sr.timestamp)
                && _establish(mode, sr.reactivationTime <= sr.timestamp)
                && _establish(mode, sr.reactivationTime <= addTo(config.DYNAMIC_TIMELOCK_MAX_DURATION(), sr.activationTime))
        );
    }

    /**
     * Veto Signalling Invariant: The rage quit support cannot be greater than
     * the maximum rage quit support since entering the Veto Signalling state,
     * and the maximum rage quit support must be greater than the first seal
     * threshold.
     */
    function _vetoSignallingRageQuitInvariant(Mode mode, StateRecord memory sr) internal view returns (bool) {
        return (
            _establish(mode, sr.rageQuitSupport <= sr.maxRageQuitSupport)
                && _establish(mode, config.FIRST_SEAL_RAGE_QUIT_SUPPORT() <= sr.maxRageQuitSupport)
        );
    }

    function _calculateDynamicTimelock(Configuration _config, uint256 rageQuitSupport) public view returns (Duration) {
        if (rageQuitSupport < _config.FIRST_SEAL_RAGE_QUIT_SUPPORT()) {
            return Durations.ZERO;
        } else if (rageQuitSupport < _config.SECOND_SEAL_RAGE_QUIT_SUPPORT()) {
            return _linearInterpolation(_config, rageQuitSupport);
        } else {
            return _config.DYNAMIC_TIMELOCK_MAX_DURATION();
        }
    }

    function _linearInterpolation(Configuration _config, uint256 rageQuitSupport) private view returns (Duration) {
        uint32 L_min = Duration.unwrap(_config.DYNAMIC_TIMELOCK_MIN_DURATION());
        uint32 L_max = Duration.unwrap(_config.DYNAMIC_TIMELOCK_MAX_DURATION());
        uint256 interpolation = L_min
            + ((rageQuitSupport - _config.FIRST_SEAL_RAGE_QUIT_SUPPORT()) * (L_max - L_min))
                / (_config.SECOND_SEAL_RAGE_QUIT_SUPPORT() - _config.FIRST_SEAL_RAGE_QUIT_SUPPORT());
        assert(interpolation <= type(uint32).max);
        return Duration.wrap(uint32(interpolation));
    }

    function _maxTimestamp(Timestamp t1, Timestamp t2) internal pure returns (Timestamp) {
        return Timestamp.wrap(uint40(Math.max(Timestamp.unwrap(t1), Timestamp.unwrap(t2))));
    }

    /**
     * Veto Signalling Invariant: If at a given time both the dynamic timelock
     * for the current rage quit support AND the minimum active duration since
     * the Deactivation sub-state was last exited have passed, the protocol is
     * in the Deactivation sub-state. Otherwise, it is in the parent state.
     */
    function _vetoSignallingDeactivationInvariant(Mode mode, StateRecord memory sr) internal view returns (bool) {
        Duration dynamicTimelock = _calculateDynamicTimelock(config, sr.rageQuitSupport);

        // Note: creates three branches in symbolic execution
        if (sr.timestamp <= addTo(dynamicTimelock, sr.activationTime)) {
            return _establish(mode, sr.state == State.VetoSignalling);
        }
        if (
            sr.timestamp
                <= addTo(
                    config.VETO_SIGNALLING_MIN_ACTIVE_DURATION(), _maxTimestamp(sr.activationTime, sr.reactivationTime)
                )
        ) {
            return _establish(mode, sr.state == State.VetoSignalling);
        }
        return _establish(mode, sr.state == State.VetoSignallingDeactivation);
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
    function _vetoSignallingMaxDelayInvariant(Mode mode, StateRecord memory sr) internal view returns (bool) {
        // Note: creates two branches in symbolic execution
        if (_maxDeactivationDelayPassed(sr)) {
            return _establish(mode, sr.state == State.VetoSignallingDeactivation);
        }
        return true;
    }

    function _maxDeactivationDelayPassed(StateRecord memory sr) internal view returns (bool) {
        Duration maxDeactivationDelay =
            _calculateDynamicTimelock(config, sr.maxRageQuitSupport) + config.VETO_SIGNALLING_MIN_ACTIVE_DURATION();

        return addTo(maxDeactivationDelay, sr.activationTime) < sr.timestamp;
    }

    function _recordPreviousState(
        Timestamp lastInteractionTimestamp,
        uint256 previousRageQuitSupport,
        uint256 maxRageQuitSupport
    ) internal view returns (StateRecord memory sr) {
        sr.state = dualGovernance.getCurrentState();
        sr.timestamp = lastInteractionTimestamp;
        sr.rageQuitSupport = previousRageQuitSupport;
        sr.maxRageQuitSupport = maxRageQuitSupport;
        sr.activationTime = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));
        sr.reactivationTime = Timestamp.wrap(_getVetoSignallingReactivationTime(dualGovernance));
    }

    function _recordCurrentState(uint256 previousMaxRageQuitSupport) internal view returns (StateRecord memory sr) {
        sr.state = dualGovernance.getCurrentState();
        sr.timestamp = Timestamps.now();
        sr.rageQuitSupport = signallingEscrow.getRageQuitSupport();
        sr.maxRageQuitSupport =
            previousMaxRageQuitSupport < sr.rageQuitSupport ? sr.rageQuitSupport : previousMaxRageQuitSupport;
        sr.activationTime = Timestamp.wrap(_getVetoSignallingActivationTime(dualGovernance));
        sr.reactivationTime = Timestamp.wrap(_getVetoSignallingReactivationTime(dualGovernance));
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

        vm.assume(dualGovernance.getCurrentState() != State.VetoSignalling);
        vm.assume(dualGovernance.getCurrentState() != State.VetoSignallingDeactivation);

        dualGovernance.activateNextState();

        // Consider only the case where we have transitioned to Veto Signalling
        if (dualGovernance.getCurrentState() == State.VetoSignalling) {
            StateRecord memory sr = _recordCurrentState(0);
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

        StateRecord memory previous = _recordPreviousState(
            Timestamp.wrap(uint40(lastInteractionTimestamp)), previousRageQuitSupport, maxRageQuitSupport
        );

        vm.assume(previous.state != State.Normal);
        vm.assume(previous.state != State.VetoCooldown);
        vm.assume(previous.state != State.RageQuit);

        // Assume the first two invariants, which are non-branching
        _vetoSignallingTimesInvariant(Mode.Assume, previous);
        _vetoSignallingRageQuitInvariant(Mode.Assume, previous);

        dualGovernance.activateNextState();

        State currentState = dualGovernance.getCurrentState();

        if (currentState != State.Normal && currentState != State.VetoCooldown && currentState != State.RageQuit) {
            bool assumedDeactivationInvariant = false;
            bool assumedMaxDelayInvariant = false;

            StateRecord memory current = _recordCurrentState(maxRageQuitSupport);

            // First two invariants can be established immediately
            _vetoSignallingTimesInvariant(Mode.Assert, current);
            _vetoSignallingRageQuitInvariant(Mode.Assert, current);

            // Try establishing third invariant
            if (!_vetoSignallingDeactivationInvariant(Mode.Try, current)) {
                // Assume third invariant
                assumedDeactivationInvariant = true;
                _vetoSignallingDeactivationInvariant(Mode.Assume, previous);
                // Assume fourth invariant only if initial state is VetoSignalling,
                // because fourth invariant can only cut VetoSignalling initial states
                if (previous.state == State.VetoSignalling) {
                    assumedMaxDelayInvariant = true;
                    _vetoSignallingMaxDelayInvariant(Mode.Assume, previous);
                }
                // Establish third invariant
                _vetoSignallingDeactivationInvariant(Mode.Assert, current);
                if (!_vetoSignallingMaxDelayInvariant(Mode.Try, current)) {
                    // Assume fourth invariant if not already assumed
                    if (!assumedMaxDelayInvariant) {
                        _vetoSignallingMaxDelayInvariant(Mode.Assume, previous);
                    }
                    // If we still fail, it means that we have not assumed the third invariant,
                    // which has to eliminate all of the remaining branches
                    if (!_vetoSignallingMaxDelayInvariant(Mode.Try, current)) {
                        assert(!assumedDeactivationInvariant);
                        _vetoSignallingDeactivationInvariant(Mode.Assume, previous);
                        assert(false);
                    }
                }
            }
            return;
        }
        vm.assume(currentState == State.VetoSignalling || currentState == State.VetoSignallingDeactivation);
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
        vm.assume(lastInteractionTimestamp < timeUpperBound);
        vm.assume(signallingEscrow.getRageQuitSupport() <= maxRageQuitSupport);
        vm.assume(maxRageQuitSupport < config.SECOND_SEAL_RAGE_QUIT_SUPPORT());

        StateRecord memory previous = _recordPreviousState(
            Timestamp.wrap(uint40(lastInteractionTimestamp)), previousRageQuitSupport, maxRageQuitSupport
        );

        Timestamp deactivationStartTime = Timestamp.wrap(_getEnteredAt(dualGovernance));
        Timestamp deactivationEndTime = addTo(config.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION(), deactivationStartTime);

        vm.assume(previous.state != State.Normal);
        vm.assume(previous.state != State.VetoCooldown);
        vm.assume(previous.state != State.RageQuit);

        _vetoSignallingTimesInvariant(Mode.Assume, previous);
        _vetoSignallingRageQuitInvariant(Mode.Assume, previous);
        vm.assume(_maxDeactivationDelayPassed(previous));
        _vetoSignallingMaxDelayInvariant(Mode.Assume, previous);

        assert(previous.state == State.VetoSignallingDeactivation);

        dualGovernance.activateNextState();

        State currentState = dualGovernance.getCurrentState();

        // The protocol is either in the Deactivation sub-state, or, if the
        // maximum deactivation duration has passed, in the Veto Cooldown state
        if (deactivationEndTime < Timestamps.now()) {
            assert(currentState == State.VetoCooldown);
        } else {
            assert(currentState == State.VetoSignallingDeactivation);
        }
    }
}
