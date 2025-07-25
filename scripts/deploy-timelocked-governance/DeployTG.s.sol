// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {TimelockedGovernanceDeployConfig} from "../utils/contracts-deployment.sol";
import {DeployFiles} from "../utils/DeployFiles.sol";

contract DeployTG is Script {
    using TimelockedGovernanceDeployConfig for TimelockedGovernanceDeployConfig.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    TimelockedGovernanceDeployConfig.Context internal _config;

    function run() public {
        string memory configFileName = vm.envString("TIMELOCKED_GOVERNANCE_CONFIG_FILE_NAME");
        console.log("Loading config file: %s", configFileName);

        TimelockedGovernanceDeployConfig.Context memory deployConfig =
            TimelockedGovernanceDeployConfig.load(DeployFiles.resolveDeployConfig(configFileName), "");

        deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        vm.startBroadcast();

        TimelockedGovernance timelockedGovernance =
            new TimelockedGovernance(deployConfig.governance, deployConfig.timelock);

        vm.stopBroadcast();

        console.log("TimelockedGovernance deployed successfully at", address(timelockedGovernance));
    }
}
