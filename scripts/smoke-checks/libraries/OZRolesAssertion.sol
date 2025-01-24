// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library OZRolesAssertion {
    struct Context {
        address[] grantedTo;
    }

    function grant(address _grantedTo) internal pure returns (Context memory ctx) {
        ctx.grantedTo = new address[](1);
        ctx.grantedTo[0] = _grantedTo;
        return ctx;
    }

    function grant(address[2] memory _grantedTo) internal pure returns (Context memory ctx) {
        ctx.grantedTo = new address[](2);
        for (uint256 i = 0; i < 2; ++i) {
            ctx.grantedTo[i] = _grantedTo[i];
        }
        return ctx;
    }

    function grant(address[3] memory _grantedTo) internal pure returns (Context memory ctx) {
        ctx.grantedTo = new address[](3);
        for (uint256 i = 0; i < 3; ++i) {
            ctx.grantedTo[i] = _grantedTo[i];
        }
        return ctx;
    }

    function grant(address[4] memory _grantedTo) internal pure returns (Context memory ctx) {
        ctx.grantedTo = new address[](4);
        for (uint256 i = 0; i < 4; ++i) {
            ctx.grantedTo[i] = _grantedTo[i];
        }
        return ctx;
    }

    /* function grantedTo(Context memory ctx, address _grantedTo) internal pure returns (Context memory) {
        ctx.grantedTo = new address[](1);
        ctx.grantedTo[0] = _grantedTo;
        return ctx;
    } */
}
