// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";
import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract EmergencyProtectionTest is UnitTest {
    EmergencyProtection.Context ctx;

    address emergencyGovernance = address(0x1);
    address emergencyActivationCommittee = address(0x2);
    address emergencyExecutionCommittee = address(0x3);

    function setUp() external {
        // Setup initial values
        ctx.emergencyGovernance = emergencyGovernance;
        ctx.emergencyActivationCommittee = emergencyActivationCommittee;
        ctx.emergencyExecutionCommittee = emergencyExecutionCommittee;
        ctx.emergencyModeDuration = Duration.wrap(3600);
        ctx.emergencyProtectionEndsAfter = Timestamps.from(block.timestamp + 86400);
    }

    function test_ActivateEmergencyMode() external {
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeActivated(Timestamps.now());
        EmergencyProtection.activateEmergencyMode(ctx);

        assertTrue(EmergencyProtection.isEmergencyModeActive(ctx));
        assertEq(Timestamp.unwrap(ctx.emergencyModeEndsAfter), block.timestamp + 3600);
    }

    function test_ActivateEmergencyMode_RevertOn_ProtectionExpired() external {
        Duration untilExpiration =
            Durations.between(ctx.emergencyProtectionEndsAfter, Timestamps.from(block.timestamp)).plusSeconds(1);

        _wait(untilExpiration);

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.EmergencyProtectionExpired.selector, ctx.emergencyProtectionEndsAfter
            )
        );
        EmergencyProtection.activateEmergencyMode(ctx);
    }

    function test_DeactivateEmergencyMode() external {
        EmergencyProtection.activateEmergencyMode(ctx);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDeactivated(Timestamps.now());
        EmergencyProtection.deactivateEmergencyMode(ctx);

        assertFalse(EmergencyProtection.isEmergencyModeActive(ctx));
        assertEq(ctx.emergencyActivationCommittee, address(0));
        assertEq(ctx.emergencyExecutionCommittee, address(0));
        assertEq(Timestamp.unwrap(ctx.emergencyProtectionEndsAfter), 0);
        assertEq(Timestamp.unwrap(ctx.emergencyModeEndsAfter), 0);
        assertEq(Duration.unwrap(ctx.emergencyModeDuration), 0);
    }

    function test_SetEmergencyGovernance() external {
        address newGovernance = address(0x4);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyGovernanceSet(newGovernance);
        EmergencyProtection.setEmergencyGovernance(ctx, newGovernance);

        assertEq(ctx.emergencyGovernance, newGovernance);
    }

    function test_SetEmergencyGovernance_RevertOn_SameAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyGovernance.selector, emergencyGovernance)
        );
        EmergencyProtection.setEmergencyGovernance(ctx, emergencyGovernance);
    }

    function test_SetEmergencyProtectionEndDate() external {
        Timestamp newEndDate = Timestamps.from(block.timestamp + 43200);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyProtectionEndDateSet(newEndDate);
        EmergencyProtection.setEmergencyProtectionEndDate(ctx, newEndDate, Duration.wrap(86400));

        assertEq(Timestamp.unwrap(ctx.emergencyProtectionEndsAfter), block.timestamp + 43200);
    }

    function test_SetEmergencyProtectionEndDate_RevertOn_InvalidValue() external {
        Timestamp invalidEndDate = Timestamps.from(block.timestamp + 90000);

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyProtectionEndDate.selector, invalidEndDate)
        );
        EmergencyProtection.setEmergencyProtectionEndDate(ctx, invalidEndDate, Duration.wrap(86400));

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.InvalidEmergencyProtectionEndDate.selector, ctx.emergencyProtectionEndsAfter
            )
        );
        EmergencyProtection.setEmergencyProtectionEndDate(ctx, ctx.emergencyProtectionEndsAfter, Duration.wrap(86400));
    }

    function test_SetEmergencyModeDuration() external {
        Duration newDuration = Duration.wrap(7200);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(newDuration);
        EmergencyProtection.setEmergencyModeDuration(ctx, newDuration, Duration.wrap(86400));

        assertEq(Duration.unwrap(ctx.emergencyModeDuration), 7200);
    }

    function test_SetEmergencyModeDuration_RevertOn_InvalidValue() external {
        Duration invalidDuration = Duration.wrap(90000);

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeDuration.selector, invalidDuration)
        );
        EmergencyProtection.setEmergencyModeDuration(ctx, invalidDuration, Duration.wrap(86400));

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeDuration.selector, ctx.emergencyModeDuration)
        );
        EmergencyProtection.setEmergencyModeDuration(ctx, ctx.emergencyModeDuration, Duration.wrap(86400));
    }

    function test_CheckCallerIsEmergencyActivationCommittee() external {
        vm.prank(emergencyActivationCommittee);
        this.external__checkCallerIsEmergencyActivationCommittee();
    }

    function test_CheckCallerIsEmergencyActivationCommittee_RevertOn_Stranger() external {
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyActivationCommittee.selector, address(0x5))
        );
        vm.prank(address(0x5));
        this.external__checkCallerIsEmergencyActivationCommittee();
    }

    function test_CheckCallerIsEmergencyExecutionCommittee() external {
        vm.prank(emergencyExecutionCommittee);
        this.external__checkCallerIsEmergencyExecutionCommittee();
    }

    function test_CheckCallerIsEmergencyExecutionCommittee_RevertOn_Stranger() external {
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyExecutionCommittee.selector, address(0x5))
        );
        vm.prank(address(0x5));
        this.external__checkCallerIsEmergencyExecutionCommittee();
    }

    function test_CheckEmergencyMode() external {
        EmergencyProtection.activateEmergencyMode(ctx);
        EmergencyProtection.checkEmergencyMode(ctx, true);
    }

    function test_CheckEmergencyMode_RevertOn_NotInEmergencyMode() external {
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
        EmergencyProtection.checkEmergencyMode(ctx, true);
    }

    function test_IsEmergencyModeActive() public {
        assertFalse(EmergencyProtection.isEmergencyModeActive(ctx));
        EmergencyProtection.activateEmergencyMode(ctx);
        assertTrue(EmergencyProtection.isEmergencyModeActive(ctx));
    }

    function test_IsEmergencyModeDurationPassed() public {
        assertFalse(EmergencyProtection.isEmergencyModeDurationPassed(ctx));
        EmergencyProtection.activateEmergencyMode(ctx);
        assertFalse(EmergencyProtection.isEmergencyModeDurationPassed(ctx));

        Duration untilExpiration =
            Durations.between(ctx.emergencyModeEndsAfter, Timestamps.from(block.timestamp)).plusSeconds(1);
        _wait(untilExpiration);

        assertTrue(EmergencyProtection.isEmergencyModeDurationPassed(ctx));
    }

    function test_IsEmergencyProtectionEnabled() public {
        assertTrue(EmergencyProtection.isEmergencyProtectionEnabled(ctx));

        Duration untilExpiration =
            Durations.between(ctx.emergencyProtectionEndsAfter, Timestamps.from(block.timestamp)).plusSeconds(1);
        _wait(untilExpiration);

        assertFalse(EmergencyProtection.isEmergencyProtectionEnabled(ctx));
    }

    function test_IsEmergencyProtectionEnabled_WhenEmergencyModeActive() public {
        assertTrue(EmergencyProtection.isEmergencyProtectionEnabled(ctx));
        EmergencyProtection.activateEmergencyMode(ctx);
        assertTrue(EmergencyProtection.isEmergencyProtectionEnabled(ctx));

        Duration untilExpiration =
            Durations.between(ctx.emergencyModeEndsAfter, Timestamps.from(block.timestamp)).plusSeconds(1);
        _wait(untilExpiration);

        assertTrue(EmergencyProtection.isEmergencyProtectionEnabled(ctx));

        untilExpiration =
            Durations.between(ctx.emergencyProtectionEndsAfter, Timestamps.from(block.timestamp)).plusSeconds(1);

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
}
