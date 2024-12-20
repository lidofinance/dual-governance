// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DeployScriptBase} from "./DeployScriptBase.sol";
import {DeployVerifier} from "./DeployVerifier.sol";

contract DeployDeployVerifier is DeployScriptBase {
    function run() external {
        vm.label(msg.sender, "DEPLOYER");

        _loadEnv();

        vm.startBroadcast();

        DeployVerifier deployVerifier = new DeployVerifier(_config, _lidoAddresses);

        vm.stopBroadcast();

        console.log("DeployVerifier address", address(deployVerifier));
    }
}
