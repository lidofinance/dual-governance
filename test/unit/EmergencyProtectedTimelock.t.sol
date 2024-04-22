// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, Vm} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {IConfiguration, Configuration} from "contracts/Configuration.sol";
import {ConfigurationProvider} from "contracts/ConfigurationProvider.sol";

import "forge-std/console.sol";

contract EmergencyProtectedTimelockUnitTests is Test {
    EmergencyProtectedTimelock private _timelock;
    Configuration private _config;

    address private _emergencyGovernance = makeAddr("emergencyGovernance");
    address private _dualGovernance = makeAddr("dualGovernance");
    address private _adminExecutor = makeAddr("executor");

    function setUp() external {
        _config = new Configuration(_adminExecutor, _emergencyGovernance, new address[](0));
        _timelock = new EmergencyProtectedTimelock(address(_config));
    }

    // EmergencyProtectedTimelock.setGovernance()

    function test_admin_executor_can_set_governance() external {
        assertEq(_timelock.getGovernance(), address(0));

        vm.recordLogs();

        vm.prank(_adminExecutor);
        _timelock.setGovernance(_dualGovernance);

        assertEq(_timelock.getGovernance(), _dualGovernance);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(_timelock));
        assertEq(entries[0].topics[0], EmergencyProtectedTimelock.GovernanceSet.selector);
        // There is no topic with value in the event (foundry bug??)
        assertEq(entries[0].topics.length, 1);

        assertEq(abi.decode(entries[0].data, (address)), _dualGovernance);
    }

    function test_cannot_set_governance_to_zero() external {
        vm.prank(_adminExecutor);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.InvalidGovernance.selector, address(0)));
        _timelock.setGovernance(address(0));
    }

    function test_cannot_set_governance_to_the_same_address() external {
        vm.startPrank(_adminExecutor);

        _timelock.setGovernance(_dualGovernance);
        assertEq(_timelock.getGovernance(), _dualGovernance);

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.InvalidGovernance.selector, _dualGovernance));
        _timelock.setGovernance(_dualGovernance);
        assertEq(_timelock.getGovernance(), _dualGovernance);

        vm.stopPrank();
    }

    function testFuzz_stranger_cannot_set_governance(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ConfigurationProvider.NotAdminExecutor.selector, stranger));
        _timelock.setGovernance(makeAddr("newGovernance"));
    }

    // EmergencyProtectedTimelock.transferExecutorOwnership()

    function testFuzz_admin_executor_can_transfer_executor_ownership(address newOwner) external {
        vm.assume(newOwner != _adminExecutor);
        vm.assume(newOwner != address(0));

        Executor executor = new Executor(address(_timelock));

        assertEq(executor.owner(), address(_timelock));

        vm.recordLogs();

        vm.prank(_adminExecutor);
        _timelock.transferExecutorOwnership(address(executor), newOwner);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(executor));
        assertEq(entries[0].topics[0], Ownable.OwnershipTransferred.selector);
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(address(_timelock)))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(newOwner))));

        // There is no data in the event (foundry bug??)
        assertEq(bytes32(entries[0].data), bytes32(uint256(0)));

        assertEq(executor.owner(), newOwner);
    }

    function test_stranger_cannot_transfer_executor_ownership(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ConfigurationProvider.NotAdminExecutor.selector, stranger));
        _timelock.transferExecutorOwnership(_adminExecutor, makeAddr("newOwner"));
    }
}
