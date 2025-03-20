// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AragonRoles} from "./libraries/AragonRoles.sol";
import {OZRoles} from "./libraries/OZRoles.sol";

import {IACL} from "./interfaces/IACL.sol";
import {IOZ} from "./interfaces/IOZ.sol";

/**
 * @title RolesValidatorBase
 * @dev Abstract contract for validating roles in both Aragon and OpenZeppelin access control systems.
 * This base contract provides functionality to check if entities have the correct permissions
 * according to predefined role configurations.
 */
abstract contract RolesValidatorBase {
    event RoleValidated(address entity, string roleName);

    error OZRoleGranted(address entity, string roleName, address app);
    error OZRoleNotGranted(address entity, string roleName, address app);
    error AragonPermissionInvalidManager(
        address entity, string roleName, address expectedManager, address actualManager
    );
    error AragonPermissionGranted(address entity, string roleName, address app);
    error AragonPermissionNotGranted(address entity, string roleName, address app);

    IACL public immutable ACL_CONTRACT;

    constructor(address acl) {
        ACL_CONTRACT = IACL(acl);
    }

    // @dev Validates Aragon role permissions for a specific entity.
    // @param entity The address of the contract entity to validate.
    // @param roleName The string name of the role being validated.
    // @param role The context containing manager, granted and revoked addresses for the role.
    // @notice Checks that:
    // 1. The role has the correct manager.
    // 2. All addresses in grantedTo list have the permission.
    // 3. All addresses in revokedFrom list do not have the permission.
    function _validate(address entity, string memory roleName, AragonRoles.Context memory role) internal {
        bytes32 roleNameHash = keccak256(bytes(roleName));

        address roleManager = ACL_CONTRACT.getPermissionManager(entity, roleNameHash);
        if (roleManager != role.manager) {
            revert AragonPermissionInvalidManager(entity, roleName, role.manager, roleManager);
        }

        for (uint256 i = 0; i < role.grantedTo.length; ++i) {
            bool isPermissionGranted = ACL_CONTRACT.hasPermission(role.grantedTo[i], entity, roleNameHash);
            if (!isPermissionGranted) {
                revert AragonPermissionNotGranted(entity, roleName, role.grantedTo[i]);
            }
        }

        for (uint256 i = 0; i < role.revokedFrom.length; ++i) {
            bool isPermissionGranted = ACL_CONTRACT.hasPermission(role.revokedFrom[i], entity, roleNameHash);
            if (isPermissionGranted) {
                revert AragonPermissionGranted(entity, roleName, role.revokedFrom[i]);
            }
        }

        emit RoleValidated(entity, roleName);
    }

    // @dev Validates OpenZeppelin role assignments for a specific entity.
    // @param entity The address of the contract entity to validate.
    // @param roleName The string name of the role being validated.
    // @param role The context containing granted and revoked addresses for the role.
    // @notice Handles special case for DEFAULT_ADMIN_ROLE (uses bytes32(0)).
    // @notice Checks that:
    // 1. All addresses in grantedTo list have the role.
    // 2. All addresses in revokedFrom list do not have the role.
    function _validate(address entity, string memory roleName, OZRoles.Context memory role) internal {
        bytes32 roleHash = keccak256(bytes(roleName)) == keccak256(bytes("DEFAULT_ADMIN_ROLE"))
            ? bytes32(0)
            : keccak256(bytes(roleName));

        for (uint256 i = 0; i < role.grantedTo.length; ++i) {
            bool isRoleGranted = IOZ(entity).hasRole(roleHash, role.grantedTo[i]);
            if (!isRoleGranted) {
                revert OZRoleNotGranted(entity, roleName, role.grantedTo[i]);
            }
        }

        for (uint256 i = 0; i < role.revokedFrom.length; ++i) {
            bool isRoleGranted = IOZ(entity).hasRole(roleHash, role.revokedFrom[i]);
            if (isRoleGranted) {
                revert OZRoleGranted(entity, roleName, role.revokedFrom[i]);
            }
        }

        emit RoleValidated(entity, roleName);
    }
}
