// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

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

        checkContext(State.SignallingEscrow, minAssetsLockDuration, D0, D0, T0);
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

        checkContext(State.RageQuitEscrow, D0, rageQuitExtensionDelay, rageQuitWithdrawalsTimelock, T0);
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
        emit EscrowState.RageQuitTimelockStarted();

        EscrowState.startRageQuitExtensionDelay(_context);

        checkContext(State.NotInitialized, D0, D0, D0, Timestamps.now());
    }

    // ---
    // setMinAssetsLockDuration()
    // ---

    function test_setMinAssetsLockDuration_happyPath(Duration minAssetsLockDuration) external {
        vm.assume(minAssetsLockDuration != Durations.ZERO);

        vm.expectEmit();
        emit EscrowState.MinAssetsLockDurationSet(minAssetsLockDuration);

        EscrowState.setMinAssetsLockDuration(_context, minAssetsLockDuration);

        checkContext(State.NotInitialized, minAssetsLockDuration, D0, D0, T0);
    }

    function test_setMinAssetsLockDuration_WhenDurationNotChanged(Duration minAssetsLockDuration) external {
        _context.minAssetsLockDuration = minAssetsLockDuration;

        Vm.Log[] memory entries = vm.getRecordedLogs();

        EscrowState.setMinAssetsLockDuration(_context, minAssetsLockDuration);

        checkContext(State.NotInitialized, minAssetsLockDuration, D0, D0, T0);

        assertEq(entries.length, 0);
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

        vm.warp(
            rageQuitExtensionDelayStartedAt.toSeconds() + rageQuitExtensionDelay.toSeconds()
                + rageQuitWithdrawalsTimelock.toSeconds() + 1
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

        vm.warp(
            rageQuitExtensionDelayStartedAt.toSeconds() + rageQuitExtensionDelay.toSeconds()
                + rageQuitWithdrawalsTimelock.toSeconds()
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
        assert(res == _context.rageQuitExtensionDelayStartedAt.isNotZero());
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

        vm.warp(rageQuitExtensionDelayStartedAt.toSeconds() + rageQuitExtensionDelay.toSeconds() + 1);
        bool res = EscrowState.isRageQuitExtensionDelayPassed(_context);
        assert(res == true);
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

        vm.warp(rageQuitExtensionDelayStartedAt.toSeconds() + rageQuitExtensionDelay.toSeconds());
        bool res = EscrowState.isRageQuitExtensionDelayPassed(_context);
        assert(res == false);
    }

    function test_isRageQuitExtensionDelayPassed_ReturnsFalseWhenRageQuitExtraTimelockNotStarted() external {
        vm.warp(1234);
        bool res = EscrowState.isRageQuitExtensionDelayPassed(_context);
        assert(res == false);
    }

    // ---
    // isRageQuitEscrow()
    // ---

    function testFuzz_isRageQuitEscrow(bool expectedResult) external {
        if (expectedResult) {
            _context.state = State.RageQuitEscrow;
        }
        bool actualResult = EscrowState.isRageQuitEscrow(_context);
        assert(actualResult == expectedResult);
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
    ) internal view {
        assert(_context.state == state);
        assert(_context.minAssetsLockDuration == minAssetsLockDuration);
        assert(_context.rageQuitExtensionDelay == rageQuitExtensionDelay);
        assert(_context.rageQuitWithdrawalsTimelock == rageQuitWithdrawalsTimelock);
        assert(_context.rageQuitExtensionDelayStartedAt == rageQuitExtensionDelayStartedAt);
    }
}
