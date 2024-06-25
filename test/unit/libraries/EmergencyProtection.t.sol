// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, Vm} from "forge-std/Test.sol";

import {EmergencyProtection, EmergencyState} from "contracts/libraries/EmergencyProtection.sol";

import {UnitTest, Duration, Durations, Timestamp, Timestamps} from "test/utils/unit-test.sol";

contract EmergencyProtectionUnitTests is UnitTest {
    using EmergencyProtection for EmergencyProtection.State;

    EmergencyProtection.State internal _emergencyProtection;

    function testFuzz_setup_emergency_protection(
        address activationCommittee,
        address executionCommittee,
        Duration protectionDuration,
        Duration duration
    ) external {
        vm.assume(protectionDuration > Durations.ZERO);
        vm.assume(duration > Durations.ZERO);
        vm.assume(activationCommittee != address(0));
        vm.assume(executionCommittee != address(0));

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(activationCommittee);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(executionCommittee);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(protectionDuration.addTo(Timestamps.now()));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(duration);

        vm.recordLogs();

        _emergencyProtection.setup(activationCommittee, executionCommittee, protectionDuration, duration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 4);

        assertEq(_emergencyProtection.activationCommittee, activationCommittee);
        assertEq(_emergencyProtection.executionCommittee, executionCommittee);
        assertEq(_emergencyProtection.protectedTill, protectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, duration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_setup_same_activation_committee() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);
        address activationCommittee = makeAddr("activationCommittee");

        _emergencyProtection.setup(activationCommittee, address(0x2), protectionDuration, emergencyModeDuration);

        Duration newProtectionDuration = Durations.from(200 seconds);
        Duration newEmergencyModeDuration = Durations.from(300 seconds);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(newProtectionDuration.addTo(Timestamps.now()));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(newEmergencyModeDuration);

        vm.recordLogs();
        _emergencyProtection.setup(activationCommittee, address(0x3), newProtectionDuration, newEmergencyModeDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, activationCommittee);
        assertEq(_emergencyProtection.executionCommittee, address(0x3));
        assertEq(_emergencyProtection.protectedTill, newProtectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, newEmergencyModeDuration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_setup_same_execution_committee() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);
        address executionCommittee = makeAddr("executionCommittee");

        _emergencyProtection.setup(address(0x1), executionCommittee, protectionDuration, emergencyModeDuration);

        Duration newProtectionDuration = Durations.from(200 seconds);
        Duration newEmergencyModeDuration = Durations.from(300 seconds);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x2));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(newProtectionDuration.addTo(Timestamps.now()));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(newEmergencyModeDuration);

        vm.recordLogs();
        _emergencyProtection.setup(address(0x2), executionCommittee, newProtectionDuration, newEmergencyModeDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, address(0x2));
        assertEq(_emergencyProtection.executionCommittee, executionCommittee);
        assertEq(_emergencyProtection.protectedTill, newProtectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, newEmergencyModeDuration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_setup_same_protected_till() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _emergencyProtection.setup(address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        Duration newProtectionDuration = protectionDuration; // the new value is the same as previous one
        Duration newEmergencyModeDuration = Durations.from(200 seconds);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x4));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(newEmergencyModeDuration);

        vm.recordLogs();
        _emergencyProtection.setup(address(0x3), address(0x4), newProtectionDuration, newEmergencyModeDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, address(0x3));
        assertEq(_emergencyProtection.executionCommittee, address(0x4));
        assertEq(_emergencyProtection.protectedTill, protectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, newEmergencyModeDuration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_setup_same_emergency_mode_duration() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _emergencyProtection.setup(address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        Duration newProtectionDuration = Durations.from(200 seconds);
        Duration newEmergencyModeDuration = emergencyModeDuration; // the new value is the same as previous one

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x4));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(newProtectionDuration.addTo(Timestamps.now()));

        vm.recordLogs();
        _emergencyProtection.setup(address(0x3), address(0x4), newProtectionDuration, newEmergencyModeDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, address(0x3));
        assertEq(_emergencyProtection.executionCommittee, address(0x4));
        assertEq(_emergencyProtection.protectedTill, newProtectionDuration.addTo(Timestamps.now()));
        assertEq(_emergencyProtection.emergencyModeDuration, newEmergencyModeDuration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_activate_emergency_mode() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _emergencyProtection.setup(address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeActivated(Timestamps.now());

        vm.recordLogs();

        _emergencyProtection.activate();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, emergencyModeDuration.addTo(Timestamps.now()));
    }

    function test_cannot_activate_emergency_mode_if_protected_till_expired() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _emergencyProtection.setup(address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        _wait(protectionDuration.plusSeconds(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.EmergencyCommitteeExpired.selector,
                Timestamps.now(),
                _emergencyProtection.protectedTill
            )
        );
        _emergencyProtection.activate();
    }

    function testFuzz_deactivate_emergency_mode(
        address activationCommittee,
        address executionCommittee,
        Duration protectionDuration,
        Duration emergencyModeDuration
    ) external {
        vm.assume(activationCommittee != address(0));
        vm.assume(executionCommittee != address(0));

        _emergencyProtection.setup(activationCommittee, executionCommittee, protectionDuration, emergencyModeDuration);
        _emergencyProtection.activate();

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDeactivated(Timestamps.now());

        vm.recordLogs();

        _emergencyProtection.deactivate();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);

        assertEq(_emergencyProtection.activationCommittee, address(0));
        assertEq(_emergencyProtection.executionCommittee, address(0));
        assertEq(_emergencyProtection.protectedTill, Timestamps.ZERO);
        assertEq(_emergencyProtection.emergencyModeDuration, Durations.ZERO);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_get_emergency_state() external {
        EmergencyState memory state = _emergencyProtection.getEmergencyState();

        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
        assertEq(state.isEmergencyModeActivated, false);

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(200 seconds);

        _emergencyProtection.setup(address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        state = _emergencyProtection.getEmergencyState();

        assertEq(state.activationCommittee, address(0x1));
        assertEq(state.executionCommittee, address(0x2));
        assertEq(state.protectedTill, protectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeDuration, emergencyModeDuration);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
        assertEq(state.isEmergencyModeActivated, false);

        _emergencyProtection.activate();

        state = _emergencyProtection.getEmergencyState();

        assertEq(state.activationCommittee, address(0x1));
        assertEq(state.executionCommittee, address(0x2));
        assertEq(state.protectedTill, protectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeDuration, emergencyModeDuration);
        assertEq(state.emergencyModeEndsAfter, emergencyModeDuration.addTo(Timestamps.now()));
        assertEq(state.isEmergencyModeActivated, true);

        _emergencyProtection.deactivate();

        state = _emergencyProtection.getEmergencyState();

        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
        assertEq(state.isEmergencyModeActivated, false);
    }

    function test_is_emergency_mode_activated() external {
        assertEq(_emergencyProtection.isEmergencyModeActivated(), false);

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _emergencyProtection.setup(address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        assertEq(_emergencyProtection.isEmergencyModeActivated(), false);

        _emergencyProtection.activate();

        assertEq(_emergencyProtection.isEmergencyModeActivated(), true);

        _emergencyProtection.deactivate();

        assertEq(_emergencyProtection.isEmergencyModeActivated(), false);
    }

    function test_is_emergency_mode_passed() external {
        assertEq(_emergencyProtection.isEmergencyModePassed(), false);

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(200 seconds);

        _emergencyProtection.setup(address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        assertEq(_emergencyProtection.isEmergencyModePassed(), false);

        _emergencyProtection.activate();

        assertEq(_emergencyProtection.isEmergencyModePassed(), false);

        _wait(emergencyModeDuration.plusSeconds(1));

        assertEq(_emergencyProtection.isEmergencyModePassed(), true);

        _emergencyProtection.deactivate();

        assertEq(_emergencyProtection.isEmergencyModePassed(), false);
    }

    function test_is_emergency_protection_enabled() external {
        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(200 seconds);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), false);

        _emergencyProtection.setup(address(0x1), address(0x2), protectionDuration, emergencyModeDuration);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), true);

        EmergencyState memory emergencyState = _emergencyProtection.getEmergencyState();

        _wait(Durations.between(emergencyState.protectedTill, Timestamps.now()));

        // _wait(emergencyState.protectedTill.absDiff(Timestamps.now()));

        EmergencyProtection.activate(_emergencyProtection);

        _wait(emergencyModeDuration);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), true);

        _wait(protectionDuration);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), true);

        EmergencyProtection.deactivate(_emergencyProtection);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), false);
    }

    function testFuzz_check_activation_committee(address committee, address stranger) external {
        vm.assume(committee != address(0));
        vm.assume(stranger != address(0) && stranger != committee);

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyActivator.selector, [stranger]));
        _emergencyProtection.checkActivationCommittee(stranger);
        _emergencyProtection.checkActivationCommittee(address(0));

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _emergencyProtection.setup(committee, address(0x2), protectionDuration, emergencyModeDuration);

        _emergencyProtection.checkActivationCommittee(committee);

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyActivator.selector, [stranger]));
        _emergencyProtection.checkActivationCommittee(stranger);
    }

    function testFuzz_check_execution_committee(address committee, address stranger) external {
        vm.assume(committee != address(0));
        vm.assume(stranger != address(0) && stranger != committee);

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyEnactor.selector, [stranger]));
        _emergencyProtection.checkExecutionCommittee(stranger);
        _emergencyProtection.checkExecutionCommittee(address(0));

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _emergencyProtection.setup(address(0x1), committee, protectionDuration, emergencyModeDuration);

        _emergencyProtection.checkExecutionCommittee(committee);

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyEnactor.selector, [stranger]));
        _emergencyProtection.checkExecutionCommittee(stranger);
    }

    function test_check_emergency_mode_active() external {
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeActiveValue.selector, [false, true])
        );
        _emergencyProtection.checkEmergencyModeActive(true);
        _emergencyProtection.checkEmergencyModeActive(false);

        Duration protectionDuration = Durations.from(100 seconds);
        Duration emergencyModeDuration = Durations.from(100 seconds);

        _emergencyProtection.setup(address(0x1), address(0x2), protectionDuration, emergencyModeDuration);
        _emergencyProtection.activate();

        _emergencyProtection.checkEmergencyModeActive(true);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeActiveValue.selector, [true, false])
        );
    }
}
