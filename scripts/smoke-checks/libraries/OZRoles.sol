// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library OZRoles {
    struct Context {
        address[] grantedTo;
        address[] revokedFrom;
    }

    function granted(address _grantedTo) internal pure returns (Context memory ctx) {
        return granted(ctx, _grantedTo);
    }

    function granted(Context memory ctx, address _grantedTo) internal pure returns (Context memory) {
        ctx.grantedTo = new address[](1);
        ctx.grantedTo[0] = _grantedTo;
        return ctx;
    }

    function revoked(address _revokedFrom) internal pure returns (Context memory ctx) {
        return revoked(ctx, _revokedFrom);
    }

    function revoked(Context memory ctx, address _revokedFrom) internal pure returns (Context memory) {
        ctx.revokedFrom = new address[](1);
        ctx.revokedFrom[0] = _revokedFrom;

        return ctx;
    }
}
