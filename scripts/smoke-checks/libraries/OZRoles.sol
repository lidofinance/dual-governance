// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library OZRolesAssertion {
    struct Context {
        address[] grantedTo;
        address[] revokedFrom;
    }

    function granted(address _grantedTo) internal pure returns (Context memory ctx) {
        ctx.grantedTo = new address[](1);
        ctx.grantedTo[0] = _grantedTo;
        return ctx;
    }

    function granted(address[2] memory _grantedTo) internal pure returns (Context memory ctx) {
        ctx.grantedTo = new address[](2);
        for (uint256 i = 0; i < 2; ++i) {
            ctx.grantedTo[i] = _grantedTo[i];
        }
        return ctx;
    }

    function granted(address[3] memory _grantedTo) internal pure returns (Context memory ctx) {
        ctx.grantedTo = new address[](3);
        for (uint256 i = 0; i < 3; ++i) {
            ctx.grantedTo[i] = _grantedTo[i];
        }
        return ctx;
    }

    function granted(address[4] memory _grantedTo) internal pure returns (Context memory ctx) {
        ctx.grantedTo = new address[](4);
        for (uint256 i = 0; i < 4; ++i) {
            ctx.grantedTo[i] = _grantedTo[i];
        }
        return ctx;
    }

    function revoked(address _revokedFrom) internal pure returns (Context memory ctx) {
        ctx.revokedFrom = new address[](1);
        ctx.revokedFrom[0] = _revokedFrom;
        return ctx;
    }

    function revoked(address[2] memory _revokedFrom) internal pure returns (Context memory ctx) {
        ctx.revokedFrom = new address[](2);
        for (uint256 i = 0; i < 2; ++i) {
            ctx.revokedFrom[i] = _revokedFrom[i];
        }
        return ctx;
    }

    function revoked(address[3] memory _revokedFrom) internal pure returns (Context memory ctx) {
        ctx.revokedFrom = new address[](3);
        for (uint256 i = 0; i < 3; ++i) {
            ctx.revokedFrom[i] = _revokedFrom[i];
        }
        return ctx;
    }

    function revoked(address[4] memory _revokedFrom) internal pure returns (Context memory ctx) {
        ctx.revokedFrom = new address[](4);
        for (uint256 i = 0; i < 4; ++i) {
            ctx.revokedFrom[i] = _revokedFrom[i];
        }
        return ctx;
    }
}
