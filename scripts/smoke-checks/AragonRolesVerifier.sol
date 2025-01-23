// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ACL {
    function hasPermission(address _who, address _where, bytes32 _what) external view returns (bool);
}

contract AragonRolesVerifier {
    struct RoleToVerify {
        // Do not change the fields order, it should be sorted alphabetically: granted, what, where, who
        bool granted;
        bytes32 what;
        address where;
        address who;
    }

    address public constant ACL_ADDRESS = 0xfd1E42595CeC3E83239bf8dFc535250e7F48E0bC;

    RoleToVerify[] public rolesToVerify;

    constructor(RoleToVerify[] memory _rolesToVerify) {
        for (uint256 i = 0; i < _rolesToVerify.length; i++) {
            rolesToVerify.push(_rolesToVerify[i]);
        }
    }

    function verify() public view {
        ACL acl = ACL(ACL_ADDRESS);
        for (uint256 i = 0; i < rolesToVerify.length; i++) {
            bool isPermissionGranted =
                acl.hasPermission(rolesToVerify[i].who, rolesToVerify[i].where, rolesToVerify[i].what);
            assert(isPermissionGranted == rolesToVerify[i].granted);
        }
    }
}
