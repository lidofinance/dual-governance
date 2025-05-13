// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RolesValidatorBase} from "scripts/launch/RolesValidatorBase.sol";
import {AragonRoles} from "scripts/launch/libraries/AragonRoles.sol";
import {OZRoles} from "scripts/launch/libraries/OZRoles.sol";

contract MockACL {
    mapping(address => mapping(bytes32 => address)) private permissionManagers;
    mapping(address => mapping(bytes32 => mapping(address => bool))) private permissions;

    function setPermissionManager(address entity, bytes32 role, address manager) external {
        permissionManagers[entity][role] = manager;
    }

    function setPermission(address entity, bytes32 role, address who, bool granted) external {
        permissions[entity][role][who] = granted;
    }

    function getPermissionManager(address entity, bytes32 role) external view returns (address) {
        return permissionManagers[entity][role];
    }

    function hasPermission(address who, address entity, bytes32 role) external view returns (bool) {
        return permissions[entity][role][who];
    }
}

contract MockOZ {
    mapping(bytes32 => mapping(address => bool)) private roles;

    function setRole(bytes32 role, address who, bool granted) external {
        roles[role][who] = granted;
    }

    function hasRole(bytes32 role, address who) external view returns (bool) {
        return roles[role][who];
    }
}

contract TestRolesValidator is RolesValidatorBase {
    constructor(address acl) RolesValidatorBase(acl) {}

    function validateAragonRole(address entity, string memory roleName, AragonRoles.Context memory role) public {
        _validate(entity, roleName, role);
    }

    function validateOZRole(address entity, string memory roleName, OZRoles.Context memory role) public {
        _validate(entity, roleName, role);
    }
}

