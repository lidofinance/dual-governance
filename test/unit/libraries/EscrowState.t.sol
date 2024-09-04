// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations, MAX_VALUE as DURATION_MAX_VALUE} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps, MAX_TIMESTAMP_VALUE, TimestampOverflow} from "contracts/types/Timestamp.sol";
import {EscrowState, State} from "contracts/libraries/EscrowState.sol";

import {UnitTest} from "test/utils/unit-test.sol";

Duration constant D0 = Durations.ZERO;
Timestamp constant T0 = Timestamps.ZERO;

contract EscrowStateUnitTests is UnitTest {
    EscrowState.Context private _context;

    // ---
    // initialize()
    // ---

    function testFuzz_initialize_happyPath(Duration minAssetsLockDuration) external {
        _context.state = State.NotInitialized;

        vm.expectEmit();
        emit EscrowState.EscrowStateChanged(State.NotInitialized, State.SignallingEscrow);
        emit EscrowState.MinAssetsLockDurationSet(minAssetsLockDuration);

        EscrowState.initialize(_context, minAssetsLockDuration);

        checkContext({
            state: State.SignallingEscrow,
            minAssetsLockDuration: minAssetsLockDuration,
            rageQuitExtensionDelay: D0,
            rageQuitWithdrawalsTimelock: D0,
            rageQuitExtensionDelayStartedAt: T0
        });
    }

    function testFuzz_initialize_RevertOn_InvalidState(Duration minAssetsLockDuration) external {
        _context.state = State.SignallingEscrow;

        // TODO: not very informative, maybe need to change to `revert UnexpectedState(self.state);`: UnexpectedState(NotInitialized)[current implementation] => UnexpectedState(SignallingEscrow)[proposed]
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.NotInitialized));

        EscrowState.initialize(_context, minAssetsLockDuration);
    }

    // ---
    // startRageQuit()
    // ---

    function testFuzz_startRageQuit_happyPath(
        Duration rageQuitExtensionDelay,
        Duration rageQuitWithdrawalsTimelock
    ) external {
        _context.state = State.SignallingEscrow;

        vm.expectEmit();
        emit EscrowState.EscrowStateChanged(State.SignallingEscrow, State.RageQuitEscrow);
        emit EscrowState.RageQuitStarted(rageQuitExtensionDelay, rageQuitWithdrawalsTimelock);

        EscrowState.startRageQuit(_context, rageQuitExtensionDelay, rageQuitWithdrawalsTimelock);

        checkContext({
            state: State.RageQuitEscrow,
            minAssetsLockDuration: D0,
            rageQuitExtensionDelay: rageQuitExtensionDelay,
            rageQuitWithdrawalsTimelock: rageQuitWithdrawalsTimelock,
            rageQuitExtensionDelayStartedAt: T0
        });
    }

    function testFuzz_startRageQuit_RevertOn_InvalidState(
        Duration rageQuitExtensionDelay,
        Duration rageQuitWithdrawalsTimelock
    ) external {
        _context.state = State.NotInitialized;

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.SignallingEscrow));

        EscrowState.startRageQuit(_context, rageQuitExtensionDelay, rageQuitWithdrawalsTimelock);
    }

    // ---
    // startRageQuitExtensionDelay()
    // ---

    function test_startRageQuitExtensionDelay_happyPath() external {
        vm.expectEmit();
        emit EscrowState.RageQuitTimelockStarted(Timestamps.now());

        EscrowState.startRageQuitExtensionDelay(_context);

        checkContext({
            state: State.NotInitialized,
            minAssetsLockDuration: D0,
            rageQuitExtensionDelay: D0,
            rageQuitWithdrawalsTimelock: D0,
            rageQuitExtensionDelayStartedAt: Timestamps.now()
        });
    }

    // ---
    // setMinAssetsLockDuration()
    // ---

    function test_setMinAssetsLockDuration_happyPath(Duration minAssetsLockDuration) external {
        vm.assume(minAssetsLockDuration != Durations.ZERO);

        vm.expectEmit();
        emit EscrowState.MinAssetsLockDurationSet(minAssetsLockDuration);

        EscrowState.setMinAssetsLockDuration(_context, minAssetsLockDuration);

        checkContext({
            state: State.NotInitialized,
            minAssetsLockDuration: minAssetsLockDuration,
            rageQuitExtensionDelay: D0,
            rageQuitWithdrawalsTimelock: D0,
            rageQuitExtensionDelayStartedAt: T0
        });
    }

    function test_setMinAssetsLockDuration_RevertWhen_DurationNotChanged(Duration minAssetsLockDuration) external {
        _context.minAssetsLockDuration = minAssetsLockDuration;

        vm.expectRevert(
            abi.encodeWithSelector(EscrowState.InvalidMinAssetsLockDuration.selector, minAssetsLockDuration)
        );
        EscrowState.setMinAssetsLockDuration(_context, minAssetsLockDuration);
    }

    // ---
    // checkSignallingEscrow()
    // ---

    function test_checkSignallingEscrow_happyPath() external {
        _context.state = State.SignallingEscrow;
        EscrowState.checkSignallingEscrow(_context);
    }

    function test_checkSignallingEscrow_RevertOn_InvalidState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.SignallingEscrow));

        EscrowState.checkSignallingEscrow(_context);
    }

    // ---
    // checkRageQuitEscrow()
    // ---

    function test_checkRageQuitEscrow_happyPath() external {
        _context.state = State.RageQuitEscrow;
        EscrowState.checkRageQuitEscrow(_context);
    }

    function test_checkRageQuitEscrow_RevertOn_InvalidState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.RageQuitEscrow));

        EscrowState.checkRageQuitEscrow(_context);
    }

    // ---
    // checkBatchesClaimingInProgress()
    // ---

    function test_checkBatchesClaimingInProgress_happyPath() external view {
        EscrowState.checkBatchesClaimingInProgress(_context);
    }

    function testFuzz_checkBatchesClaimingInProgress_RevertOn_InvalidState(Timestamp rageQuitExtensionDelayStartedAt)
        external
    {
        vm.assume(rageQuitExtensionDelayStartedAt > Timestamps.ZERO);
        _context.rageQuitExtensionDelayStartedAt = rageQuitExtensionDelayStartedAt;
        vm.expectRevert(EscrowState.ClaimingIsFinished.selector);

        EscrowState.checkBatchesClaimingInProgress(_context);
    }

    // ---
    // checkWithdrawalsTimelockPassed()
    // ---

    function testFuzz_checkWithdrawalsTimelockPassed_happyPath(
        Timestamp rageQuitExtensionDelayStartedAt,
        Duration rageQuitExtensionDelay,
        Duration rageQuitWithdrawalsTimelock
    ) external {
        vm.assume(rageQuitExtensionDelayStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionDelayStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionDelay < Durations.from(type(uint16).max));
        vm.assume(rageQuitWithdrawalsTimelock < Durations.from(type(uint16).max));

        _context.rageQuitExtensionDelayStartedAt = rageQuitExtensionDelayStartedAt;
        _context.rageQuitExtensionDelay = rageQuitExtensionDelay;
        _context.rageQuitWithdrawalsTimelock = rageQuitWithdrawalsTimelock;

        _wait(
            Durations.between(
                (rageQuitExtensionDelay + rageQuitWithdrawalsTimelock).plusSeconds(1).addTo(
                    rageQuitExtensionDelayStartedAt
                ),
                Timestamps.now()
            )
        );
        EscrowState.checkWithdrawalsTimelockPassed(_context);
    }

    function test_checkWithdrawalsTimelockPassed_RevertWhen_RageQuitExtraTimelockNotStarted() external {
        vm.expectRevert(EscrowState.RageQuitExtraTimelockNotStarted.selector);

        EscrowState.checkWithdrawalsTimelockPassed(_context);
    }

    function testFuzz_checkWithdrawalsTimelockPassed_RevertWhen_WithdrawalsTimelockNotPassed(
        Timestamp rageQuitExtensionDelayStartedAt,
        Duration rageQuitExtensionDelay,
        Duration rageQuitWithdrawalsTimelock
    ) external {
        vm.assume(rageQuitExtensionDelayStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionDelayStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionDelay < Durations.from(type(uint16).max));
        vm.assume(rageQuitWithdrawalsTimelock < Durations.from(type(uint16).max));

        _context.rageQuitExtensionDelayStartedAt = rageQuitExtensionDelayStartedAt;
        _context.rageQuitExtensionDelay = rageQuitExtensionDelay;
        _context.rageQuitWithdrawalsTimelock = rageQuitWithdrawalsTimelock;

        _wait(
            Durations.between(
                (rageQuitExtensionDelay + rageQuitWithdrawalsTimelock).addTo(rageQuitExtensionDelayStartedAt),
                Timestamps.now()
            )
        );

        vm.expectRevert(EscrowState.WithdrawalsTimelockNotPassed.selector);

        EscrowState.checkWithdrawalsTimelockPassed(_context);
    }

    function test_checkWithdrawalsTimelockPassed_RevertWhen_WithdrawalsTimelockOverflow() external {
        Duration rageQuitExtensionDelay = Durations.from(DURATION_MAX_VALUE / 2);
        Duration rageQuitWithdrawalsTimelock = Durations.from(DURATION_MAX_VALUE / 2 + 1);

        _context.rageQuitExtensionDelayStartedAt = Timestamps.from(MAX_TIMESTAMP_VALUE - 1);
        _context.rageQuitExtensionDelay = rageQuitExtensionDelay;
        _context.rageQuitWithdrawalsTimelock = rageQuitWithdrawalsTimelock;

        vm.expectRevert(TimestampOverflow.selector);

        EscrowState.checkWithdrawalsTimelockPassed(_context);
    }

    // ---
    // isRageQuitExtensionDelayStarted()
    // ---

    function testFuzz_isRageQuitExtensionDelayStarted_happyPath(Timestamp rageQuitExtensionDelayStartedAt) external {
        _context.rageQuitExtensionDelayStartedAt = rageQuitExtensionDelayStartedAt;
        bool res = EscrowState.isRageQuitExtensionDelayStarted(_context);
        assertEq(res, _context.rageQuitExtensionDelayStartedAt.isNotZero());
    }

    // ---
    // isRageQuitExtensionDelayPassed()
    // ---

    function testFuzz_isRageQuitExtensionDelayPassed_ReturnsTrue(
        Timestamp rageQuitExtensionDelayStartedAt,
        Duration rageQuitExtensionDelay
    ) external {
        vm.assume(rageQuitExtensionDelayStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionDelayStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionDelay < Durations.from(type(uint16).max));

        _context.rageQuitExtensionDelayStartedAt = rageQuitExtensionDelayStartedAt;
        _context.rageQuitExtensionDelay = rageQuitExtensionDelay;

        _wait(
            Durations.between(
                rageQuitExtensionDelay.plusSeconds(1).addTo(rageQuitExtensionDelayStartedAt), Timestamps.now()
            )
        );
        bool res = EscrowState.isRageQuitExtensionDelayPassed(_context);
        assertTrue(res);
    }

    function testFuzz_isRageQuitExtensionDelayPassed_ReturnsFalse(
        Timestamp rageQuitExtensionDelayStartedAt,
        Duration rageQuitExtensionDelay
    ) external {
        vm.assume(rageQuitExtensionDelayStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionDelayStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionDelay < Durations.from(type(uint16).max));

        _context.rageQuitExtensionDelayStartedAt = rageQuitExtensionDelayStartedAt;
        _context.rageQuitExtensionDelay = rageQuitExtensionDelay;

        _wait(Durations.between(rageQuitExtensionDelay.addTo(rageQuitExtensionDelayStartedAt), Timestamps.now()));
        bool res = EscrowState.isRageQuitExtensionDelayPassed(_context);
        assertFalse(res);
    }

    function test_isRageQuitExtensionDelayPassed_ReturnsFalseWhenRageQuitExtraTimelockNotStarted() external {
        _wait(Durations.from(1234));
        bool res = EscrowState.isRageQuitExtensionDelayPassed(_context);
        assertFalse(res);
    }

    // ---
    // isRageQuitEscrow()
    // ---

    function testFuzz_isRageQuitEscrow(bool expectedResult) external {
        if (expectedResult) {
            _context.state = State.RageQuitEscrow;
        }
        bool actualResult = EscrowState.isRageQuitEscrow(_context);
        assertEq(actualResult, expectedResult);
    }

    // ---
    // helpers()
    // ---

    function checkContext(
        State state,
        Duration minAssetsLockDuration,
        Duration rageQuitExtensionDelay,
        Duration rageQuitWithdrawalsTimelock,
        Timestamp rageQuitExtensionDelayStartedAt
    ) internal {
        assertEq(_context.state, state);
        assertEq(_context.minAssetsLockDuration, minAssetsLockDuration);
        assertEq(_context.rageQuitExtensionDelay, rageQuitExtensionDelay);
        assertEq(_context.rageQuitWithdrawalsTimelock, rageQuitWithdrawalsTimelock);
        assertEq(_context.rageQuitExtensionDelayStartedAt, rageQuitExtensionDelayStartedAt);
    }

    function assertEq(State a, State b) internal {
        assertEq(uint256(a), uint256(b));
    }
}
