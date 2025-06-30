// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RolesTracker} from "./RolesTracker.sol";

library AragonRoles {
    using RolesTracker for RolesTracker.Context;

    struct Context {
        address manager;
        RolesTracker.Context rolesTracker;
    }

    function manager(address _manager) internal pure returns (Context memory ctx) {
        ctx.manager = _manager;
    }

    function granted(Context memory self, address grantedTo) internal pure returns (Context memory) {
        self.rolesTracker.addGrantedTo(grantedTo);
        return self;
    }

    function revoked(Context memory self, address revokedFrom) internal pure returns (Context memory) {
        self.rolesTracker.addRevokedFrom(revokedFrom);
        return self;
    }
}
