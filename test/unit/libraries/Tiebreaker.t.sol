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
import {SealableMock} from "../../mocks/SealableMock.sol";

contract TiebreakerTest is UnitTest {
    using EnumerableSet for EnumerableSet.AddressSet;

    Tiebreaker.Context private context;
    SealableMock private mockSealable1;
    SealableMock private mockSealable2;

    function setUp() external {
        mockSealable1 = new SealableMock();
        mockSealable2 = new SealableMock();
    }

    function test_addSealableWithdrawalBlocker_HappyPath() external {
        vm.expectEmit();
        emit Tiebreaker.SealableWithdrawalBlockerAdded(address(mockSealable1));
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 1);

        assertTrue(context.sealableWithdrawalBlockers.contains(address(mockSealable1)));
    }

    function test_addSealableWithdrawalBlocker_RevertOn_LimitReached() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 1);

        vm.expectRevert(Tiebreaker.SealableWithdrawalBlockersLimitReached.selector);
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable2), 1);
    }

    function test_addSealableWithdrawalBlocker_RevertOn_AlreadyAdded() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 2);

        vm.expectRevert(
            abi.encodeWithSelector(Tiebreaker.SealableWithdrawalBlockerAlreadyAdded.selector, address(mockSealable1))
        );
        this.external__addSealableWithdrawalBlocker(address(mockSealable1), 2);
    }

    function test_addSealableWithdrawalBlocker_RevertOn_InvalidSealable() external {
        mockSealable1.setShouldRevertIsPaused(true);

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidSealable.selector, address(mockSealable1)));
        // external call should be used to intercept the revert
        this.external__addSealableWithdrawalBlocker(address(mockSealable1), 2);

        vm.expectRevert();
        // external call should be used to intercept the revert
        this.external__addSealableWithdrawalBlocker(address(0x123), 2);
    }

    function test_removeSealableWithdrawalBlocker_HappyPath() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 1);
        assertTrue(context.sealableWithdrawalBlockers.contains(address(mockSealable1)));

        vm.expectEmit();
        emit Tiebreaker.SealableWithdrawalBlockerRemoved(address(mockSealable1));

        Tiebreaker.removeSealableWithdrawalBlocker(context, address(mockSealable1));
        assertFalse(context.sealableWithdrawalBlockers.contains(address(mockSealable1)));
    }

    function test_removeSealableWithdrawalBlocker_RevertOn_NotFound() external {
        vm.expectRevert(
            abi.encodeWithSelector(Tiebreaker.SealableWithdrawalBlockerNotFound.selector, address(mockSealable1))
        );
        this.external__removeSealableWithdrawalBlocker(address(mockSealable1));
    }

    function test_setTiebreakerCommittee_HappyPath() external {
        address newCommittee = address(0x123);

        vm.expectEmit();
        emit Tiebreaker.TiebreakerCommitteeSet(newCommittee);
        Tiebreaker.setTiebreakerCommittee(context, newCommittee);

        assertEq(context.tiebreakerCommittee, newCommittee);
    }

    function test_setTiebreakerCommittee_WithExistingCommitteeAddress() external {
        address newCommittee = address(0x123);

        Tiebreaker.setTiebreakerCommittee(context, newCommittee);
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerCommittee.selector, newCommittee));
        Tiebreaker.setTiebreakerCommittee(context, newCommittee);
    }

    function test_setTiebreakerCommittee_RevertOn_ZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerCommittee.selector, address(0)));
        Tiebreaker.setTiebreakerCommittee(context, address(0));
    }

    function testFuzz_SetTiebreakerActivationTimeout(
        Duration minTimeout,
        Duration maxTimeout,
        Duration timeout
    ) external {
        vm.assume(minTimeout < timeout && timeout < maxTimeout);

        vm.expectEmit();
        emit Tiebreaker.TiebreakerActivationTimeoutSet(timeout);

        Tiebreaker.setTiebreakerActivationTimeout(context, minTimeout, timeout, timeout);
        assertEq(context.tiebreakerActivationTimeout, timeout);
    }

    function test_setTiebreakerActivationTimeout_RevertOn_InvalidTimeout() external {
        Duration minTimeout = Duration.wrap(1 days);
        Duration maxTimeout = Duration.wrap(10 days);
        Duration newTimeout = Duration.wrap(15 days);

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerActivationTimeout.selector, newTimeout));
        Tiebreaker.setTiebreakerActivationTimeout(context, minTimeout, newTimeout, maxTimeout);

        newTimeout = Duration.wrap(0 days);

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.InvalidTiebreakerActivationTimeout.selector, newTimeout));
        Tiebreaker.setTiebreakerActivationTimeout(context, minTimeout, newTimeout, maxTimeout);
    }

    function test_isSomeSealableWithdrawalBlockerPaused_HappyPath() external {
        mockSealable1.pauseFor(1 days);
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 2);

        bool result = Tiebreaker.isSomeSealableWithdrawalBlockerPaused(context);
        assertTrue(result);

        mockSealable1.resume();

        result = Tiebreaker.isSomeSealableWithdrawalBlockerPaused(context);
        assertFalse(result);

        mockSealable1.setShouldRevertIsPaused(true);

        result = Tiebreaker.isSomeSealableWithdrawalBlockerPaused(context);
        assertTrue(result);
    }

    function test_checkTie_HappyPath() external {
        Timestamp cooldownExitedAt = Timestamps.from(block.timestamp);

        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 1);
        Tiebreaker.setTiebreakerActivationTimeout(
            context, Duration.wrap(1 days), Duration.wrap(3 days), Duration.wrap(10 days)
        );

        mockSealable1.pauseFor(1 days);
        Tiebreaker.checkTie(context, DualGovernanceState.RageQuit, cooldownExitedAt);

        _wait(Duration.wrap(3 days));
        Tiebreaker.checkTie(context, DualGovernanceState.VetoSignalling, cooldownExitedAt);
    }

    function test_checkTie_RevertOn_NormalOrVetoCooldownState() external {
        Timestamp cooldownExitedAt = Timestamps.from(block.timestamp);

        vm.expectRevert(Tiebreaker.TiebreakNotAllowed.selector);
        Tiebreaker.checkTie(context, DualGovernanceState.Normal, cooldownExitedAt);

        vm.expectRevert(Tiebreaker.TiebreakNotAllowed.selector);
        Tiebreaker.checkTie(context, DualGovernanceState.VetoCooldown, cooldownExitedAt);
    }

    function test_checkCallerIsTiebreakerCommittee_HappyPath() external {
        context.tiebreakerCommittee = address(this);

        vm.expectRevert(abi.encodeWithSelector(Tiebreaker.CallerIsNotTiebreakerCommittee.selector, address(0x456)));
        vm.prank(address(0x456));
        this.external__checkCallerIsTiebreakerCommittee();

        this.external__checkCallerIsTiebreakerCommittee();
    }

    function test_getTimebreakerInfo_HappyPath() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 1);

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
        assertEq(details.sealableWithdrawalBlockers[0], address(mockSealable1));
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);
    }

    function test_getTiebreakerDetails_HappyPath_PendingTransitionFromVetoCooldown_ExpectIsTieFalse() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 1);

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
        assertEq(details.sealableWithdrawalBlockers[0], address(mockSealable1));
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);

        _wait(timeout);

        details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], address(mockSealable1));
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);
    }

    function test_getTiebreakerDetails_HappyPath_PendingTransitionFromNormal_ExpectIsTieFalse() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 1);

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
        assertEq(details.sealableWithdrawalBlockers[0], address(mockSealable1));
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);

        _wait(timeout);

        details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], address(mockSealable1));
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);
    }

    function test_getTiebreakerDetails_HappyPath_PendingTransitionFromVetoSignalling_ExpectIsTieTrue() external {
        Tiebreaker.addSealableWithdrawalBlocker(context, address(mockSealable1), 1);

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
        assertEq(details.sealableWithdrawalBlockers[0], address(mockSealable1));
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, false);

        _wait(timeout);

        details = Tiebreaker.getTiebreakerDetails(context, stateDetails);

        assertEq(details.tiebreakerCommittee, context.tiebreakerCommittee);
        assertEq(details.tiebreakerActivationTimeout, context.tiebreakerActivationTimeout);
        assertEq(details.sealableWithdrawalBlockers[0], address(mockSealable1));
        assertEq(details.sealableWithdrawalBlockers.length, 1);
        assertEq(details.isTie, true);
    }

    function external__checkCallerIsTiebreakerCommittee() external view {
        Tiebreaker.checkCallerIsTiebreakerCommittee(context);
    }

    function external__addSealableWithdrawalBlocker(address sealable, uint256 count) external {
        Tiebreaker.addSealableWithdrawalBlocker(context, sealable, count);
    }

    function external__removeSealableWithdrawalBlocker(address sealable) external {
        Tiebreaker.removeSealableWithdrawalBlocker(context, sealable);
    }
}
