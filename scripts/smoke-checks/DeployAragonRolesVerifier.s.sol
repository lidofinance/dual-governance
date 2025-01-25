// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AragonRolesVerifier} from "./AragonRolesVerifier.sol";

contract DeployAragonRolesVerifier is Script {
    string internal _rolesFileName;

    constructor() {
        _rolesFileName = vm.envString("ARAGON_ROLES_PERMISSIONS_FILE");
    }

    function run() public {
        vm.label(msg.sender, "DEPLOYER");

        string memory rolesJson = _loadRolesFile();
        AragonRolesVerifier.RoleToVerify[] memory roles = _parseRolesFile(rolesJson);

        console.log("Loaded roles");
        console.log("---------------------------");
        _printRoles(roles);

        vm.startBroadcast();

        AragonRolesVerifier rolesVerifier = new AragonRolesVerifier(roles);

        vm.stopBroadcast();

        console.log("AragonRolesVerifier deployed successfully at", address(rolesVerifier));
    }

    function _loadRolesFile() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/", _rolesFileName);
        return vm.readFile(path);
    }

    function _parseRolesFile(string memory rolesJson)
        internal
        pure
        returns (AragonRolesVerifier.RoleToVerify[] memory)
    {
        bytes memory data = vm.parseJson(rolesJson);
        return abi.decode(data, (AragonRolesVerifier.RoleToVerify[]));
    }

    function _printRoles(AragonRolesVerifier.RoleToVerify[] memory roles) internal pure {
        for (uint256 i = 0; i < roles.length; ++i) {
            console.log("Role", i);
            console.log("Who:", roles[i].who);
            console.log("What:", Strings.toHexString(uint256(roles[i].what)));
            console.log("Where:", roles[i].where);
            console.log("Granted", roles[i].granted);
            console.log("---------------------------");
        }
    }
}
