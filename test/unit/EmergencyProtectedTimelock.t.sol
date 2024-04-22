// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, Vm} from "forge-std/Test.sol";

import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {IConfiguration, Configuration} from "contracts/Configuration.sol";
import {ConfigurationProvider} from "contracts/ConfigurationProvider.sol";

import "forge-std/console.sol";

contract EmergencyProtectedTimelockUnitTests is Test {
    EmergencyProtectedTimelock private _timelock;
    Configuration private _config;

    address private _emergencyGovernance = makeAddr("emergencyGovernance");
    address private _dualGovernance = makeAddr("dualGovernance");
    address private _executor = makeAddr("executor");

    function setUp() external {
        _config = new Configuration(_executor, _emergencyGovernance, new address[](0));
        _timelock = new EmergencyProtectedTimelock(address(_config));
    }

    function test_admin_executor_can_set_governance() external {
        vm.recordLogs();

        assertEq(_timelock.getGovernance(), address(0));

        vm.prank(_executor);
        _timelock.setGovernance(_dualGovernance);

        assertEq(_timelock.getGovernance(), _dualGovernance);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], EmergencyProtectedTimelock.GovernanceSet.selector);
        assertEq(abi.decode(entries[0].data, (address)), _dualGovernance);
    }

    function test_cannot_set_governance_to_zero() external {
        vm.prank(_executor);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.InvalidGovernance.selector, address(0)));
        _timelock.setGovernance(address(0));
    }

    function test_cannot_set_governance_to_the_same_address() external {
        vm.startPrank(_executor);

        _timelock.setGovernance(_dualGovernance);
        assertEq(_timelock.getGovernance(), _dualGovernance);

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.InvalidGovernance.selector, _dualGovernance));
        _timelock.setGovernance(_dualGovernance);
        assertEq(_timelock.getGovernance(), _dualGovernance);

        vm.stopPrank();
    }

    function testFuzz_stranger_cannot_set_governance(address stranger) external {
        vm.assume(stranger != _executor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ConfigurationProvider.NotAdminExecutor.selector, stranger));
        _timelock.setGovernance(makeAddr("newGovernance"));
    }
}
