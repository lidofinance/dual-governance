// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HoleskyMocksLidoRolesValidator} from "./HoleskyMocksLidoRolesValidator.sol";

contract DeployHoleskyMocksLidoRolesValidator is Script {
    function run() public {
        vm.label(msg.sender, "DEPLOYER");

        vm.startBroadcast();

        HoleskyMocksLidoRolesValidator rolesValidator = new HoleskyMocksLidoRolesValidator();

        vm.stopBroadcast();

        console.log("HoleskyMocksLidoRolesValidator deployed successfully at", address(rolesValidator));
    }
}
