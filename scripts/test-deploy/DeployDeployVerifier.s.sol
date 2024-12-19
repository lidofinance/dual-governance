// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DeployVerifier} from "./DeployVerifier.sol";

contract DeployDeployVerifier is Script {
    function run() external {
        vm.label(msg.sender, "DEPLOYER");

        vm.startBroadcast();

        DeployVerifier deployVerifier = new DeployVerifier();

        vm.stopBroadcast();

        console.log("DeployVerifier address", address(deployVerifier));
    }
}
