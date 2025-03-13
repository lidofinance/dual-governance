// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";
import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract EmergencyProtectionTest is UnitTest {
    using EmergencyProtection for EmergencyProtection.Context;

    EmergencyProtection.Context private ctx;

    address private emergencyGovernance = address(0x1);
    address private emergencyActivationCommittee = address(0x2);
    address private emergencyExecutionCommittee = address(0x3);

    function setUp() external {
        // Setup initial values
        ctx.emergencyGovernance = emergencyGovernance;
        ctx.emergencyActivationCommittee = emergencyActivationCommittee;
        ctx.emergencyExecutionCommittee = emergencyExecutionCommittee;
        ctx.emergencyModeDuration = Duration.wrap(3600);
        ctx.emergencyProtectionEndsAfter = Timestamps.from(block.timestamp + 86400);
    }

    function test_activateEmergencyMode_HappyPath() external {
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeActivated();
        EmergencyProtection.activateEmergencyMode(ctx);

        assertTrue(EmergencyProtection.isEmergencyModeActive(ctx));
        assertEq(Timestamp.unwrap(ctx.emergencyModeEndsAfter), block.timestamp + 3600);
    }

    function test_activateEmergencyMode_RevertOn_ProtectionExpired() external {
        Duration untilExpiration =
            Durations.from(ctx.emergencyProtectionEndsAfter.toSeconds() - Timestamps.now().toSeconds()).plusSeconds(1);

        _wait(untilExpiration);

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.EmergencyProtectionExpired.selector, ctx.emergencyProtectionEndsAfter
            )
        );
        this.external__activateEmergencyMode();
    }

    function test_deactivateEmergencyMode_HappyPath() external {
        EmergencyProtection.activateEmergencyMode(ctx);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDeactivated();
        EmergencyProtection.deactivateEmergencyMode(ctx);

        assertFalse(EmergencyProtection.isEmergencyModeActive(ctx));
        assertEq(ctx.emergencyActivationCommittee, address(0));
        assertEq(ctx.emergencyExecutionCommittee, address(0));
        assertEq(Timestamp.unwrap(ctx.emergencyProtectionEndsAfter), 0);
        assertEq(Timestamp.unwrap(ctx.emergencyModeEndsAfter), 0);
        assertEq(Duration.unwrap(ctx.emergencyModeDuration), 0);
    }

    function test_setEmergencyGovernance_HappyPath() external {
        address newGovernance = address(0x4);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyGovernanceSet(newGovernance);
        EmergencyProtection.setEmergencyGovernance(ctx, newGovernance);

        assertEq(ctx.emergencyGovernance, newGovernance);
    }

    function test_setEmergencyGovernance_RevertOn_SameAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyGovernance.selector, emergencyGovernance)
        );
        this.external__setEmergencyGovernance(emergencyGovernance);
    }

    function test_setEmergencyProtectionEndDate_HappyPath() external {
        Timestamp newEndDate = Timestamps.from(block.timestamp + 43200);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyProtectionEndDateSet(newEndDate);
        EmergencyProtection.setEmergencyProtectionEndDate(ctx, newEndDate, Duration.wrap(86400));

        assertEq(Timestamp.unwrap(ctx.emergencyProtectionEndsAfter), block.timestamp + 43200);
    }

    function test_setEmergencyProtectionEndDate_RevertOn_InvalidValue() external {
        Timestamp invalidEndDate = Timestamps.from(block.timestamp + 90000);

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyProtectionEndDate.selector, invalidEndDate)
        );
        this.external__setEmergencyProtectionEndDate(invalidEndDate, Duration.wrap(86400));

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.InvalidEmergencyProtectionEndDate.selector, ctx.emergencyProtectionEndsAfter
            )
        );
        this.external__setEmergencyProtectionEndDate(ctx.emergencyProtectionEndsAfter, Duration.wrap(86400));
    }

    function test_setEmergencyModeDuration() external {
        Duration newDuration = Duration.wrap(7200);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(newDuration);
        EmergencyProtection.setEmergencyModeDuration(ctx, newDuration, Duration.wrap(86400));

        assertEq(Duration.unwrap(ctx.emergencyModeDuration), 7200);
    }

    function test_setEmergencyModeDuration_RevertOn_InvalidValue() external {
        Duration invalidDuration = Duration.wrap(90000);

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeDuration.selector, invalidDuration)
        );
        this.external__setEmergencyModeDuration(invalidDuration, Duration.wrap(86400));

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeDuration.selector, ctx.emergencyModeDuration)
        );
        this.external__setEmergencyModeDuration(ctx.emergencyModeDuration, Duration.wrap(86400));
    }

    function testFuzz_setEmergencyActivationCommittee_HappyPath(address committee) external {
        vm.assume(committee != emergencyActivationCommittee);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(committee);

        EmergencyProtection.setEmergencyActivationCommittee(ctx, committee);
    }

    function test_setEmergencyActivationCommittee_RevertOn_SameAddress() external {
        address committee = address(0x123);
        EmergencyProtection.setEmergencyActivationCommittee(ctx, committee);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyActivationCommittee.selector, committee)
        );
        this.external__setEmergencyActivationCommittee(committee);
    }

    function testFuzz_setEmergencyExecutionCommittee_HappyPath(address committee) external {
        vm.assume(committee != emergencyExecutionCommittee);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(committee);

        EmergencyProtection.setEmergencyExecutionCommittee(ctx, committee);
    }

    function test_setEmergencyExecutionCommittee_RevertOn_SameAddress() external {
        address committee = address(0x123);
        EmergencyProtection.setEmergencyExecutionCommittee(ctx, committee);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyExecutionCommittee.selector, committee)
        );
        this.external__setEmergencyExecutionCommittee(committee);
    }

    function test_checkCallerIsEmergencyActivationCommittee_HappyPath() external {
        vm.prank(emergencyActivationCommittee);
        this.external__checkCallerIsEmergencyActivationCommittee();
    }

    function test_checkCallerIsEmergencyActivationCommittee_RevertOn_Stranger() external {
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyActivationCommittee.selector, address(0x5))
        );
        vm.prank(address(0x5));
        this.external__checkCallerIsEmergencyActivationCommittee();
    }

    function test_checkCallerIsEmergencyExecutionCommittee_HappyPath() external {
        vm.prank(emergencyExecutionCommittee);
        this.external__checkCallerIsEmergencyExecutionCommittee();
    }

    function test_checkCallerIsEmergencyExecutionCommittee_RevertOn_Stranger() external {
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyExecutionCommittee.selector, address(0x5))
        );
        vm.prank(address(0x5));
        this.external__checkCallerIsEmergencyExecutionCommittee();
    }

    function test_checkEmergencyMode_HappyPath() external {
        EmergencyProtection.activateEmergencyMode(ctx);
        EmergencyProtection.checkEmergencyMode(ctx, true);
    }

    function test_checkEmergencyMode_RevertOn_NotInEmergencyMode() external {
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
        this.external__checkEmergencyMode(true);
    }

    function test_isEmergencyModeActive_HappyPath() public {
        assertFalse(EmergencyProtection.isEmergencyModeActive(ctx));
        EmergencyProtection.activateEmergencyMode(ctx);
        assertTrue(EmergencyProtection.isEmergencyModeActive(ctx));
    }

    function test_isEmergencyModeDurationPassed_HappyPath() public {
        assertFalse(EmergencyProtection.isEmergencyModeDurationPassed(ctx));
        EmergencyProtection.activateEmergencyMode(ctx);
        assertFalse(EmergencyProtection.isEmergencyModeDurationPassed(ctx));

        Duration untilExpiration =
            Durations.from(ctx.emergencyModeEndsAfter.toSeconds() - Timestamps.now().toSeconds()).plusSeconds(1);
        _wait(untilExpiration);

        assertTrue(EmergencyProtection.isEmergencyModeDurationPassed(ctx));
    }

    function test_isEmergencyProtectionEnabled_HappyPath() public {
        assertTrue(EmergencyProtection.isEmergencyProtectionEnabled(ctx));

        Duration untilExpiration =
            Durations.from(ctx.emergencyProtectionEndsAfter.toSeconds() - Timestamps.now().toSeconds()).plusSeconds(1);
        _wait(untilExpiration);

        assertFalse(EmergencyProtection.isEmergencyProtectionEnabled(ctx));
    }

    function test_isEmergencyProtectionEnabled_WhenEmergencyModeActive() public {
        assertTrue(EmergencyProtection.isEmergencyProtectionEnabled(ctx));
        EmergencyProtection.activateEmergencyMode(ctx);
        assertTrue(EmergencyProtection.isEmergencyProtectionEnabled(ctx));

        Duration untilExpiration =
            Durations.from(ctx.emergencyModeEndsAfter.toSeconds() - Timestamps.now().toSeconds()).plusSeconds(1);
        _wait(untilExpiration);

        assertTrue(EmergencyProtection.isEmergencyProtectionEnabled(ctx));

        untilExpiration =
            Durations.from(ctx.emergencyProtectionEndsAfter.toSeconds() - Timestamps.now().toSeconds()).plusSeconds(1);

        assertTrue(EmergencyProtection.isEmergencyProtectionEnabled(ctx));

        EmergencyProtection.deactivateEmergencyMode(ctx);

        assertFalse(EmergencyProtection.isEmergencyProtectionEnabled(ctx));
    }

    function external__checkCallerIsEmergencyActivationCommittee() external view {
        EmergencyProtection.checkCallerIsEmergencyActivationCommittee(ctx);
    }

    function external__checkCallerIsEmergencyExecutionCommittee() external view {
        EmergencyProtection.checkCallerIsEmergencyExecutionCommittee(ctx);
    }

    function external__activateEmergencyMode() external {
        ctx.activateEmergencyMode();
    }

    function external__setEmergencyGovernance(address newEmergencyGovernance) external {
        ctx.setEmergencyGovernance(newEmergencyGovernance);
    }

    function external__setEmergencyProtectionEndDate(
        Timestamp newEmergencyProtectionEndDate,
        Duration maxEmergencyProtectionDuration
    ) external {
        ctx.setEmergencyProtectionEndDate(newEmergencyProtectionEndDate, maxEmergencyProtectionDuration);
    }

    function external__setEmergencyModeDuration(
        Duration newEmergencyModeDuration,
        Duration maxEmergencyModeDuration
    ) external {
        ctx.setEmergencyModeDuration(newEmergencyModeDuration, maxEmergencyModeDuration);
    }

    function external__setEmergencyActivationCommittee(address newActivationCommittee) external {
        ctx.setEmergencyActivationCommittee(newActivationCommittee);
    }

    function external__setEmergencyExecutionCommittee(address newExecutionCommittee) external {
        ctx.setEmergencyExecutionCommittee(newExecutionCommittee);
    }

    function external__checkEmergencyMode(bool isActive) external view {
        ctx.checkEmergencyMode(isActive);
    }
}
