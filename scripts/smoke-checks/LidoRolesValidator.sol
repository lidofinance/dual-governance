// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AragonRolesAssertion} from "./libraries/AragonRolesAssertion.sol";
import {OZRolesAssertion} from "./libraries/OZRolesAssertion.sol";

interface IACL {
    function hasPermission(address _who, address _where, bytes32 _what) external view returns (bool);
    function getPermissionManager(address _app, bytes32 _role) external view returns (address);
}

interface IOZAccessControl {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

abstract contract LidoRolesValidator {
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

    function _validate(address entity, string memory roleName, AragonRolesAssertion.Context memory role) internal {
        bytes32 roleNameHash = keccak256(bytes(roleName));
        if (role.manager != address(0)) {
            address roleManager = ACL.getPermissionManager(entity, roleNameHash);
            if (roleManager != role.manager) {
                revert AragonPermissionInvalidManager(entity, roleName, role.manager, roleManager);
            }
        }

        for (uint256 i = 0; i < role.grantedTo.length; ++i) {
            bool isPermissionGranted = ACL.hasPermission(entity, role.grantedTo[i], roleNameHash);
            if (!isPermissionGranted) {
                revert AragonPermissionNotGranted(entity, roleName, role.grantedTo[i]);
            }
        }

        for (uint256 i = 0; i < role.revokedFrom.length; ++i) {
            bool isPermissionGranted = ACL.hasPermission(entity, role.revokedFrom[i], roleNameHash);
            if (isPermissionGranted) {
                revert AragonPermissionGranted(entity, roleName, role.revokedFrom[i]);
            }
        }

        emit RoleValidated(entity, roleName);
    }

    function _validate(address entity, string memory roleName, OZRolesAssertion.Context memory role) internal {
        for (uint256 i = 0; i < role.grantedTo.length; ++i) {
            bool isRoleGranted = IOZAccessControl(entity).hasRole(keccak256(bytes(roleName)), role.grantedTo[i]);
            if (!isRoleGranted) {
                revert OZRoleNotGranted(entity, roleName, role.grantedTo[i]);
            }
        }
        emit RoleValidated(entity, roleName);
    }
}
