// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, Vm} from "forge-std/Test.sol";

import {EmergencyProtection, EmergencyState} from "contracts/libraries/EmergencyProtection.sol";

import {UnitTest} from "test/utils/unit-test.sol";

contract EmergencyProtectionUnitTests is UnitTest {
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

        EmergencyProtection.setup(
            _emergencyProtection, activationCommittee, executionCommittee, protectedTill, duration
        );

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

        EmergencyProtection.setup(_emergencyProtection, activationCommittee, address(0x2), 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(block.timestamp + 200);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(200);

        vm.recordLogs();
        EmergencyProtection.setup(_emergencyProtection, activationCommittee, address(0x3), 200, 200);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, activationCommittee);
        assertEq(_emergencyProtection.executionCommittee, address(0x3));
        assertEq(_emergencyProtection.protectedTill, block.timestamp + 200);
        assertEq(_emergencyProtection.emergencyModeDuration, 200);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_setup_same_execution_committee() external {
        address executionCommittee = makeAddr("executionCommittee");

        EmergencyProtection.setup(_emergencyProtection, address(0x1), executionCommittee, 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x2));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(block.timestamp + 200);
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(200);

        vm.recordLogs();
        EmergencyProtection.setup(_emergencyProtection, address(0x2), executionCommittee, 200, 200);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, address(0x2));
        assertEq(_emergencyProtection.executionCommittee, executionCommittee);
        assertEq(_emergencyProtection.protectedTill, block.timestamp + 200);
        assertEq(_emergencyProtection.emergencyModeDuration, 200);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_setup_same_protected_till() external {
        EmergencyProtection.setup(_emergencyProtection, address(0x1), address(0x2), 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x4));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDurationSet(200);

        vm.recordLogs();
        EmergencyProtection.setup(_emergencyProtection, address(0x3), address(0x4), 100, 200);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, address(0x3));
        assertEq(_emergencyProtection.executionCommittee, address(0x4));
        assertEq(_emergencyProtection.protectedTill, block.timestamp + 100);
        assertEq(_emergencyProtection.emergencyModeDuration, 200);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_setup_same_emergency_mode_duration() external {
        EmergencyProtection.setup(_emergencyProtection, address(0x1), address(0x2), 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyActivationCommitteeSet(address(0x3));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyExecutionCommitteeSet(address(0x4));
        vm.expectEmit();
        emit EmergencyProtection.EmergencyCommitteeProtectedTillSet(block.timestamp + 200);

        vm.recordLogs();
        EmergencyProtection.setup(_emergencyProtection, address(0x3), address(0x4), 200, 100);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(_emergencyProtection.activationCommittee, address(0x3));
        assertEq(_emergencyProtection.executionCommittee, address(0x4));
        assertEq(_emergencyProtection.protectedTill, block.timestamp + 200);
        assertEq(_emergencyProtection.emergencyModeDuration, 100);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_activate_emergency_mode() external {
        EmergencyProtection.setup(_emergencyProtection, address(0x1), address(0x2), 100, 100);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeActivated(block.timestamp);

        vm.recordLogs();

        EmergencyProtection.activate(_emergencyProtection);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, block.timestamp + 100);
    }

    function test_cannot_activate_emergency_mode_if_protected_till_expired() external {
        uint256 protectedTill = 100;
        EmergencyProtection.setup(_emergencyProtection, address(0x1), address(0x2), protectedTill, 100);

        _wait(protectedTill + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.EmergencyCommitteeExpired.selector,
                [block.timestamp, _emergencyProtection.protectedTill]
            )
        );
        EmergencyProtection.activate(_emergencyProtection);
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

        EmergencyProtection.setup(
            _emergencyProtection, activationCommittee, executionCommittee, protectedTill, duration
        );
        EmergencyProtection.activate(_emergencyProtection);

        vm.expectEmit();
        emit EmergencyProtection.EmergencyModeDeactivated(block.timestamp);

        vm.recordLogs();

        EmergencyProtection.deactivate(_emergencyProtection);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);

        assertEq(_emergencyProtection.activationCommittee, address(0));
        assertEq(_emergencyProtection.executionCommittee, address(0));
        assertEq(_emergencyProtection.protectedTill, 0);
        assertEq(_emergencyProtection.emergencyModeDuration, 0);
        assertEq(_emergencyProtection.emergencyModeEndsAfter, 0);
    }

    function test_get_emergency_state() external {
        EmergencyState memory state = EmergencyProtection.getEmergencyState(_emergencyProtection);

        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, 0);
        assertEq(state.emergencyModeDuration, 0);
        assertEq(state.emergencyModeEndsAfter, 0);
        assertEq(state.isEmergencyModeActivated, false);

        EmergencyProtection.setup(_emergencyProtection, address(0x1), address(0x2), 100, 100);

        state = EmergencyProtection.getEmergencyState(_emergencyProtection);

        assertEq(state.activationCommittee, address(0x1));
        assertEq(state.executionCommittee, address(0x2));
        assertEq(state.protectedTill, block.timestamp + 100);
        assertEq(state.emergencyModeDuration, 100);
        assertEq(state.emergencyModeEndsAfter, 0);
        assertEq(state.isEmergencyModeActivated, false);

        EmergencyProtection.activate(_emergencyProtection);

        state = EmergencyProtection.getEmergencyState(_emergencyProtection);

        assertEq(state.activationCommittee, address(0x1));
        assertEq(state.executionCommittee, address(0x2));
        assertEq(state.protectedTill, block.timestamp + 100);
        assertEq(state.emergencyModeDuration, 100);
        assertEq(state.emergencyModeEndsAfter, block.timestamp + 100);
        assertEq(state.isEmergencyModeActivated, true);

        EmergencyProtection.deactivate(_emergencyProtection);

        state = EmergencyProtection.getEmergencyState(_emergencyProtection);

        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, 0);
        assertEq(state.emergencyModeDuration, 0);
        assertEq(state.emergencyModeEndsAfter, 0);
        assertEq(state.isEmergencyModeActivated, false);
    }

    function test_is_emergency_mode_activated() external {
        assertEq(EmergencyProtection.isEmergencyModeActivated(_emergencyProtection), false);

        EmergencyProtection.setup(_emergencyProtection, address(0x1), address(0x2), 100, 100);

        assertEq(EmergencyProtection.isEmergencyModeActivated(_emergencyProtection), false);

        EmergencyProtection.activate(_emergencyProtection);

        assertEq(EmergencyProtection.isEmergencyModeActivated(_emergencyProtection), true);

        EmergencyProtection.deactivate(_emergencyProtection);

        assertEq(EmergencyProtection.isEmergencyModeActivated(_emergencyProtection), false);
    }

    function test_is_emergency_mode_passed() external {
        assertEq(EmergencyProtection.isEmergencyModePassed(_emergencyProtection), false);

        uint256 duration = 100;

        EmergencyProtection.setup(_emergencyProtection, address(0x1), address(0x2), 100, duration);

        assertEq(EmergencyProtection.isEmergencyModePassed(_emergencyProtection), false);

        EmergencyProtection.activate(_emergencyProtection);

        assertEq(EmergencyProtection.isEmergencyModePassed(_emergencyProtection), false);

        _wait(duration + 1);

        assertEq(EmergencyProtection.isEmergencyModePassed(_emergencyProtection), true);

        EmergencyProtection.deactivate(_emergencyProtection);

        assertEq(EmergencyProtection.isEmergencyModePassed(_emergencyProtection), false);
    }

    function test_is_emergency_protection_enabled() external {
        uint256 protectedTill = 100;
        uint256 duration = 100;

        assertEq(EmergencyProtection.isEmergencyProtectionEnabled(_emergencyProtection), false);

        EmergencyProtection.setup(_emergencyProtection, address(0x1), address(0x2), protectedTill, duration);

        assertEq(EmergencyProtection.isEmergencyProtectionEnabled(_emergencyProtection), true);

        _wait(protectedTill - block.timestamp);

        EmergencyProtection.activate(_emergencyProtection);

        _wait(duration);

        assertEq(EmergencyProtection.isEmergencyProtectionEnabled(_emergencyProtection), true);

        _wait(100);

        assertEq(EmergencyProtection.isEmergencyProtectionEnabled(_emergencyProtection), true);

        EmergencyProtection.deactivate(_emergencyProtection);

        assertEq(EmergencyProtection.isEmergencyProtectionEnabled(_emergencyProtection), false);
    }

    function testFuzz_check_activation_committee(address committee, address stranger) external {
        vm.assume(committee != address(0));
        vm.assume(stranger != address(0) && stranger != committee);

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.NotEmergencyActivator.selector,
                [stranger]
            )
        );
        EmergencyProtection.checkActivationCommittee(_emergencyProtection, stranger);
        EmergencyProtection.checkActivationCommittee(_emergencyProtection, address(0));

        EmergencyProtection.setup(_emergencyProtection, committee, address(0x2), 100, 100);

        EmergencyProtection.checkActivationCommittee(_emergencyProtection, committee);

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.NotEmergencyActivator.selector,
                [stranger]
            )
        );
        EmergencyProtection.checkActivationCommittee(_emergencyProtection, stranger);
    }

    function testFuzz_check_execution_committee(address committee, address stranger) external {
        vm.assume(committee != address(0));
        vm.assume(stranger != address(0) && stranger != committee);

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.NotEmergencyEnactor.selector,
                [stranger]
            )
        );
        EmergencyProtection.checkExecutionCommittee(_emergencyProtection, stranger);
        EmergencyProtection.checkExecutionCommittee(_emergencyProtection, address(0));

        EmergencyProtection.setup(_emergencyProtection, address(0x1), committee, 100, 100);

        EmergencyProtection.checkExecutionCommittee(_emergencyProtection, committee);

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.NotEmergencyEnactor.selector,
                [stranger]
            )
        );
        EmergencyProtection.checkExecutionCommittee(_emergencyProtection, stranger);
    }

    function test_check_emergency_mode_active() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.InvalidEmergencyModeActiveValue.selector,
                [false, true]
            )
        );
        EmergencyProtection.checkEmergencyModeActive(_emergencyProtection, true);
        EmergencyProtection.checkEmergencyModeActive(_emergencyProtection, false);

        EmergencyProtection.setup(_emergencyProtection, address(0x1), address(0x2), 100, 100);
        EmergencyProtection.activate(_emergencyProtection);

        EmergencyProtection.checkEmergencyModeActive(_emergencyProtection, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.InvalidEmergencyModeActiveValue.selector,
                [true, false]
            )
        );
    }
}
