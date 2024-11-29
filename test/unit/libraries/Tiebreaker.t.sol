// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {State as DualGovernanceState} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {Tiebreaker} from "contracts/libraries/Tiebreaker.sol";
import {Duration, Durations, Timestamp, Timestamps} from "contracts/types/Duration.sol";
import {ISealable} from "contracts/interfaces/ISealable.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";

import {UnitTest} from "test/utils/unit-test.sol";

error CustomSealableError(string reason);

contract TiebreakerTest is UnitTest {
    using Tiebreaker for Tiebreaker.Context;
    using EnumerableSet for EnumerableSet.AddressSet;

    address private immutable _SEALABLE = makeAddr("SEALABLE");
    Tiebreaker.Context private context;

    function setUp() external {
        // The expected state of the sealable most of the time - unpaused
        // According to the implementation of PausableUntil
        // https://github.com/lidofinance/core/blob/60bc9b77b036eec22b2ab8a3a1d49c6b6614c600/contracts/0.8.9/utils/PausableUntil.sol#L52
        // the sealable is considered resumed when block.timestamp >= resumeSinceTimestamp
        _mockSealableResumeSinceTimestampResult(_SEALABLE, block.timestamp);
    }

    // ---
    // addSealableWithdrawalBlocker()
    // ---

    function test_addSealableWithdrawalBlocker_HappyPath() external {
        vm.expectEmit();
        emit Tiebreaker.SealableWithdrawalBlockerAdded(_SEALABLE);
        this.external__addSealableWithdrawalBlocker(_SEALABLE);
        assertTrue(context.sealableWithdrawalBlockers.contains(_SEALABLE));

        context.removeSealableWithdrawalBlocker(_SEALABLE);

        _mockSealableResumeSinceTimestampResult(_SEALABLE, 0);
        this.external__addSealableWithdrawalBlocker(_SEALABLE);
        assertTrue(context.sealableWithdrawalBlockers.contains(_SEALABLE));

        context.removeSealableWithdrawalBlocker(_SEALABLE);

        _wait(Durations.from(42 seconds));

        _mockSealableResumeSinceTimestampResult(_SEALABLE, block.timestamp / 2);
        this.external__addSealableWithdrawalBlocker(_SEALABLE);
        assertTrue(context.sealableWithdrawalBlockers.contains(_SEALABLE));
    }

    function test_addSealableWithdrawalBlocker_RevertOn_LimitReached() external {
        uint256 maxSealableWithdrawalBlockersCount = 1;
        this.external__addSealableWithdrawalBlocker(_SEALABLE, maxSealableWithdrawalBlockersCount);

        address newSealable = makeAddr("NEW_SEALABLE");
        _mockSealableResumeSinceTimestampResult(newSealable, 0);

        vm.expectRevert(Tiebreaker.SealableWithdrawalBlockersLimitReached.selector);
        this.external__addSealableWithdrawalBlocker(newSealable, maxSealableWithdrawalBlockersCount);
    }

    function test_addSealableWithdrawalBlocker_RevertOn_AlreadyAdded() external {
        this.external__addSealableWithdrawalBlocker(_SEALABLE);

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.SealableWithdrawalBlockerAlreadyAdded.selector, _SEALABLE));
        this.external__addSealableWithdrawalBlocker(_SEALABLE);
    }

    function test_addSealableWithdrawalBlocker_RevertOn_InvalidSealable() external {
        address emptyAccount = makeAddr("EMPTY_ACCOUNT");
        assertEq(emptyAccount.code.length, 0);

        // revert when sealable is not a contract
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidSealable.selector, emptyAccount));

        this.external__addSealableWithdrawalBlocker(emptyAccount);

        // reverts when sealable's isPaused call reverts without reason
        _mockSealableResumeSinceTimestampReverts(_SEALABLE, "");
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidSealable.selector, _SEALABLE));

        this.external__addSealableWithdrawalBlocker(_SEALABLE);

        // revert when sealable's isPaused call returns invalid value
        _mockSealableResumeSinceTimestampReverts(_SEALABLE, abi.encode("Invalid Result"));
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidSealable.selector, _SEALABLE));

        this.external__addSealableWithdrawalBlocker(_SEALABLE);

        // set the block timestamp to make sure it's > 0
        _wait(Durations.from(42 seconds));

        // revert when sealable is paused for short period

        // edge case, the last second of the pause period
        _mockSealableResumeSinceTimestampResult(_SEALABLE, block.timestamp + 1);
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidSealable.selector, _SEALABLE));

        this.external__addSealableWithdrawalBlocker(_SEALABLE);

        // the finite period of time
        _mockSealableResumeSinceTimestampResult(_SEALABLE, block.timestamp + 30 days);
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidSealable.selector, _SEALABLE));

        this.external__addSealableWithdrawalBlocker(_SEALABLE);

        // revert when sealable is paused for long period
        _mockSealableResumeSinceTimestampResult(_SEALABLE, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidSealable.selector, _SEALABLE));

        this.external__addSealableWithdrawalBlocker(_SEALABLE);
    }

    // ---
    // removeSealableWithdrawalBlocker()
    // ---

    function test_removeSealableWithdrawalBlocker_HappyPath() external {
        this.external__addSealableWithdrawalBlocker(_SEALABLE);
        assertTrue(context.sealableWithdrawalBlockers.contains(_SEALABLE));

        vm.expectEmit();
        emit Tiebreaker.SealableWithdrawalBlockerRemoved(_SEALABLE);

        this.external__removeSealableWithdrawalBlocker(_SEALABLE);
        assertFalse(context.sealableWithdrawalBlockers.contains(_SEALABLE));
    }

    function test_removeSealableWithdrawalBlocker_RevertOn_NotFound() external {
        vm.expectRevert(
            abi.encodeWithSelector(Tiebreaker.SealableWithdrawalBlockerNotFound.selector, address(_SEALABLE))
        );
        this.external__removeSealableWithdrawalBlocker(_SEALABLE);
    }

    // ---
    // setTiebreakerCommittee()
    // ---

    function test_setTiebreakerCommittee_HappyPath() external {
        address newCommittee = makeAddr("TIEBREAKER_COMMITTEE");

        vm.expectEmit();
        emit Tiebreaker.TiebreakerCommitteeSet(newCommittee);

        this.external__setTiebreakerCommittee(newCommittee);
        assertEq(context.tiebreakerCommittee, newCommittee);
    }

    function test_setTiebreakerCommittee_RevertOn_SameCommitteeAddress() external {
        address newCommittee = makeAddr("TIEBREAKER_COMMITTEE");
        this.external__setTiebreakerCommittee(newCommittee);
        assertEq(context.tiebreakerCommittee, newCommittee);

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerCommittee.selector, newCommittee));
        this.external__setTiebreakerCommittee(newCommittee);
    }

    function test_setTiebreakerCommittee_RevertOn_ZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerCommittee.selector, address(0)));
        this.external__setTiebreakerCommittee(address(0));
    }

    // ---
    // setTiebreakerActivationTimeout()
    // ---

    function test_setTiebreakerActivationTimeout_HappyPath() external {
        assertEq(context.tiebreakerActivationTimeout, Durations.ZERO);

        Duration minTimeout = Durations.from(1 days);
        Duration newTimeout = Durations.from(8 days);
        Duration maxTimeout = Durations.from(10 days);

        vm.expectEmit();
        emit Tiebreaker.TiebreakerActivationTimeoutSet(newTimeout);

        this.external__setTiebreakerActivationTimeout(minTimeout, newTimeout, maxTimeout);
        assertEq(context.tiebreakerActivationTimeout, newTimeout);
    }

    function test_setTiebreakerActivationTimeout_HappyPath_EdgeCases() external {
        context.tiebreakerActivationTimeout = Durations.from(7 days);

        Duration minTimeout = Durations.from(1 days);
        Duration maxTimeout = Durations.from(10 days);

        // equal to min timeout
        Duration newTimeout = minTimeout;
        this.external__setTiebreakerActivationTimeout(minTimeout, newTimeout, maxTimeout);
        assertEq(context.tiebreakerActivationTimeout, newTimeout);

        // equal to max timeout
        newTimeout = maxTimeout;
        this.external__setTiebreakerActivationTimeout(minTimeout, newTimeout, maxTimeout);
        assertEq(context.tiebreakerActivationTimeout, newTimeout);
    }

    function test_setTiebreakerActivationTimeout_RevertOn_NewTimeoutSameAsOldOne() external {
        Duration newTimeout = Durations.from(30 days);
        context.tiebreakerActivationTimeout = newTimeout;

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerActivationTimeout.selector, newTimeout));
        this.external__setTiebreakerActivationTimeout(Durations.from(0), newTimeout, Durations.from(90 days));
    }

    function test_setTiebreakerActivationTimeout_RevertOn_InvalidTimeout() external {
        Duration minTimeout = Duration.wrap(1 days);
        Duration maxTimeout = Duration.wrap(10 days);
        Duration newTimeout = Duration.wrap(15 days);

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerActivationTimeout.selector, newTimeout));
        this.external__setTiebreakerActivationTimeout(minTimeout, newTimeout, maxTimeout);

        newTimeout = Duration.wrap(0 days);

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerActivationTimeout.selector, newTimeout));
        this.external__setTiebreakerActivationTimeout(minTimeout, newTimeout, maxTimeout);
    }

    function testFuzz_setTiebreakerActivationTimeout_HappyPath(
        Duration minTimeout,
        Duration oldTimeout,
        Duration newTimeout,
        Duration maxTimeout
    ) external {
        vm.assume(newTimeout >= minTimeout && newTimeout <= maxTimeout);
        vm.assume(oldTimeout != newTimeout);

        // this value may be not in range [minTimeout, maxTimeout], but it's ok for this test
        context.tiebreakerActivationTimeout = oldTimeout;

        vm.expectEmit();
        emit Tiebreaker.TiebreakerActivationTimeoutSet(newTimeout);

        this.external__setTiebreakerActivationTimeout(minTimeout, newTimeout, maxTimeout);
        assertEq(context.tiebreakerActivationTimeout, newTimeout);
    }

    function testFuzz_setTiebreakerActivationTimeout_RevertOn_NewTimeoutLessThanMinTimeout(
        Duration minTimeout,
        Duration oldTimeout,
        Duration newTimeout,
        Duration maxTimeout
    ) external {
        vm.assume(newTimeout < minTimeout && newTimeout <= maxTimeout);
        vm.assume(oldTimeout != newTimeout);

        // this value may be not in range [minTimeout, maxTimeout], but it's ok for this test
        context.tiebreakerActivationTimeout = oldTimeout;

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerActivationTimeout.selector, newTimeout));
        this.external__setTiebreakerActivationTimeout(minTimeout, newTimeout, maxTimeout);
    }

    function testFuzz_setTiebreakerActivationTimeout_RevertOn_NewTimeoutGreaterThanMaxTimeout(
        Duration minTimeout,
        Duration oldTimeout,
        Duration newTimeout,
        Duration maxTimeout
    ) external {
        vm.assume(newTimeout >= minTimeout && newTimeout > maxTimeout);
        vm.assume(oldTimeout != newTimeout);

        // this value may be not in range [minTimeout, maxTimeout], but it's ok for this test
        context.tiebreakerActivationTimeout = oldTimeout;

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerActivationTimeout.selector, newTimeout));
        this.external__setTiebreakerActivationTimeout(minTimeout, newTimeout, maxTimeout);
    }

    // ---
    // isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty()
    // ---

    function test_isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty_ReturnsTrue_OnValidSealable() external {
        this.external__addSealableWithdrawalBlocker(_SEALABLE);

        assertFalse(context.isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty());

        // sealable is paused now
        _mockSealableResumeSinceTimestampResult(_SEALABLE, type(uint256).max);
        assertTrue(context.isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty());
    }

    /// @dev consider only some possible reasons of sealable fails here, the full list of possible
    ///     failures is checked in the tests for SealableCalls lib
    function test_isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty_ReturnsFalse_OnFaultySealable() external {
        // revert when sealable is an empty account
        address emptyAccount = makeAddr("EMPTY_ACCOUNT");
        assertEq(emptyAccount.code.length, 0);

        assertTrue(context.sealableWithdrawalBlockers.add(emptyAccount));
        assertTrue(context.isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty());
        assertTrue(context.sealableWithdrawalBlockers.remove(emptyAccount));

        assertFalse(context.isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty());
        this.external__addSealableWithdrawalBlocker(_SEALABLE);

        // reverts when sealable's isPaused call reverts without reason
        _mockSealableResumeSinceTimestampReverts(_SEALABLE, "");
        assertTrue(context.isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty());

        // revert when sealable's isPaused call returns invalid value
        vm.mockCall(
            _SEALABLE,
            abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector),
            abi.encode(["Invalid", "Result"])
        );
        assertTrue(context.isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty());
    }

    // ---
    // checkTie()
    // ---

    function test_checkTie_HappyPath_SealablePausedInRageQuitState() external {
        Timestamp normalOrVetoCooldownExitedAt = Timestamps.now();
        Duration tiebreakerActivationTimeout = Durations.from(180 days);
        Timestamp tiebreakerAllowedAt = tiebreakerActivationTimeout.addTo(normalOrVetoCooldownExitedAt);

        this.external__addSealableWithdrawalBlocker(_SEALABLE);
        this.external__setTiebreakerActivationTimeout(tiebreakerActivationTimeout);

        // tiebreak is not allowed in the normal state
        vm.expectRevert(Tiebreaker.TiebreakNotAllowed.selector);
        this.external__checkTie(DualGovernanceState.Normal, normalOrVetoCooldownExitedAt);

        _mockSealableResumeSinceTimestampResult(_SEALABLE, type(uint256).max);

        // tiebreak is not allowed in the state different from RageQuit even when some sealable is blocked
        vm.expectRevert(Tiebreaker.TiebreakNotAllowed.selector);
        this.external__checkTie(DualGovernanceState.VetoSignalling, normalOrVetoCooldownExitedAt);

        vm.expectRevert(Tiebreaker.TiebreakNotAllowed.selector);
        this.external__checkTie(DualGovernanceState.VetoCooldown, normalOrVetoCooldownExitedAt);

        vm.expectRevert(Tiebreaker.TiebreakNotAllowed.selector);
        this.external__checkTie(DualGovernanceState.VetoSignallingDeactivation, normalOrVetoCooldownExitedAt);

        // no revert, tiebreak is allowed
        // tiebreak is allowed when some sealable is paused for a duration exceeded tiebreakerActivationTimeout
        // and the DG in the RageQuit state
        this.external__checkTie(DualGovernanceState.RageQuit, normalOrVetoCooldownExitedAt);

        // simulate tiebreaker was locked for time < tiebreakerActivationTimeout
        _mockSealableResumeSinceTimestampResult(_SEALABLE, block.timestamp + 14 days);

        // then tiebreaker activation is not allowed
        vm.expectRevert(Tiebreaker.TiebreakNotAllowed.selector);
        this.external__checkTie(DualGovernanceState.VetoSignallingDeactivation, normalOrVetoCooldownExitedAt);

        // check edge case when resumeSinceTimestamp == block.timestamp + tiebreakerActivationTimeout
        _mockSealableResumeSinceTimestampResult(_SEALABLE, block.timestamp + tiebreakerActivationTimeout.toSeconds());

        // tiebreaker activation is not allowed
        vm.expectRevert(Tiebreaker.TiebreakNotAllowed.selector);
        this.external__checkTie(DualGovernanceState.RageQuit, normalOrVetoCooldownExitedAt);

        // but when resumeSinceTimestamp  == block.timestamp + tiebreakerActivationTimeout + 1
        _mockSealableResumeSinceTimestampResult(
            _SEALABLE, block.timestamp + tiebreakerActivationTimeout.toSeconds() + 1
        );

        // tiebreaker activation is allowed
        this.external__checkTie(DualGovernanceState.RageQuit, normalOrVetoCooldownExitedAt);

        // if the DG locked for a long period of time, tiebreak becomes allowed in any state
        _wait(tiebreakerActivationTimeout);
        _mockSealableResumeSinceTimestampResult(_SEALABLE, block.timestamp);
        assertTrue(Timestamps.now() >= tiebreakerAllowedAt);

        // call does not revert
        this.external__checkTie(DualGovernanceState.VetoSignalling, normalOrVetoCooldownExitedAt);
    }

    // ---
    // checkCallerIsTiebreakerCommittee()
    // ---

    function test_checkCallerIsTiebreakerCommittee_HappyPath() external {
        context.tiebreakerCommittee = makeAddr("TIEBREAKER_COMMITTEE");

        // no revert when the call made by tiebreaker committee
        vm.prank(context.tiebreakerCommittee);
        this.external__checkCallerIsTiebreakerCommittee();
    }

    function testFuzz_checkCallerIsTiebreakerCommittee_RevertOn_NotTiebreakerCommittee(
        address caller,
        address tiebreakerCommittee
    ) external {
        vm.assume(caller != tiebreakerCommittee);

        context.tiebreakerCommittee = tiebreakerCommittee;

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.CallerIsNotTiebreakerCommittee.selector, caller));
        this.external__checkCallerIsTiebreakerCommittee();
        vm.stopPrank();
    }

    // ---
    // getTiebreakerInfo()
    // ---

    function test_getTiebreakerInfo_HappyPath() external {
        this.external__addSealableWithdrawalBlocker(_SEALABLE);

        Duration timeout = Duration.wrap(5 days);

        context.tiebreakerActivationTimeout = timeout;
        context.tiebreakerCommittee = address(0x123);

        IDualGovernance.StateDetails memory stateDetails;
        stateDetails.persistedState = DualGovernanceState.Normal;
        stateDetails.effectiveState = DualGovernanceState.VetoSignalling;
        stateDetails.normalOrVetoCooldownExitedAt = Timestamps.now();

        ITiebreaker.TiebreakerDetails memory details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], _SEALABLE);
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);
    }

    function test_getTiebreakerDetails_HappyPath_PendingTransitionFromVetoCooldown_ExpectIsTieFalse() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, _SEALABLE, 1);

        Duration timeout = Duration.wrap(5 days);

        context.tiebreakerActivationTimeout = timeout;
        context.tiebreakerCommittee = address(0x123);

        IDualGovernance.StateDetails memory stateDetails;

        stateDetails.persistedState = DualGovernanceState.VetoCooldown;
        stateDetails.effectiveState = DualGovernanceState.VetoSignalling;
        stateDetails.normalOrVetoCooldownExitedAt = Timestamps.now();

        ITiebreaker.TiebreakerDetails memory details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], _SEALABLE);
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);

        _wait(timeout);

        details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], _SEALABLE);
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);
    }

    function test_getTiebreakerDetails_HappyPath_PendingTransitionFromNormal_ExpectIsTieFalse() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, _SEALABLE, 1);

        Duration timeout = Duration.wrap(5 days);

        context.tiebreakerActivationTimeout = timeout;
        context.tiebreakerCommittee = address(0x123);

        IDualGovernance.StateDetails memory stateDetails;

        stateDetails.persistedState = DualGovernanceState.Normal;
        stateDetails.effectiveState = DualGovernanceState.VetoSignalling;
        stateDetails.normalOrVetoCooldownExitedAt = Timestamps.now();

        ITiebreaker.TiebreakerDetails memory details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], _SEALABLE);
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);

        _wait(timeout);

        details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], _SEALABLE);
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);
    }

    function test_getTiebreakerDetails_HappyPath_PendingTransitionFromVetoSignalling_ExpectIsTieTrue() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, _SEALABLE, 1);

        Duration timeout = Duration.wrap(5 days);

        context.tiebreakerActivationTimeout = timeout;
        context.tiebreakerCommittee = address(0x123);

        IDualGovernance.StateDetails memory stateDetails;

        stateDetails.persistedState = DualGovernanceState.VetoSignalling;
        stateDetails.effectiveState = DualGovernanceState.RageQuit;
        stateDetails.normalOrVetoCooldownExitedAt = Timestamps.now();

        ITiebreaker.TiebreakerDetails memory details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], _SEALABLE);
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);

        _wait(timeout);

        details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], _SEALABLE);
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, true);
    }

    function external__checkCallerIsTiebreakerCommittee() external view {
        context.checkCallerIsTiebreakerCommittee();
    }

    // overloaded method, to not pass limit parameter each time in the tests
    function external__addSealableWithdrawalBlocker(address sealable) external {
        context.addSealableWithdrawalBlocker(sealable, type(uint256).max);
    }

    function external__addSealableWithdrawalBlocker(
        address sealable,
        uint256 maxSealableWithdrawalBlockersCount
    ) external {
        context.addSealableWithdrawalBlocker(sealable, maxSealableWithdrawalBlockersCount);
    }

    function external__removeSealableWithdrawalBlocker(address sealable) external {
        context.removeSealableWithdrawalBlocker(sealable);
    }

    function external__setTiebreakerCommittee(address newTiebreakerCommittee) external {
        context.setTiebreakerCommittee(newTiebreakerCommittee);
    }

    function external__setTiebreakerActivationTimeout(
        Duration minTimeout,
        Duration timeout,
        Duration maxTimeout
    ) external {
        context.setTiebreakerActivationTimeout(minTimeout, timeout, maxTimeout);
    }

    function external__setTiebreakerActivationTimeout(Duration timeout) external {
        context.setTiebreakerActivationTimeout(Durations.from(0), timeout, Durations.from(365 days));
    }

    function external__checkTie(DualGovernanceState dgState, Timestamp normalOrVetoCooldownExitedAt) external {
        context.checkTie(dgState, normalOrVetoCooldownExitedAt);
    }

    // ---
    // Internal Testing Helper Methods
    // ---

    function _mockSealableResumeSinceTimestampResult(address sealable, uint256 resumeSinceTimestamp) internal {
        vm.mockCall(
            sealable,
            abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector),
            abi.encode(resumeSinceTimestamp)
        );
    }

    function _mockSealableResumeSinceTimestampReverts(address sealable, bytes memory revertReason) internal {
        vm.mockCallRevert(sealable, abi.encodeWithSelector(ISealable.getResumeSinceTimestamp.selector), revertReason);
    }
}
