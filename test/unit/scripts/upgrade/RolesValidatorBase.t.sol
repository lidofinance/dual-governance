// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RolesValidatorBase} from "scripts/upgrade/RolesValidatorBase.sol";
import {AragonRoles} from "scripts/upgrade/libraries/AragonRoles.sol";
import {OZRoles} from "scripts/upgrade/libraries/OZRoles.sol";
import {IACL} from "scripts/upgrade/interfaces/IACL.sol";
import {IOZ} from "scripts/upgrade/interfaces/IOZ.sol";

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
    MockACL public aclContract;
    MockOZ public ozContract;
    TestRolesValidator public rolesValidator;

    address private constant ENTITY = address(0x123);
    address private constant MANAGER = address(0x456);
    address private constant USER_1 = address(0x789);
    address private constant USER_2 = address(0xabc);
    address private constant USER_3 = address(0xdef);

    string roleName = "TEST_ROLE";

    function setUp() external {
        aclContract = new MockACL();
        ozContract = new MockOZ();
        rolesValidator = new TestRolesValidator(address(aclContract));
    }

    function test_ValidateAragonRole_HappyPath() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermissionManager(ENTITY, roleNameHash, MANAGER);
        aclContract.setPermission(ENTITY, roleNameHash, USER_1, true);
        aclContract.setPermission(ENTITY, roleNameHash, USER_2, false);

        address[] memory grantedTo = new address[](1);
        grantedTo[0] = USER_1;

        address[] memory revokedFrom = new address[](1);
        revokedFrom[0] = USER_2;

        AragonRoles.Context memory roleContext =
            AragonRoles.Context({manager: MANAGER, grantedTo: grantedTo, revokedFrom: revokedFrom});

        rolesValidator.validateAragonRole(ENTITY, roleName, roleContext);
    }

    function test_ValidateAragonRole_InvalidManager() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermissionManager(ENTITY, roleNameHash, USER_1);

        AragonRoles.Context memory roleContext =
            AragonRoles.Context({manager: MANAGER, grantedTo: new address[](0), revokedFrom: new address[](0)});

        vm.expectRevert(
            abi.encodeWithSelector(
                RolesValidatorBase.AragonPermissionInvalidManager.selector, ENTITY, roleName, MANAGER, USER_1
            )
        );

        rolesValidator.validateAragonRole(ENTITY, roleName, roleContext);
    }

    function test_ValidateAragonRole_PermissionNotGranted() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermissionManager(ENTITY, roleNameHash, MANAGER);
        aclContract.setPermission(ENTITY, roleNameHash, USER_1, false);

        address[] memory grantedTo = new address[](1);
        grantedTo[0] = USER_1;

        AragonRoles.Context memory roleContext =
            AragonRoles.Context({manager: MANAGER, grantedTo: grantedTo, revokedFrom: new address[](0)});

        vm.expectRevert(
            abi.encodeWithSelector(RolesValidatorBase.AragonPermissionNotGranted.selector, ENTITY, roleName, USER_1)
        );

        rolesValidator.validateAragonRole(ENTITY, roleName, roleContext);
    }

    function test_ValidateAragonRole_PermissionGranted() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermissionManager(ENTITY, roleNameHash, MANAGER);
        aclContract.setPermission(ENTITY, roleNameHash, USER_2, true);

        address[] memory revokedFrom = new address[](1);
        revokedFrom[0] = USER_2;

        AragonRoles.Context memory roleContext =
            AragonRoles.Context({manager: MANAGER, grantedTo: new address[](0), revokedFrom: revokedFrom});

        vm.expectRevert(
            abi.encodeWithSelector(RolesValidatorBase.AragonPermissionGranted.selector, ENTITY, roleName, USER_2)
        );

        rolesValidator.validateAragonRole(ENTITY, roleName, roleContext);
    }

    function test_ValidateOZRole_HappyPath() external {
        bytes32 roleHash = keccak256(bytes(roleName));

        ozContract.setRole(roleHash, USER_1, true);
        ozContract.setRole(roleHash, USER_2, false);

        address[] memory grantedTo = new address[](1);
        grantedTo[0] = USER_1;

        address[] memory revokedFrom = new address[](1);
        revokedFrom[0] = USER_2;

        OZRoles.Context memory roleContext = OZRoles.Context({grantedTo: grantedTo, revokedFrom: revokedFrom});

        rolesValidator.validateOZRole(address(ozContract), roleName, roleContext);
    }

    function test_ValidateOZRole_DefaultAdminRole() external {
        string memory roleNameDefault = "DEFAULT_ADMIN_ROLE";
        bytes32 roleHash = bytes32(0);

        ozContract.setRole(roleHash, USER_1, true);
        ozContract.setRole(roleHash, USER_2, false);

        address[] memory grantedTo = new address[](1);
        grantedTo[0] = USER_1;

        address[] memory revokedFrom = new address[](1);
        revokedFrom[0] = USER_2;

        OZRoles.Context memory roleContext = OZRoles.Context({grantedTo: grantedTo, revokedFrom: revokedFrom});

        rolesValidator.validateOZRole(address(ozContract), roleNameDefault, roleContext);
    }

    function test_ValidateOZRole_RoleNotGranted() external {
        bytes32 roleHash = keccak256(bytes(roleName));

        ozContract.setRole(roleHash, USER_1, false);

        address[] memory grantedTo = new address[](1);
        grantedTo[0] = USER_1;

        OZRoles.Context memory roleContext = OZRoles.Context({grantedTo: grantedTo, revokedFrom: new address[](0)});

        vm.expectRevert(
            abi.encodeWithSelector(RolesValidatorBase.OZRoleNotGranted.selector, address(ozContract), roleName, USER_1)
        );

        rolesValidator.validateOZRole(address(ozContract), roleName, roleContext);
    }

    function test_ValidateOZRole_RoleGranted() external {
        bytes32 roleHash = keccak256(bytes(roleName));

        ozContract.setRole(roleHash, USER_2, true);

        address[] memory revokedFrom = new address[](1);
        revokedFrom[0] = USER_2;

        OZRoles.Context memory roleContext = OZRoles.Context({grantedTo: new address[](0), revokedFrom: revokedFrom});

        vm.expectRevert(
            abi.encodeWithSelector(RolesValidatorBase.OZRoleGranted.selector, address(ozContract), roleName, USER_2)
        );

        rolesValidator.validateOZRole(address(ozContract), roleName, roleContext);
    }

    function test_Events() external {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        aclContract.setPermissionManager(ENTITY, roleNameHash, MANAGER);
        AragonRoles.Context memory aragonRoleContext =
            AragonRoles.Context({manager: MANAGER, grantedTo: new address[](0), revokedFrom: new address[](0)});

        vm.expectEmit(true, true, true, true);
        emit RolesValidatorBase.RoleValidated(ENTITY, roleName);
        rolesValidator.validateAragonRole(ENTITY, roleName, aragonRoleContext);

        OZRoles.Context memory ozRoleContext =
            OZRoles.Context({grantedTo: new address[](0), revokedFrom: new address[](0)});

        vm.expectEmit(true, true, true, true);
        emit RolesValidatorBase.RoleValidated(address(ozContract), roleName);
        rolesValidator.validateOZRole(address(ozContract), roleName, ozRoleContext);
    }
}
