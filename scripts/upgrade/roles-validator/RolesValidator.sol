// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AragonRoles} from "./libraries/AragonRoles.sol";
import {OZRoles} from "./libraries/OZRoles.sol";

interface IACL {
    function hasPermission(address _who, address _where, bytes32 _what) external view returns (bool);
    function getPermissionManager(address _app, bytes32 _role) external view returns (address);
}

interface IOZAccessControl {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

abstract contract RolesValidator {
    event RoleValidated(address entity, string roleName);

    error OZRoleNotGranted(address entity, string roleName, address app);
    error AragonPermissionInvalidManager(
        address entity, string roleName, address expectedManager, address actualManager
    );
    error AragonPermissionGranted(address entity, string roleName, address app);
    error AragonPermissionNotGranted(address entity, string roleName, address app);

    IACL public immutable ACL;

    constructor(address acl) {
        ACL = IACL(acl);
    }

    function _validate(address entity, string memory roleName, AragonRoles.Context memory role) internal {
        bytes32 roleNameHash = keccak256(bytes(roleName));
        if (role.manager != address(0)) {
            address roleManager = ACL.getPermissionManager(entity, roleNameHash);
            if (roleManager != role.manager) {
                revert AragonPermissionInvalidManager(entity, roleName, role.manager, roleManager);
            }
        }

        for (uint256 i = 0; i < role.grantedTo.length; ++i) {
            bool isPermissionGranted = ACL.hasPermission(role.grantedTo[i], entity, roleNameHash);
            if (!isPermissionGranted) {
                revert AragonPermissionNotGranted(entity, roleName, role.grantedTo[i]);
            }
        }

        for (uint256 i = 0; i < role.revokedFrom.length; ++i) {
            bool isPermissionGranted = ACL.hasPermission(role.revokedFrom[i], entity, roleNameHash);
            if (isPermissionGranted) {
                revert AragonPermissionGranted(entity, roleName, role.revokedFrom[i]);
            }
        }

        emit RoleValidated(entity, roleName);
    }

    function _validate(address entity, string memory roleName, OZRoles.Context memory role) internal {
        for (uint256 i = 0; i < role.grantedTo.length; ++i) {
            bytes32 roleHash = keccak256(bytes(roleName)) == keccak256(bytes("DEFAULT_ADMIN_ROLE"))
                ? bytes32(0)
                : keccak256(bytes(roleName));
            bool isRoleGranted = IOZAccessControl(entity).hasRole(roleHash, role.grantedTo[i]);
            if (!isRoleGranted) {
                revert OZRoleNotGranted(entity, roleName, role.grantedTo[i]);
            }
        }
        emit RoleValidated(entity, roleName);
    }
}
