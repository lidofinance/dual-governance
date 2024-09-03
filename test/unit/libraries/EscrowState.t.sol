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

    function testFuzz_initialize_happyPath(
        Duration minAssetsLockDuration
    ) external {
        _context.state = State.NotInitialized;

        vm.expectEmit();
        emit EscrowState.EscrowStateChanged(State.NotInitialized, State.SignallingEscrow);
        emit EscrowState.MinAssetsLockDurationSet(minAssetsLockDuration);

        EscrowState.initialize(_context, minAssetsLockDuration);

        checkContext({
            state: State.SignallingEscrow,
            minAssetsLockDuration: minAssetsLockDuration,
            rageQuitExtensionPeriodDuration: D0,
            rageQuitWithdrawalsTimelock: D0,
            rageQuitExtensionPeriodStartedAt: T0
        });
    }

    function testFuzz_initialize_RevertOn_InvalidState(
        Duration minAssetsLockDuration
    ) external {
        _context.state = State.SignallingEscrow;

        // TODO: not very informative, maybe need to change to `revert UnexpectedState(self.state);`: UnexpectedState(NotInitialized)[current implementation] => UnexpectedState(SignallingEscrow)[proposed]
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.NotInitialized));

        EscrowState.initialize(_context, minAssetsLockDuration);
    }

    // ---
    // startRageQuit()
    // ---

    function testFuzz_startRageQuit_happyPath(
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitWithdrawalsTimelock
    ) external {
        _context.state = State.SignallingEscrow;

        vm.expectEmit();
        emit EscrowState.EscrowStateChanged(State.SignallingEscrow, State.RageQuitEscrow);
        emit EscrowState.RageQuitStarted(rageQuitExtensionPeriodDuration, rageQuitWithdrawalsTimelock);

        EscrowState.startRageQuit(_context, rageQuitExtensionPeriodDuration, rageQuitWithdrawalsTimelock);

        checkContext({
            state: State.RageQuitEscrow,
            minAssetsLockDuration: D0,
            rageQuitExtensionPeriodDuration: rageQuitExtensionPeriodDuration,
            rageQuitWithdrawalsTimelock: rageQuitWithdrawalsTimelock,
            rageQuitExtensionPeriodStartedAt: T0
        });
    }

    function testFuzz_startRageQuit_RevertOn_InvalidState(
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitWithdrawalsTimelock
    ) external {
        _context.state = State.NotInitialized;

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedState.selector, State.SignallingEscrow));

        EscrowState.startRageQuit(_context, rageQuitExtensionPeriodDuration, rageQuitWithdrawalsTimelock);
    }

    // ---
    // startRageQuitExtensionPeriod()
    // ---

    function test_startRageQuitExtensionPeriod_happyPath() external {
        vm.expectEmit();
        emit EscrowState.RageQuitTimelockStarted(Timestamps.now());

        EscrowState.startRageQuitExtensionPeriod(_context);

        checkContext({
            state: State.NotInitialized,
            minAssetsLockDuration: D0,
            rageQuitExtensionPeriodDuration: D0,
            rageQuitWithdrawalsTimelock: D0,
            rageQuitExtensionPeriodStartedAt: Timestamps.now()
        });
    }

    // ---
    // setMinAssetsLockDuration()
    // ---

    function test_setMinAssetsLockDuration_happyPath(
        Duration minAssetsLockDuration
    ) external {
        vm.assume(minAssetsLockDuration != Durations.ZERO);

        vm.expectEmit();
        emit EscrowState.MinAssetsLockDurationSet(minAssetsLockDuration);

        EscrowState.setMinAssetsLockDuration(_context, minAssetsLockDuration);

        checkContext({
            state: State.NotInitialized,
            minAssetsLockDuration: minAssetsLockDuration,
            rageQuitExtensionPeriodDuration: D0,
            rageQuitWithdrawalsTimelock: D0,
            rageQuitExtensionPeriodStartedAt: T0
        });
    }

    function test_setMinAssetsLockDuration_RevertWhen_DurationNotChanged(
        Duration minAssetsLockDuration
    ) external {
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

    function testFuzz_checkBatchesClaimingInProgress_RevertOn_InvalidState(
        Timestamp rageQuitExtensionPeriodStartedAt
    ) external {
        vm.assume(rageQuitExtensionPeriodStartedAt > Timestamps.ZERO);
        _context.rageQuitExtensionPeriodStartedAt = rageQuitExtensionPeriodStartedAt;
        vm.expectRevert(EscrowState.ClaimingIsFinished.selector);

        EscrowState.checkBatchesClaimingInProgress(_context);
    }

    // ---
    // checkWithdrawalsTimelockPassed()
    // ---

    function testFuzz_checkWithdrawalsTimelockPassed_happyPath(
        Timestamp rageQuitExtensionPeriodStartedAt,
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitWithdrawalsTimelock
    ) external {
        vm.assume(rageQuitExtensionPeriodStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionPeriodStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionPeriodDuration < Durations.from(type(uint16).max));
        vm.assume(rageQuitWithdrawalsTimelock < Durations.from(type(uint16).max));

        _context.rageQuitExtensionPeriodStartedAt = rageQuitExtensionPeriodStartedAt;
        _context.rageQuitExtensionPeriodDuration = rageQuitExtensionPeriodDuration;
        _context.rageQuitWithdrawalsTimelock = rageQuitWithdrawalsTimelock;

        _wait(
            Durations.between(
                (rageQuitExtensionPeriodDuration + rageQuitWithdrawalsTimelock).plusSeconds(1).addTo(
                    rageQuitExtensionPeriodStartedAt
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
        Timestamp rageQuitExtensionPeriodStartedAt,
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitWithdrawalsTimelock
    ) external {
        vm.assume(rageQuitExtensionPeriodStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionPeriodStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionPeriodDuration < Durations.from(type(uint16).max));
        vm.assume(rageQuitWithdrawalsTimelock < Durations.from(type(uint16).max));

        _context.rageQuitExtensionPeriodStartedAt = rageQuitExtensionPeriodStartedAt;
        _context.rageQuitExtensionPeriodDuration = rageQuitExtensionPeriodDuration;
        _context.rageQuitWithdrawalsTimelock = rageQuitWithdrawalsTimelock;

        _wait(
            Durations.between(
                (rageQuitExtensionPeriodDuration + rageQuitWithdrawalsTimelock).addTo(rageQuitExtensionPeriodStartedAt),
                Timestamps.now()
            )
        );

        vm.expectRevert(EscrowState.WithdrawalsTimelockNotPassed.selector);

        EscrowState.checkWithdrawalsTimelockPassed(_context);
    }

    function test_checkWithdrawalsTimelockPassed_RevertWhen_WithdrawalsTimelockOverflow() external {
        Duration rageQuitExtensionPeriodDuration = Durations.from(DURATION_MAX_VALUE / 2);
        Duration rageQuitWithdrawalsTimelock = Durations.from(DURATION_MAX_VALUE / 2 + 1);

        _context.rageQuitExtensionPeriodStartedAt = Timestamps.from(MAX_TIMESTAMP_VALUE - 1);
        _context.rageQuitExtensionPeriodDuration = rageQuitExtensionPeriodDuration;
        _context.rageQuitWithdrawalsTimelock = rageQuitWithdrawalsTimelock;

        vm.expectRevert(TimestampOverflow.selector);

        EscrowState.checkWithdrawalsTimelockPassed(_context);
    }

    // ---
    // isRageQuitExtensionPeriodStarted()
    // ---

    function testFuzz_isRageQuitExtensionDelayStarted_happyPath(
        Timestamp rageQuitExtensionPeriodStartedAt
    ) external {
        _context.rageQuitExtensionPeriodStartedAt = rageQuitExtensionPeriodStartedAt;
        bool res = EscrowState.isRageQuitExtensionPeriodStarted(_context);
        assertEq(res, _context.rageQuitExtensionPeriodStartedAt.isNotZero());
    }

    // ---
    // isRageQuitExtensionPeriodPassed()
    // ---

    function testFuzz_isRageQuitExtensionPeriodPassed_ReturnsTrue(
        Timestamp rageQuitExtensionPeriodStartedAt,
        Duration rageQuitExtensionPeriodDuration
    ) external {
        vm.assume(rageQuitExtensionPeriodStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionPeriodStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionPeriodDuration < Durations.from(type(uint16).max));

        _context.rageQuitExtensionPeriodStartedAt = rageQuitExtensionPeriodStartedAt;
        _context.rageQuitExtensionPeriodDuration = rageQuitExtensionPeriodDuration;

        _wait(
            Durations.between(
                rageQuitExtensionPeriodDuration.plusSeconds(1).addTo(rageQuitExtensionPeriodStartedAt), Timestamps.now()
            )
        );
        bool res = EscrowState.isRageQuitExtensionPeriodPassed(_context);
        assertTrue(res);
    }

    function testFuzz_isRageQuitExtensionDelayPassed_ReturnsFalse(
        Timestamp rageQuitExtensionPeriodStartedAt,
        Duration rageQuitExtensionPeriodDuration
    ) external {
        vm.assume(rageQuitExtensionPeriodStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionPeriodStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionPeriodDuration < Durations.from(type(uint16).max));

        _context.rageQuitExtensionPeriodStartedAt = rageQuitExtensionPeriodStartedAt;
        _context.rageQuitExtensionPeriodDuration = rageQuitExtensionPeriodDuration;

        _wait(
            Durations.between(rageQuitExtensionPeriodDuration.addTo(rageQuitExtensionPeriodStartedAt), Timestamps.now())
        );
        bool res = EscrowState.isRageQuitExtensionPeriodPassed(_context);
        assertFalse(res);
    }

    function test_isRageQuitExtensionDelayPassed_ReturnsFalseWhenRageQuitExtraTimelockNotStarted() external {
        _wait(Durations.from(1234));
        bool res = EscrowState.isRageQuitExtensionPeriodPassed(_context);
        assertFalse(res);
    }

    // ---
    // isRageQuitEscrow()
    // ---

    function testFuzz_isRageQuitEscrow(
        bool expectedResult
    ) external {
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
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitWithdrawalsTimelock,
        Timestamp rageQuitExtensionPeriodStartedAt
    ) internal {
        assertEq(_context.state, state);
        assertEq(_context.minAssetsLockDuration, minAssetsLockDuration);
        assertEq(_context.rageQuitExtensionPeriodDuration, rageQuitExtensionPeriodDuration);
        assertEq(_context.rageQuitWithdrawalsTimelock, rageQuitWithdrawalsTimelock);
        assertEq(_context.rageQuitExtensionPeriodStartedAt, rageQuitExtensionPeriodStartedAt);
    }

    function assertEq(State a, State b) internal {
        assertEq(uint256(a), uint256(b));
    }

}