contract RolesValidatorBaseTest is Test {
    using OZRoles for OZRoles.Context;
    using AragonRoles for AragonRoles.Context;

    MockACL public aclContract;
    MockOZ public ozContract;
    TestRolesValidator public rolesValidator;

    string private roleName = "TEST_ROLE";

    address private immutable USER_1 = makeAddr("USER_1");
    address private immutable USER_2 = makeAddr("USER_2");
    address private immutable USER_3 = makeAddr("USER_3");
    address private immutable ENTITY = makeAddr("ENTITY");
    address private immutable MANAGER = makeAddr("MANAGER");

    function setUp() external {
        aclContract = new MockACL();
        ozContract = new MockOZ();
        rolesValidator = new TestRolesValidator(address(aclContract));
    }

    function test_validateAragonRole_HappyPath() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermissionManager(ENTITY, roleNameHash, MANAGER);
        aclContract.setPermission(ENTITY, roleNameHash, USER_1, true);
        aclContract.setPermission(ENTITY, roleNameHash, USER_2, true);
        aclContract.setPermission(ENTITY, roleNameHash, USER_3, false);

        AragonRoles.Context memory role = AragonRoles.manager(MANAGER).granted(USER_1).granted(USER_2).revoked(USER_3);

        assertEq(role.manager, MANAGER);
        assertEq(role.rolesTracker.grantedTo.length, 2);
        assertEq(role.rolesTracker.grantedTo[0], USER_1);
        assertEq(role.rolesTracker.grantedTo[1], USER_2);
        assertEq(role.rolesTracker.revokedFrom.length, 1);
        assertEq(role.rolesTracker.revokedFrom[0], USER_3);

        rolesValidator.validateAragonRole(ENTITY, roleName, role);
    }

    function test_validateAragonRole_InvalidManager() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermissionManager(ENTITY, roleNameHash, USER_1);

        AragonRoles.Context memory role = AragonRoles.manager(MANAGER);
        assertEq(role.manager, MANAGER);
        assertEq(role.rolesTracker.grantedTo.length, 0);
        assertEq(role.rolesTracker.revokedFrom.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                RolesValidatorBase.AragonPermissionInvalidManager.selector, ENTITY, roleName, MANAGER, USER_1
            )
        );

        rolesValidator.validateAragonRole(ENTITY, roleName, role);
    }

    function test_validateAragonRole_PermissionNotGranted() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermissionManager(ENTITY, roleNameHash, MANAGER);
        aclContract.setPermission(ENTITY, roleNameHash, USER_1, false);

        AragonRoles.Context memory role = AragonRoles.manager(MANAGER).granted(USER_1);
        assertEq(role.manager, MANAGER);
        assertEq(role.rolesTracker.grantedTo.length, 1);
        assertEq(role.rolesTracker.grantedTo[0], USER_1);
        assertEq(role.rolesTracker.revokedFrom.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(RolesValidatorBase.AragonPermissionNotGranted.selector, ENTITY, roleName, USER_1)
        );

        rolesValidator.validateAragonRole(ENTITY, roleName, role);
    }

    function test_validateAragonRole_PermissionGranted() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermission(ENTITY, roleNameHash, USER_2, true);

        address[] memory revokedFrom = new address[](1);
        revokedFrom[0] = USER_2;

        AragonRoles.Context memory role = AragonRoles.manager(address(0)).revoked(USER_2);
        assertEq(role.manager, address(0));
        assertEq(role.rolesTracker.grantedTo.length, 0);
        assertEq(role.rolesTracker.revokedFrom.length, 1);
        assertEq(role.rolesTracker.revokedFrom[0], USER_2);

        vm.expectRevert(
            abi.encodeWithSelector(RolesValidatorBase.AragonPermissionGranted.selector, ENTITY, roleName, USER_2)
        );
        rolesValidator.validateAragonRole(ENTITY, roleName, role);
    }

    function test_validateOZRole_HappyPath() external {
        bytes32 roleHash = keccak256(bytes(roleName));

        ozContract.setRole(roleHash, USER_1, true);
        ozContract.setRole(roleHash, USER_2, false);
        ozContract.setRole(roleHash, USER_3, true);

        address[] memory grantedTo = new address[](1);
        grantedTo[0] = USER_1;

        address[] memory revokedFrom = new address[](1);
        revokedFrom[0] = USER_2;

        OZRoles.Context memory role = OZRoles.granted(USER_1).revoked(USER_2).granted(USER_3);

        assertEq(role.rolesTracker.grantedTo.length, 2);
        assertEq(role.rolesTracker.grantedTo[0], USER_1);
        assertEq(role.rolesTracker.grantedTo[1], USER_3);
        assertEq(role.rolesTracker.revokedFrom.length, 1);
        assertEq(role.rolesTracker.revokedFrom[0], USER_2);

        rolesValidator.validateOZRole(address(ozContract), roleName, role);
    }

    function test_validateOZRole_DefaultAdminRole() external {
        string memory roleNameDefault = "DEFAULT_ADMIN_ROLE";
        bytes32 roleHash = bytes32(0);

        ozContract.setRole(roleHash, USER_1, true);
        ozContract.setRole(roleHash, USER_2, false);

        address[] memory grantedTo = new address[](1);
        grantedTo[0] = USER_1;

        address[] memory revokedFrom = new address[](1);
        revokedFrom[0] = USER_2;

        OZRoles.Context memory role = OZRoles.granted(USER_1).revoked(USER_2);

        assertEq(role.rolesTracker.grantedTo.length, 1);
        assertEq(role.rolesTracker.grantedTo[0], USER_1);
        assertEq(role.rolesTracker.revokedFrom.length, 1);
        assertEq(role.rolesTracker.revokedFrom[0], USER_2);

        rolesValidator.validateOZRole(address(ozContract), roleNameDefault, role);
    }

    function test_validateOZRole_RoleNotGranted() external {
        bytes32 roleHash = keccak256(bytes(roleName));

        ozContract.setRole(roleHash, USER_1, false);

        OZRoles.Context memory role = OZRoles.granted(USER_1);

        assertEq(role.rolesTracker.grantedTo.length, 1);
        assertEq(role.rolesTracker.grantedTo[0], USER_1);
        assertEq(role.rolesTracker.revokedFrom.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(RolesValidatorBase.OZRoleNotGranted.selector, address(ozContract), roleName, USER_1)
        );

        rolesValidator.validateOZRole(address(ozContract), roleName, role);
    }

    function test_validateOZRole_RoleGranted() external {
        bytes32 roleHash = keccak256(bytes(roleName));

        ozContract.setRole(roleHash, USER_2, true);

        OZRoles.Context memory role = OZRoles.revoked(USER_2);

        assertEq(role.rolesTracker.grantedTo.length, 0);
        assertEq(role.rolesTracker.revokedFrom.length, 1);
        assertEq(role.rolesTracker.revokedFrom[0], USER_2);

        vm.expectRevert(
            abi.encodeWithSelector(RolesValidatorBase.OZRoleGranted.selector, address(ozContract), roleName, USER_2)
        );
        rolesValidator.validateOZRole(address(ozContract), roleName, role);
    }

    function test_Events() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermissionManager(ENTITY, roleNameHash, MANAGER);

        AragonRoles.Context memory aragonRole = AragonRoles.manager(MANAGER);
        assertEq(aragonRole.manager, MANAGER);
        assertEq(aragonRole.rolesTracker.grantedTo.length, 0);
        assertEq(aragonRole.rolesTracker.revokedFrom.length, 0);

        vm.expectEmit(address(rolesValidator));
        emit RolesValidatorBase.AragonPermissionValidated(
            ENTITY, roleName, MANAGER, aragonRole.rolesTracker.grantedTo, aragonRole.rolesTracker.revokedFrom
        );
        rolesValidator.validateAragonRole(ENTITY, roleName, aragonRole);

        OZRoles.Context memory ozRole = OZRoles.revoked(USER_1).revoked(USER_2);
        assertEq(ozRole.rolesTracker.grantedTo.length, 0);
        assertEq(ozRole.rolesTracker.revokedFrom.length, 2);
        assertEq(ozRole.rolesTracker.revokedFrom[0], USER_1);
        assertEq(ozRole.rolesTracker.revokedFrom[1], USER_2);

        vm.expectEmit(address(rolesValidator));
        emit RolesValidatorBase.OZRoleValidated(
            address(ozContract), roleName, ozRole.rolesTracker.grantedTo, ozRole.rolesTracker.revokedFrom
        );
        rolesValidator.validateOZRole(address(ozContract), roleName, ozRole);
    }
}
