// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RolesTracker} from "./RolesTracker.sol";

library OZRoles {
    using RolesTracker for RolesTracker.Context;

    struct Context {
        RolesTracker.Context rolesTracker;
    }

    function granted(address grantedTo) internal pure returns (Context memory ctx) {
        ctx.rolesTracker.addGrantedTo(grantedTo);
    }

    function granted(Context memory self, address grantedTo) internal pure returns (Context memory) {
        self.rolesTracker.addGrantedTo(grantedTo);
        return self;
    }

    function revoked(address revokedFrom) internal pure returns (Context memory ctx) {
        ctx.rolesTracker.addRevokedFrom(revokedFrom);
    }

    function revoked(Context memory self, address revokedFrom) internal pure returns (Context memory) {
        self.rolesTracker.addRevokedFrom(revokedFrom);
        return self;
    }
}
