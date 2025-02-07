// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HoleskyMocksDGLaunchVerifier} from "./HoleskyMocksDGLaunchVerifier.sol";

contract DeployHoleskyMocksDGLaunchVerifier is Script {
    function run() public {
        vm.label(msg.sender, "DEPLOYER");

        vm.startBroadcast();

        HoleskyMocksDGLaunchVerifier verifier = new HoleskyMocksDGLaunchVerifier();

        vm.stopBroadcast();

        console.log("HoleskyMocksDGLaunchVerifier deployed successfully at", address(verifier));
    }
}
