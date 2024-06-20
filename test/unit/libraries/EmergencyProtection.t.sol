// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, Vm} from "forge-std/Test.sol";

import {EmergencyProtection, EmergencyState} from "contracts/libraries/EmergencyProtection.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract EmergencyProtectionUnitTests is UnitTest {
    using EmergencyProtection for EmergencyProtection.State;

    EmergencyProtection.State internal _emergencyProtection;

    function testFuzz_setup_emergency_protection(
        address activationCommittee,
        address executionCommittee,
        uint256 protectedTill,
        uint256 duration
    ) external {
        vm.assume(protectedTill > 0 && protectedTill < type(uint40).max);
        vm.assume(duration > 0 && duration < type(uint32).max);
        vm.assume(activationCommittee != address(0));
        vm.assume(executionCommittee != address(0));

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(activationCommittee);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(executionCommittee);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(block.timestamp + protectedTill);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(duration);

        vm.recordLogs();

        _emergencyProtection.setup(activationCommittee, executionCommittee, protectedTill, duration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 4);

        assertEq(_emergencyProtection.activationCommittee, activationCommittee);
        assertEq(_emergencyProtection.executionCommittee, executionCommittee);
        assertEq(_emergencyProtection.protectedTill, block.timestamp + protectedTill);
        assertEq(_emergencyProtection.emergencyModeDuration, duration);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_setup_same_activation_committee() external {
        address activationCommittee = makeAddr("activationCommittee");

        _emergencyProtection.setup(activationCommittee, address(0x2), 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(block.timestamp + 200);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(300);

        vm.recordLogs();
        _emergencyProtection.setup(activationCommittee, address(0x3), 200, 300);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, activationCommittee);
        assertEq(_emergencyProtection.executionCommittee, address(0x3));
        assertEq(_emergencyProtection.protectedTill, block.timestamp + 200);
        assertEq(_emergencyProtection.emergencyModeDuration, 300);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_setup_same_execution_committee() external {
        address executionCommittee = makeAddr("executionCommittee");

        _emergencyProtection.setup(address(0x1), executionCommittee, 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x2));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(block.timestamp + 200);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(300);

        vm.recordLogs();
        _emergencyProtection.setup(address(0x2), executionCommittee, 200, 300);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, address(0x2));
        assertEq(_emergencyProtection.executionCommittee, executionCommittee);
        assertEq(_emergencyProtection.protectedTill, block.timestamp + 200);
        assertEq(_emergencyProtection.emergencyModeDuration, 300);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_setup_same_protected_till() external {
        _emergencyProtection.setup(address(0x1), address(0x2), 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x4));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(200);

        vm.recordLogs();
        _emergencyProtection.setup(address(0x3), address(0x4), 100, 200);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, address(0x3));
        assertEq(_emergencyProtection.executionCommittee, address(0x4));
        assertEq(_emergencyProtection.protectedTill, block.timestamp + 100);
        assertEq(_emergencyProtection.emergencyModeDuration, 200);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_setup_same_emergency_mode_duration() external {
        _emergencyProtection.setup(address(0x1), address(0x2), 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x4));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(block.timestamp + 200);

        vm.recordLogs();
        _emergencyProtection.setup(address(0x3), address(0x4), 200, 100);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, address(0x3));
        assertEq(_emergencyProtection.executionCommittee, address(0x4));
        assertEq(_emergencyProtection.protectedTill, block.timestamp + 200);
        assertEq(_emergencyProtection.emergencyModeDuration, 100);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_activate_emergency_mode() external {
        _emergencyProtection.setup(address(0x1), address(0x2), 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeActivated(block.timestamp);

        vm.recordLogs();

        _emergencyProtection.activate();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, block.timestamp + 100);
    }

    function test_cannot_activate_emergency_mode_if_protected_till_expired() external {
        uint256 protectedTill = 100;
        _emergencyProtection.setup(address(0x1), address(0x2), protectedTill, 100);

        _wait(protectedTill + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.EmergencyCommitteeExpired.selector,
                [block.timestamp, _emergencyProtection.protectedTill]
            )
        );
        _emergencyProtection.activate();
    }

    function testFuzz_deactivate_emergency_mode(
        address activationCommittee,
        address executionCommittee,
        uint256 protectedTill,
        uint256 duration
    ) external {
        vm.assume(protectedTill > 0 && protectedTill < type(uint40).max);
        vm.assume(duration > 0 && duration < type(uint32).max);
        vm.assume(activationCommittee != address(0));
        vm.assume(executionCommittee != address(0));

        _emergencyProtection.setup(activationCommittee, executionCommittee, protectedTill, duration);
        _emergencyProtection.activate();

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDeactivated(block.timestamp);

        vm.recordLogs();

        _emergencyProtection.deactivate();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);

        assertEq(_emergencyProtection.activationCommittee, address(0));
        assertEq(_emergencyProtection.executionCommittee, address(0));
        assertEq(_emergencyProtection.protectedTill, 0);
        assertEq(_emergencyProtection.emergencyModeDuration, 0);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_get_emergency_state() external {
        EmergencyState memory state = _emergencyProtection.getEmergencyState();

        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, 0);
        assertEq(state.emergencyModeDuration, 0);
        assertEq(state.emergencyModeEndsAfter, 0);
        assertEq(state.isEmergencyModeActivated, false);

        _emergencyProtection.setup(address(0x1), address(0x2), 100, 200);

        state = _emergencyProtection.getEmergencyState();

        assertEq(state.activationCommittee, address(0x1));
        assertEq(state.executionCommittee, address(0x2));
        assertEq(state.protectedTill, block.timestamp + 100);
        assertEq(state.emergencyModeDuration, 200);
        assertEq(state.emergencyModeEndsAfter, 0);
        assertEq(state.isEmergencyModeActivated, false);

        _emergencyProtection.activate();

        state = _emergencyProtection.getEmergencyState();

        assertEq(state.activationCommittee, address(0x1));
        assertEq(state.executionCommittee, address(0x2));
        assertEq(state.protectedTill, block.timestamp + 100);
        assertEq(state.emergencyModeDuration, 200);
        assertEq(state.emergencyModeEndsAfter, block.timestamp + 200);
        assertEq(state.isEmergencyModeActivated, true);

        _emergencyProtection.deactivate();

        state = _emergencyProtection.getEmergencyState();

        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, 0);
        assertEq(state.emergencyModeDuration, 0);
        assertEq(state.emergencyModeEndsAfter, 0);
        assertEq(state.isEmergencyModeActivated, false);
    }

    function test_is_emergency_mode_activated() external {
        assertEq(_emergencyProtection.isEmergencyModeActivated(), false);

        _emergencyProtection.setup(address(0x1), address(0x2), 100, 100);

        assertEq(_emergencyProtection.isEmergencyModeActivated(), false);

        _emergencyProtection.activate();

        assertEq(_emergencyProtection.isEmergencyModeActivated(), true);

        _emergencyProtection.deactivate();

        assertEq(_emergencyProtection.isEmergencyModeActivated(), false);
    }

    function test_is_emergency_mode_passed() external {
        assertEq(_emergencyProtection.isEmergencyModePassed(), false);

        uint256 duration = 200;

        _emergencyProtection.setup(address(0x1), address(0x2), 100, duration);

        assertEq(_emergencyProtection.isEmergencyModePassed(), false);

        _emergencyProtection.activate();

        assertEq(_emergencyProtection.isEmergencyModePassed(), false);

        _wait(duration + 1);

        assertEq(_emergencyProtection.isEmergencyModePassed(), true);

        _emergencyProtection.deactivate();

        assertEq(_emergencyProtection.isEmergencyModePassed(), false);
    }

    function test_is_emergency_protection_enabled() external {
        uint256 protectedTill = 100;
        uint256 duration = 200;

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), false);

        _emergencyProtection.setup(address(0x1), address(0x2), protectedTill, duration);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), true);

        _wait(protectedTill - block.timestamp);

        EmergencyProtection.activate(_emergencyProtection);

        _wait(duration);

        assertEq(_emergencyProtection.isEmergencyProtectionEnabled(), true);

        _wait(100);

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

        _emergencyProtection.setup(committee, address(0x2), 100, 100);

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

        _emergencyProtection.setup(address(0x1), committee, 100, 100);

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

        _emergencyProtection.setup(address(0x1), address(0x2), 100, 100);
        _emergencyProtection.activate();

        _emergencyProtection.checkEmergencyModeActive(true);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeActiveValue.selector, [true, false])
        );
    }
}
