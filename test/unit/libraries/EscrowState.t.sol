// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations, MAX_DURATION_VALUE} from "contracts/types/Duration.sol";
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
        Duration minAssetsLockDuration,
        Duration maxMinAssetsLockDuration
    ) external {
        vm.assume(minAssetsLockDuration > Durations.ZERO);
        vm.assume(minAssetsLockDuration <= maxMinAssetsLockDuration);

        _context.state = State.NotInitialized;

        vm.expectEmit();
        emit EscrowState.EscrowStateChanged(State.NotInitialized, State.SignallingEscrow);
        emit EscrowState.MinAssetsLockDurationSet(minAssetsLockDuration);

        EscrowState.initialize(_context, minAssetsLockDuration, maxMinAssetsLockDuration);

        checkContext({
            state: State.SignallingEscrow,
            minAssetsLockDuration: minAssetsLockDuration,
            rageQuitExtensionPeriodDuration: D0,
            rageQuitEthWithdrawalsDelay: D0,
            rageQuitExtensionPeriodStartedAt: T0
        });
    }

    function testFuzz_initialize_RevertOn_InvalidState(
        Duration minAssetsLockDuration,
        Duration maxMinAssetsLockDuration
    ) external {
        vm.assume(minAssetsLockDuration <= maxMinAssetsLockDuration);
        _context.state = State.SignallingEscrow;

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.SignallingEscrow));

        EscrowState.initialize(_context, minAssetsLockDuration, maxMinAssetsLockDuration);
    }

    // ---
    // startRageQuit()
    // ---

    function testFuzz_startRageQuit_happyPath(
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitEthWithdrawalsDelay
    ) external {
        _context.state = State.SignallingEscrow;

        vm.expectEmit();
        emit EscrowState.EscrowStateChanged(State.SignallingEscrow, State.RageQuitEscrow);
        emit EscrowState.RageQuitStarted(rageQuitExtensionPeriodDuration, rageQuitEthWithdrawalsDelay);

        EscrowState.startRageQuit(_context, rageQuitExtensionPeriodDuration, rageQuitEthWithdrawalsDelay);

        checkContext({
            state: State.RageQuitEscrow,
            minAssetsLockDuration: D0,
            rageQuitExtensionPeriodDuration: rageQuitExtensionPeriodDuration,
            rageQuitEthWithdrawalsDelay: rageQuitEthWithdrawalsDelay,
            rageQuitExtensionPeriodStartedAt: T0
        });
    }

    function testFuzz_startRageQuit_RevertOn_InvalidState(
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitEthWithdrawalsDelay
    ) external {
        _context.state = State.NotInitialized;

        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.NotInitialized));

        EscrowState.startRageQuit(_context, rageQuitExtensionPeriodDuration, rageQuitEthWithdrawalsDelay);
    }

    // ---
    // startRageQuitExtensionPeriod()
    // ---

    function test_startRageQuitExtensionPeriod_happyPath() external {
        vm.expectEmit();
        emit EscrowState.RageQuitExtensionPeriodStarted(Timestamps.now());

        EscrowState.startRageQuitExtensionPeriod(_context);

        checkContext({
            state: State.NotInitialized,
            minAssetsLockDuration: D0,
            rageQuitExtensionPeriodDuration: D0,
            rageQuitEthWithdrawalsDelay: D0,
            rageQuitExtensionPeriodStartedAt: Timestamps.now()
        });
    }

    // ---
    // setMinAssetsLockDuration()
    // ---

    function testFuzz_setMinAssetsLockDuration_happyPath(
        Duration minAssetsLockDuration,
        Duration maxMinAssetsLockDuration
    ) external {
        vm.assume(minAssetsLockDuration != Durations.ZERO);
        vm.assume(minAssetsLockDuration <= maxMinAssetsLockDuration);

        vm.expectEmit();
        emit EscrowState.MinAssetsLockDurationSet(minAssetsLockDuration);

        EscrowState.setMinAssetsLockDuration(_context, minAssetsLockDuration, maxMinAssetsLockDuration);

        checkContext({
            state: State.NotInitialized,
            minAssetsLockDuration: minAssetsLockDuration,
            rageQuitExtensionPeriodDuration: D0,
            rageQuitEthWithdrawalsDelay: D0,
            rageQuitExtensionPeriodStartedAt: T0
        });
    }

    function testFuzz_setMinAssetsLockDuration_RevertWhen_DurationNotChanged(Duration minAssetsLockDuration) external {
        _context.minAssetsLockDuration = minAssetsLockDuration;

        vm.expectRevert(
            abi.encodeWithSelector(EscrowState.InvalidMinAssetsLockDuration.selector, minAssetsLockDuration)
        );
        EscrowState.setMinAssetsLockDuration(_context, minAssetsLockDuration, Durations.from(MAX_DURATION_VALUE));
    }

    function testFuzz_setMinAssetsLockDuration_RevertWhen_DurationGreaterThenMaxMinAssetsLockDuration(
        Duration minAssetsLockDuration,
        Duration maxMinAssetsLockDuration
    ) external {
        vm.assume(minAssetsLockDuration > maxMinAssetsLockDuration);

        vm.expectRevert(
            abi.encodeWithSelector(EscrowState.InvalidMinAssetsLockDuration.selector, minAssetsLockDuration)
        );
        EscrowState.setMinAssetsLockDuration(_context, minAssetsLockDuration, maxMinAssetsLockDuration);
    }

    // ---
    // checkSignallingEscrow()
    // ---

    function test_checkSignallingEscrow_happyPath() external {
        _context.state = State.SignallingEscrow;
        EscrowState.checkSignallingEscrow(_context);
    }

    function test_checkSignallingEscrow_RevertOn_InvalidState() external {
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.NotInitialized));
        EscrowState.checkSignallingEscrow(_context);

        _context.state = State.RageQuitEscrow;
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.RageQuitEscrow));
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
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.NotInitialized));
        EscrowState.checkRageQuitEscrow(_context);

        _context.state = State.SignallingEscrow;
        vm.expectRevert(abi.encodeWithSelector(EscrowState.UnexpectedEscrowState.selector, State.SignallingEscrow));
        EscrowState.checkRageQuitEscrow(_context);
    }

    // ---
    // checkBatchesClaimingInProgress()
    // ---

    function test_checkBatchesClaimingInProgress_happyPath() external view {
        EscrowState.checkBatchesClaimingInProgress(_context);
    }

    function testFuzz_checkBatchesClaimingInProgress_RevertOn_InvalidState(Timestamp rageQuitExtensionPeriodStartedAt)
        external
    {
        vm.assume(rageQuitExtensionPeriodStartedAt > Timestamps.ZERO);
        _context.rageQuitExtensionPeriodStartedAt = rageQuitExtensionPeriodStartedAt;
        vm.expectRevert(EscrowState.ClaimingIsFinished.selector);

        EscrowState.checkBatchesClaimingInProgress(_context);
    }

    // ---
    // checkEthWithdrawalsDelayPassed()
    // ---

    function testFuzz_checkWithdrawalsDelayPassed_happyPath(
        Timestamp rageQuitExtensionPeriodStartedAt,
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitEthWithdrawalsDelay
    ) external {
        vm.assume(rageQuitExtensionPeriodStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionPeriodStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionPeriodDuration < Durations.from(type(uint16).max));
        vm.assume(rageQuitEthWithdrawalsDelay < Durations.from(type(uint16).max));

        _context.rageQuitExtensionPeriodStartedAt = rageQuitExtensionPeriodStartedAt;
        _context.rageQuitExtensionPeriodDuration = rageQuitExtensionPeriodDuration;
        _context.rageQuitEthWithdrawalsDelay = rageQuitEthWithdrawalsDelay;

        Duration totalWithdrawalsDelay = rageQuitExtensionPeriodDuration + rageQuitEthWithdrawalsDelay;
        Timestamp withdrawalsAllowedAt = totalWithdrawalsDelay.plusSeconds(1).addTo(rageQuitExtensionPeriodStartedAt);

        _wait(Durations.from(withdrawalsAllowedAt.toSeconds() - Timestamps.now().toSeconds()));
        EscrowState.checkEthWithdrawalsDelayPassed(_context);
    }

    function test_checkEthWithdrawalsDelayPassed_RevertWhen_RageQuitExtensionPeriodNotStarted() external {
        vm.expectRevert(EscrowState.RageQuitExtensionPeriodNotStarted.selector);

        EscrowState.checkEthWithdrawalsDelayPassed(_context);
    }

    function testFuzz_checkWithdrawalsDelayPassed_RevertWhen_EthWithdrawalsDelayNotPassed(
        Timestamp rageQuitExtensionPeriodStartedAt,
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitEthWithdrawalsDelay
    ) external {
        vm.assume(rageQuitExtensionPeriodStartedAt > Timestamps.ZERO);
        vm.assume(rageQuitExtensionPeriodStartedAt < Timestamps.from(type(uint16).max));
        vm.assume(rageQuitExtensionPeriodDuration < Durations.from(type(uint16).max));
        vm.assume(rageQuitEthWithdrawalsDelay < Durations.from(type(uint16).max));

        _context.rageQuitExtensionPeriodStartedAt = rageQuitExtensionPeriodStartedAt;
        _context.rageQuitExtensionPeriodDuration = rageQuitExtensionPeriodDuration;
        _context.rageQuitEthWithdrawalsDelay = rageQuitEthWithdrawalsDelay;

        Duration totalWithdrawalsDelay = rageQuitExtensionPeriodDuration + rageQuitEthWithdrawalsDelay;
        Timestamp withdrawalsAllowedAfter = totalWithdrawalsDelay.addTo(rageQuitExtensionPeriodStartedAt);

        _wait(Durations.from(withdrawalsAllowedAfter.toSeconds() - Timestamps.now().toSeconds()));

        vm.expectRevert(EscrowState.EthWithdrawalsDelayNotPassed.selector);

        EscrowState.checkEthWithdrawalsDelayPassed(_context);
    }

    function test_checkWithdrawalsDelayPassed_RevertWhen_EthWithdrawalsDelayOverflow() external {
        Duration rageQuitExtensionPeriodDuration = Durations.from(MAX_DURATION_VALUE / 2);
        Duration rageQuitEthWithdrawalsDelay = Durations.from(MAX_DURATION_VALUE / 2 + 1);

        _context.rageQuitExtensionPeriodStartedAt = Timestamps.from(MAX_TIMESTAMP_VALUE - 1);
        _context.rageQuitExtensionPeriodDuration = rageQuitExtensionPeriodDuration;
        _context.rageQuitEthWithdrawalsDelay = rageQuitEthWithdrawalsDelay;

        vm.expectRevert(TimestampOverflow.selector);

        EscrowState.checkEthWithdrawalsDelayPassed(_context);
    }

    // ---
    // isRageQuitExtensionPeriodStarted()
    // ---

    function testFuzz_isRageQuitExtensionDelayStarted_happyPath(Timestamp rageQuitExtensionPeriodStartedAt) external {
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

        Timestamp rageQuitExtensionPeriodPassedAfter =
            rageQuitExtensionPeriodDuration.plusSeconds(1).addTo(rageQuitExtensionPeriodStartedAt);

        _wait(Durations.from(rageQuitExtensionPeriodPassedAfter.toSeconds() - Timestamps.now().toSeconds()));
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

        Timestamp rageQuitExtensionPeriodPassedAt =
            rageQuitExtensionPeriodDuration.addTo(rageQuitExtensionPeriodStartedAt);

        _wait(Durations.from(rageQuitExtensionPeriodPassedAt.toSeconds() - Timestamps.now().toSeconds()));
        bool res = EscrowState.isRageQuitExtensionPeriodPassed(_context);
        assertFalse(res);
    }

    function test_isRageQuitExtensionDelayPassed_ReturnsFalseWhenRageQuitExtensionPeriodNotStarted() external {
        _wait(Durations.from(1234));
        bool res = EscrowState.isRageQuitExtensionPeriodPassed(_context);
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
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitEthWithdrawalsDelay,
        Timestamp rageQuitExtensionPeriodStartedAt
    ) internal {
        assertEq(_context.state, state);
        assertEq(_context.minAssetsLockDuration, minAssetsLockDuration);
        assertEq(_context.rageQuitExtensionPeriodDuration, rageQuitExtensionPeriodDuration);
        assertEq(_context.rageQuitEthWithdrawalsDelay, rageQuitEthWithdrawalsDelay);
        assertEq(_context.rageQuitExtensionPeriodStartedAt, rageQuitExtensionPeriodStartedAt);
    }

    function assertEq(State a, State b) internal {
        assertEq(uint256(a), uint256(b));
    }
}
