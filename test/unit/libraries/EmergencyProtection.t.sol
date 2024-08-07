// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract EmergencyProtectionUnitTests is UnitTest {
    using EmergencyProtection for EmergencyProtection.Context;

    address internal _emergencyGovernance = makeAddr("EMERGENCY_GOVERNANCE");

    EmergencyProtection.Context internal _emergencyProtection;

    function testFuzz_setup_emergency_protection(
        address activationCommittee,
        address executionCommittee,
        address emergencyGovernance,
        Duration protectionDuration,
        Duration duration
    ) external {
        vm.assume(protectionDuration > Durations.ZERO);
        vm.assume(duration > Durations.ZERO);
        // vm.assume(activationCommittee != address(0));
        // vm.assume(executionCommittee != address(0));
        uint256 expectedLogEntiresCount = 2;
        if (emergencyGovernance != address(0)) {
            vm.expectEmit();
            emit EmergencyProtection.EmergencyGovernanceSet(emergencyGovernance);
            expectedLogEntiresCount += 1;
        }

        if (activationCommittee != address(0)) {
            vm.expectEmit();
            emit EmergencyProtection.EmergencyActivationCommitteeSet(activationCommittee);
            expectedLogEntiresCount += 1;
        }
        if (executionCommittee != address(0)) {
            vm.expectEmit();
            emit EmergencyProtection.EmergencyExecutionCommitteeSet(executionCommittee);
            expectedLogEntiresCount += 1;
        }
        vm.expectEmit();
        emit EmergencyProtection.EmergencyProtectionEndDateSet(protectionDuration.addTo(Timestamps.now()));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(duration);

        vm.recordLogs();

        _setup(emergencyGovernance, activationCommittee, executionCommittee, protectionDuration, duration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, expectedLogEntiresCount);

        assertEq(_emergencyProtection.emergencyGovernance, emergencyGovernance);
        assertEq(_emergencyProtection.emergencyActivationCommittee, activationCommittee);
        assertEq(_emergencyProtection.emergencyExecutionCommittee, executionCommittee);
        assertEq(_emergencyProtection.emergencyProtectionEndsAfter, protectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, duration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_setup_same_activation_committee() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);
        address activationCommittee = makeAddr("activationCommittee");

        _setup(_emergencyGovernance, activationCommittee, address(0x2), protectionDuration, emergencyModeDuration);

        Duration newProtectionDuration = Durations.from(200 seconds);
        Duration newEmergencyModeDuration = Durations.from(300 seconds);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyProtectionEndDateSet(newProtectionDuration.addTo(Timestamps.now()));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(newEmergencyModeDuration);

        vm.recordLogs();
        _setup(_emergencyGovernance, activationCommittee, address(0x3), newProtectionDuration, newEmergencyModeDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.emergencyActivationCommittee, activationCommittee);
        assertEq(_emergencyProtection.emergencyExecutionCommittee, address(0x3));
        assertEq(_emergencyProtection.emergencyProtectionEndsAfter, newProtectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, newEmergencyModeDuration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_setup_same_execution_committee() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);
        address executionCommittee = makeAddr("executionCommittee");

        _setup(_emergencyGovernance, address(0x1), executionCommittee, protectionDuration, emergencyModeDuration);

        Duration newProtectionDuration = Durations.from(200 seconds);
        Duration newEmergencyModeDuration = Durations.from(300 seconds);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x2));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyProtectionEndDateSet(newProtectionDuration.addTo(Timestamps.now()));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(newEmergencyModeDuration);

        vm.recordLogs();
        _setup(_emergencyGovernance, address(0x2), executionCommittee, newProtectionDuration, newEmergencyModeDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.emergencyActivationCommittee, address(0x2));
        assertEq(_emergencyProtection.emergencyExecutionCommittee, executionCommittee);
        assertEq(_emergencyProtection.emergencyProtectionEndsAfter, newProtectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, newEmergencyModeDuration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_setup_same_protected_till() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _setup(_emergencyGovernance, address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        Duration newProtectionDuration = protectionDuration; // the new value is the same as previous one
        Duration newEmergencyModeDuration = Durations.from(200 seconds);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x4));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(newEmergencyModeDuration);

        vm.recordLogs();
        _setup(_emergencyGovernance, address(0x3), address(0x4), newProtectionDuration, newEmergencyModeDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.emergencyActivationCommittee, address(0x3));
        assertEq(_emergencyProtection.emergencyExecutionCommittee, address(0x4));
        assertEq(_emergencyProtection.emergencyProtectionEndsAfter, protectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, newEmergencyModeDuration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_setup_same_emergency_mode_duration() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _setup(_emergencyGovernance, address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        Duration newProtectionDuration = Durations.from(200 seconds);
        Duration newEmergencyModeDuration = emergencyModeDuration; // the new value is the same as previous one

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x4));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyProtectionEndDateSet(newProtectionDuration.addTo(Timestamps.now()));

        vm.recordLogs();
        _setup(_emergencyGovernance, address(0x3), address(0x4), newProtectionDuration, newEmergencyModeDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.emergencyActivationCommittee, address(0x3));
        assertEq(_emergencyProtection.emergencyExecutionCommittee, address(0x4));
        assertEq(_emergencyProtection.emergencyProtectionEndsAfter, newProtectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, newEmergencyModeDuration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_activate_emergency_mode() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _setup(_emergencyGovernance, address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeActivated();

        vm.recordLogs();

        _emergencyProtection.activateEmergencyMode();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, emergencyModeDuration.addTo(Timestamps.now()));
    }

    function test_cannot_activate_emergency_mode_if_protected_till_expired() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _setup(_emergencyGovernance, address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        _wait(protectionDuration.plusSeconds(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.EmergencyProtectionExpired.selector,
                _emergencyProtection.emergencyProtectionEndsAfter
            )
        );
        _emergencyProtection.activateEmergencyMode();
    }

    function testFuzz_deactivate_emergency_mode(
        address activationCommittee,
        address executionCommittee,
        Duration protectionDuration,
        Duration emergencyModeDuration
    ) external {
        vm.assume(activationCommittee != address(0));
        vm.assume(executionCommittee != address(0));

        _setup(_emergencyGovernance, activationCommittee, executionCommittee, protectionDuration, emergencyModeDuration);
        _emergencyProtection.activateEmergencyMode();

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDeactivated();

        vm.recordLogs();

        _emergencyProtection.deactivateEmergencyMode();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);

        assertEq(_emergencyProtection.emergencyActivationCommittee, address(0));
        assertEq(_emergencyProtection.emergencyExecutionCommittee, address(0));
        assertEq(_emergencyProtection.emergencyProtectionEndsAfter, Timestamps.ZERO);
        assertEq(_emergencyProtection.emergencyModeDuration, Durations.ZERO);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_is_emergency_mode_activated() external {
        assertEq(_emergencyProtection.isEmergencyModeActive(), false);

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _setup(_emergencyGovernance, address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        assertEq(_emergencyProtection.isEmergencyModeActive(), false);

        _emergencyProtection.activateEmergencyMode();

        assertEq(_emergencyProtection.isEmergencyModeActive(), true);

        _emergencyProtection.deactivateEmergencyMode();

        assertEq(_emergencyProtection.isEmergencyModeActive(), false);
    }

    function test_is_emergency_mode_passed() external {
        assertEq(_emergencyProtection.isEmergencyModeDurationPassed(), false);

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(200 seconds);

        _setup(_emergencyGovernance, address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        assertEq(_emergencyProtection.isEmergencyModeDurationPassed(), false);

        _emergencyProtection.activateEmergencyMode();

        assertEq(_emergencyProtection.isEmergencyModeDurationPassed(), false);

        _wait(emergencyModeDuration.plusSeconds(1));

        assertEq(_emergencyProtection.isEmergencyModeDurationPassed(), true);

        _emergencyProtection.deactivateEmergencyMode();

        assertEq(_emergencyProtection.isEmergencyModeDurationPassed(), false);
    }

    function test_is_emergency_protection_enabled() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(200 seconds);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), false);

        _setup(_emergencyGovernance, address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), true);

        EmergencyProtection.Context memory emergencyState = _emergencyProtection;

        _wait(Durations.between(emergencyState.emergencyProtectionEndsAfter, Timestamps.now()));

        // _wait(emergencyState.emergencyProtectionEndsAfter.absDiff(Timestamps.now()));

        EmergencyProtection.activateEmergencyMode(_emergencyProtection);

        _wait(emergencyModeDuration);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), true);

        _wait(protectionDuration);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), true);

        EmergencyProtection.deactivateEmergencyMode(_emergencyProtection);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), false);
    }

    function testFuzz_check_activation_committee(address committee, address stranger) external {
        vm.assume(committee != address(0));
        vm.assume(stranger != address(0) && stranger != committee);

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyActivationCommittee.selector, [stranger])
        );
        _emergencyProtection.checkEmergencyActivationCommittee(stranger);
        _emergencyProtection.checkEmergencyActivationCommittee(address(0));

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _setup(_emergencyGovernance, committee, address(0x2), protectionDuration, emergencyModeDuration);

        _emergencyProtection.checkEmergencyActivationCommittee(committee);

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyActivationCommittee.selector, [stranger])
        );
        _emergencyProtection.checkEmergencyActivationCommittee(stranger);
    }

    function testFuzz_check_execution_committee(address committee, address stranger) external {
        vm.assume(committee != address(0));
        vm.assume(stranger != address(0) && stranger != committee);

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyExecutionCommittee.selector, [stranger])
        );
        _emergencyProtection.checkEmergencyExecutionCommittee(stranger);
        _emergencyProtection.checkEmergencyExecutionCommittee(address(0));

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _setup(_emergencyGovernance, address(0x1), committee, protectionDuration, emergencyModeDuration);

        _emergencyProtection.checkEmergencyExecutionCommittee(committee);

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyExecutionCommittee.selector, [stranger])
        );
        _emergencyProtection.checkEmergencyExecutionCommittee(stranger);
    }

    function test_check_emergency_mode_active() external {
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeState.selector, [true]));
        _emergencyProtection.checkEmergencyMode(true);
        _emergencyProtection.checkEmergencyMode(false);

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _setup(_emergencyGovernance, address(0x1), address(0x2), protectionDuration, emergencyModeDuration);
        _emergencyProtection.activateEmergencyMode();

        _emergencyProtection.checkEmergencyMode(true);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeState.selector, [true]));
    }

    function _setup(
        address newEmergencyGovernance,
        address newEmergencyActivationCommittee,
        address newEmergencyExecutionCommittee,
        Duration protectionDuration,
        Duration emergencyModeDuration
    ) internal {
        _emergencyProtection.setEmergencyGovernance(newEmergencyGovernance);
        _emergencyProtection.setEmergencyActivationCommittee(newEmergencyActivationCommittee);
        _emergencyProtection.setEmergencyExecutionCommittee(newEmergencyExecutionCommittee);
        _emergencyProtection.setEmergencyProtectionEndDate(protectionDuration.addTo(Timestamps.now()), Durations.MAX);
        _emergencyProtection.setEmergencyModeDuration(emergencyModeDuration, Durations.MAX);
    }
}
