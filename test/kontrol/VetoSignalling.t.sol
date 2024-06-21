pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "test/kontrol/DualGovernanceSetUp.sol";

contract VetoSignallingTest is DualGovernanceSetUp {
    /**
     * Test that the Normal state transitions to VetoSignalling if the total
     * veto power in the signalling escrow exceeds the first seal threshold.
     */
    function testTransitionNormalToVetoSignalling() external {
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
        vm.assume(rageQuitSupport > dualGovernance.FIRST_SEAL_RAGE_QUIT_SUPPORT());
        vm.assume(dualGovernance.currentState() == DualGovernanceModel.State.Normal);
        dualGovernance.activateNextState();
        assert(dualGovernance.currentState() == DualGovernanceModel.State.VetoSignalling);
    }

    struct StateRecord {
        DualGovernanceModel.State state;
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
            sr.state != DualGovernanceModel.State.Normal && sr.state != DualGovernanceModel.State.VetoCooldown
                && sr.state != DualGovernanceModel.State.RageQuit,
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
        _establish(mode, dualGovernance.FIRST_SEAL_RAGE_QUIT_SUPPORT() < sr.maxRageQuitSupport);
    }

    /**
     * Veto Signalling Invariant: If at a given time both the dynamic timelock
     * for the current rage quit support AND the minimum active duration since
     * the Deactivation sub-state was last exited have passed, the protocol is
     * in the Deactivation sub-state. Otherwise, it is in the parent state.
     */
    function _vetoSignallingDeactivationInvariant(Mode mode, StateRecord memory sr) internal view {
        uint256 dynamicTimelock = dualGovernance.calculateDynamicTimelock(sr.rageQuitSupport);

        // Note: creates three branches in symbolic execution
        if (sr.timestamp <= sr.activationTime + dynamicTimelock) {
            _establish(mode, sr.state == DualGovernanceModel.State.VetoSignalling);
        } else if (
            sr.timestamp
                <= Math.max(sr.reactivationTime, sr.activationTime) + dualGovernance.VETO_SIGNALLING_MIN_ACTIVE_DURATION()
        ) {
            _establish(mode, sr.state == DualGovernanceModel.State.VetoSignalling);
        } else {
            _establish(mode, sr.state == DualGovernanceModel.State.VetoSignallingDeactivation);
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
            _establish(mode, sr.state == DualGovernanceModel.State.VetoSignallingDeactivation);
        }
    }

    function _maxDeactivationDelayPassed(StateRecord memory sr) internal view returns (bool) {
        uint256 maxDeactivationDelay = dualGovernance.calculateDynamicTimelock(sr.maxRageQuitSupport)
            + dualGovernance.VETO_SIGNALLING_MIN_ACTIVE_DURATION();

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
        sr.activationTime = dualGovernance.lastStateChangeTime();
        sr.reactivationTime = dualGovernance.lastStateReactivationTime();
    }

    function _recordCurrentState(uint256 previousMaxRageQuitSupport) internal view returns (StateRecord memory sr) {
        sr.state = dualGovernance.currentState();
        sr.timestamp = block.timestamp;
        sr.rageQuitSupport = signallingEscrow.getRageQuitSupport();
        sr.maxRageQuitSupport =
            previousMaxRageQuitSupport < sr.rageQuitSupport ? sr.rageQuitSupport : previousMaxRageQuitSupport;
        sr.activationTime = dualGovernance.lastStateChangeTime();
        sr.reactivationTime = dualGovernance.lastStateReactivationTime();
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

        vm.assume(dualGovernance.currentState() != DualGovernanceModel.State.VetoSignalling);
        vm.assume(dualGovernance.currentState() != DualGovernanceModel.State.VetoSignallingDeactivation);

        dualGovernance.activateNextState();

        StateRecord memory sr = _recordCurrentState(0);

        // Consider only the case where we have transitioned to Veto Signalling
        if (sr.state == DualGovernanceModel.State.VetoSignalling) {
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

        vm.assume(previous.state != DualGovernanceModel.State.Normal);
        vm.assume(previous.state != DualGovernanceModel.State.VetoCooldown);
        vm.assume(previous.state != DualGovernanceModel.State.RageQuit);

        _vetoSignallingInvariants(Mode.Assume, previous);
        dualGovernance.activateNextState();

        StateRecord memory current = _recordCurrentState(maxRageQuitSupport);

        if (
            current.state != DualGovernanceModel.State.Normal && current.state != DualGovernanceModel.State.VetoCooldown
                && current.state != DualGovernanceModel.State.RageQuit
        ) {
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

        vm.assume(previous.maxRageQuitSupport <= dualGovernance.SECOND_SEAL_RAGE_QUIT_SUPPORT());
        vm.assume(_maxDeactivationDelayPassed(previous));
        vm.assume(signallingEscrow.getRageQuitSupport() <= previous.maxRageQuitSupport);

        vm.assume(
            previous.state == DualGovernanceModel.State.VetoSignalling
                || previous.state == DualGovernanceModel.State.VetoSignallingDeactivation
        );

        _vetoSignallingInvariants(Mode.Assume, previous);

        assert(previous.state == DualGovernanceModel.State.VetoSignallingDeactivation);

        dualGovernance.activateNextState();

        StateRecord memory current = _recordCurrentState(maxRageQuitSupport);

        uint256 deactivationStartTime = dualGovernance.lastSubStateActivationTime();
        uint256 deactivationEndTime = deactivationStartTime + dualGovernance.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION();

        // The protocol is either in the Deactivation sub-state, or, if the
        // maximum deactivation duration has passed, in the Veto Cooldown state
        if (deactivationEndTime < block.timestamp) {
            assert(current.state == DualGovernanceModel.State.VetoCooldown);
        } else {
            assert(current.state == DualGovernanceModel.State.VetoSignallingDeactivation);
        }
    }
}
