pragma solidity 0.8.26;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "contracts/model/DualGovernance.sol";
import "contracts/model/EmergencyProtectedTimelock.sol";
import "contracts/model/Escrow.sol";

contract FakeETH is ERC20("fakeETH", "fETH") {}

contract VetoSignallingTest is Test, KontrolCheats {
    DualGovernance dualGovernance;
    EmergencyProtectedTimelock timelock;
    ERC20 fakeETH;
    Escrow signallingEscrow;
    Escrow rageQuitEscrow;

    uint256 constant CURRENT_STATE_SLOT = 3;
    uint256 constant CURRENT_STATE_OFFSET = 160;

    // Note: there are lemmas dependent on `ethUpperBound`
    uint256 constant ethMaxWidth = 96;
    uint256 constant ethUpperBound = 2 ** ethMaxWidth;
    uint256 constant timeUpperBound = 2 ** 40;

    enum Mode {
        Assume,
        Assert
    }

    function _establish(Mode mode, bool condition) internal view {
        if (mode == Mode.Assume) {
            vm.assume(condition);
        } else {
            assert(condition);
        }
    }

    function setUp() public {
        fakeETH = new FakeETH();
        uint256 emergencyProtectionTimelock = 0; // Regular deployment mode
        dualGovernance = new DualGovernance(address(fakeETH), emergencyProtectionTimelock);
        timelock = dualGovernance.emergencyProtectedTimelock();
        signallingEscrow = dualGovernance.signallingEscrow();
        rageQuitEscrow = new Escrow(address(dualGovernance), address(fakeETH));

        _fakeETHStorageSetup();
        _dualGovernanceStorageSetup();
        _signallingEscrowStorageSetup();
        _rageQuitEscrowStorageSetup();
        kevm.symbolicStorage(address(timelock)); // ?STORAGE3
    }

    function _fakeETHStorageSetup() internal {
        kevm.symbolicStorage(address(fakeETH)); // ?STORAGE
        // Slot 2
        uint256 totalSupply = kevm.freshUInt(32); // ?WORD
        vm.assume(0 < totalSupply);
        _storeUInt256(address(fakeETH), 2, totalSupply);
    }

    function _dualGovernanceStorageSetup() internal {
        kevm.symbolicStorage(address(dualGovernance)); // ?STORAGE0
        // Slot 0
        _storeAddress(address(dualGovernance), 0, address(timelock));
        // Slot 1
        _storeAddress(address(dualGovernance), 1, address(signallingEscrow));
        // Slot 2
        _storeAddress(address(dualGovernance), 2, address(rageQuitEscrow));
        // Slot 3
        uint8 state = uint8(kevm.freshUInt(1)); // ?WORD0
        vm.assume(state <= 4);
        bytes memory slot_3_abi_encoding = abi.encodePacked(uint88(0), state, address(fakeETH));
        bytes32 slot_3_for_storage;
        assembly {
            slot_3_for_storage := mload(add(slot_3_abi_encoding, 0x20))
        }
        _storeBytes32(address(dualGovernance), 3, slot_3_for_storage);
        // Slot 6
        uint256 lastStateChangeTime = kevm.freshUInt(32); // ?WORD1
        vm.assume(lastStateChangeTime <= block.timestamp);
        _storeUInt256(address(dualGovernance), 6, lastStateChangeTime);
        // Slot 7
        uint256 lastSubStateActivationTime = kevm.freshUInt(32); // ?WORD2
        vm.assume(lastSubStateActivationTime <= block.timestamp);
        _storeUInt256(address(dualGovernance), 7, lastSubStateActivationTime);
        // Slot 8
        uint256 lastStateReactivationTime = kevm.freshUInt(32); // ?WORD3
        vm.assume(lastStateReactivationTime <= block.timestamp);
        _storeUInt256(address(dualGovernance), 8, lastStateReactivationTime);
        // Slot 9
        uint256 lastVetoSignallingTime = kevm.freshUInt(32); // ?WORD4
        vm.assume(lastVetoSignallingTime <= block.timestamp);
        _storeUInt256(address(dualGovernance), 9, lastVetoSignallingTime);
        // Slot 10
        uint256 rageQuitSequenceNumber = kevm.freshUInt(32); // ?WORD5
        vm.assume(rageQuitSequenceNumber < type(uint256).max);
        _storeUInt256(address(dualGovernance), 10, rageQuitSequenceNumber);
    }

    function _signallingEscrowStorageSetup() internal {
        kevm.symbolicStorage(address(signallingEscrow)); // ?STORAGE1
        // Slot 0: currentState == 0 (SignallingEscrow), dualGovernance
        uint8 currentState = 0;
        bytes memory slot_0_abi_encoding = abi.encodePacked(uint88(0), address(dualGovernance), currentState);
        bytes32 slot_0_for_storage;
        assembly {
            slot_0_for_storage := mload(add(slot_0_abi_encoding, 0x20))
        }
        _storeBytes32(address(signallingEscrow), 0, slot_0_for_storage);
        // Slot 1
        _storeAddress(address(signallingEscrow), 1, address(fakeETH));
        // Slot 3
        uint256 totalStaked = kevm.freshUInt(32); // ?WORD6
        vm.assume(totalStaked < ethUpperBound);
        _storeUInt256(address(signallingEscrow), 3, totalStaked);
        // Slot 5
        uint256 totalClaimedEthAmount = kevm.freshUInt(32); // ?WORD7
        vm.assume(totalClaimedEthAmount <= totalStaked);
        _storeUInt256(address(signallingEscrow), 5, totalClaimedEthAmount);
        // Slot 11
        uint256 rageQuitExtensionDelayPeriodEnd = 0; // since SignallingEscrow
        _storeUInt256(address(signallingEscrow), 11, rageQuitExtensionDelayPeriodEnd);
    }

    function _rageQuitEscrowStorageSetup() internal {
        kevm.symbolicStorage(address(rageQuitEscrow)); // ?STORAGE2
        // Slot 0: currentState == 1 (RageQuitEscrow), dualGovernance
        uint8 currentState = 1;
        bytes memory slot_0_abi_encoding = abi.encodePacked(uint88(0), address(dualGovernance), currentState);
        bytes32 slot_0_for_storage;
        assembly {
            slot_0_for_storage := mload(add(slot_0_abi_encoding, 0x20))
        }
        _storeBytes32(address(rageQuitEscrow), 0, slot_0_for_storage);
        // Slot 1
        _storeAddress(address(rageQuitEscrow), 1, address(fakeETH));
        // Slot 3
        uint256 totalStaked = kevm.freshUInt(32); // ?WORD8
        vm.assume(totalStaked < ethUpperBound);
        _storeUInt256(address(rageQuitEscrow), 3, totalStaked);
        // Slot 5
        uint256 totalClaimedEthAmount = kevm.freshUInt(32); // ?WORD9
        vm.assume(totalClaimedEthAmount <= totalStaked);
        _storeUInt256(address(rageQuitEscrow), 5, totalClaimedEthAmount);
        // Slot 11
        uint256 rageQuitExtensionDelayPeriodEnd = kevm.freshUInt(32); // ?WORD10
        _storeUInt256(address(rageQuitEscrow), 11, rageQuitExtensionDelayPeriodEnd);
    }

    function _storeBytes32(address contractAddress, uint256 slot, bytes32 value) internal {
        vm.store(contractAddress, bytes32(slot), value);
    }

    function _storeUInt256(address contractAddress, uint256 slot, uint256 value) internal {
        vm.store(contractAddress, bytes32(slot), bytes32(value));
    }

    function _storeAddress(address contractAddress, uint256 slot, address value) internal {
        vm.store(contractAddress, bytes32(slot), bytes32(uint256(uint160(value))));
    }

    /**
     * Test that the Normal state transitions to VetoSignalling if the total
     * veto power in the signalling escrow exceeds the first seal threshold.
     */
    function testTransitionNormalToVetoSignalling() external {
        uint256 rageQuitSupport = signallingEscrow.getRageQuitSupport();
        vm.assume(rageQuitSupport > dualGovernance.FIRST_SEAL_RAGE_QUIT_SUPPORT());
        vm.assume(dualGovernance.currentState() == DualGovernance.State.Normal);
        dualGovernance.activateNextState();
        assert(dualGovernance.currentState() == DualGovernance.State.VetoSignalling);
    }

    struct StateRecord {
        DualGovernance.State state;
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
            sr.state != DualGovernance.State.Normal && sr.state != DualGovernance.State.VetoCooldown
                && sr.state != DualGovernance.State.RageQuit,
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
            _establish(mode, sr.state == DualGovernance.State.VetoSignalling);
        } else if (
            sr.timestamp
                <= Math.max(sr.reactivationTime, sr.activationTime) + dualGovernance.VETO_SIGNALLING_MIN_ACTIVE_DURATION()
        ) {
            _establish(mode, sr.state == DualGovernance.State.VetoSignalling);
        } else {
            _establish(mode, sr.state == DualGovernance.State.VetoSignallingDeactivation);
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
            _establish(mode, sr.state == DualGovernance.State.VetoSignallingDeactivation);
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

        vm.assume(dualGovernance.currentState() != DualGovernance.State.VetoSignalling);
        vm.assume(dualGovernance.currentState() != DualGovernance.State.VetoSignallingDeactivation);

        dualGovernance.activateNextState();

        StateRecord memory sr = _recordCurrentState(0);

        // Consider only the case where we have transitioned to Veto Signalling
        if (sr.state == DualGovernance.State.VetoSignalling) {
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

        vm.assume(previous.state != DualGovernance.State.Normal);
        vm.assume(previous.state != DualGovernance.State.VetoCooldown);
        vm.assume(previous.state != DualGovernance.State.RageQuit);

        _vetoSignallingInvariants(Mode.Assume, previous);
        dualGovernance.activateNextState();

        StateRecord memory current = _recordCurrentState(maxRageQuitSupport);

        if (
            current.state != DualGovernance.State.Normal && current.state != DualGovernance.State.VetoCooldown
                && current.state != DualGovernance.State.RageQuit
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
            previous.state == DualGovernance.State.VetoSignalling
                || previous.state == DualGovernance.State.VetoSignallingDeactivation
        );

        _vetoSignallingInvariants(Mode.Assume, previous);

        assert(previous.state == DualGovernance.State.VetoSignallingDeactivation);

        dualGovernance.activateNextState();

        StateRecord memory current = _recordCurrentState(maxRageQuitSupport);

        uint256 deactivationStartTime = dualGovernance.lastSubStateActivationTime();
        uint256 deactivationEndTime = deactivationStartTime + dualGovernance.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION();

        // The protocol is either in the Deactivation sub-state, or, if the
        // maximum deactivation duration has passed, in the Veto Cooldown state
        if (deactivationEndTime < block.timestamp) {
            assert(current.state == DualGovernance.State.VetoCooldown);
        } else {
            assert(current.state == DualGovernance.State.VetoSignallingDeactivation);
        }
    }
}
