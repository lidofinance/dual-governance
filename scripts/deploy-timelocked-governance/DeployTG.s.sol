// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {DeployConfig} from "./Config.sol";
import {TimelockedGovernanceConfigProvider} from "./ConfigProvider.sol";
import {DGContractsDeployment} from "../deploy/ContractsDeployment.sol";

contract DeployTG is Script {
    error ChainIdMismatch(uint256 actual, uint256 expected);

    DeployConfig internal _config;
    address internal _deployer;
    TimelockedGovernanceConfigProvider internal _configProvider;
    string internal _chainName;
    string internal _configFileName;

    constructor() {
        _chainName = _getChainName();
        _configFileName = _getConfigFileName();

        _configProvider = new TimelockedGovernanceConfigProvider(_configFileName);
        _config = _configProvider.loadAndValidate();
    }

    function run() public {
        _deployer = msg.sender;
        vm.label(_deployer, "DEPLOYER");

        vm.startBroadcast();

        TimelockedGovernance timelockedGovernance =
            DGContractsDeployment.deployTimelockedGovernance(_config.GOVERNANCE, ITimelock(_config.TIMELOCK));

        vm.stopBroadcast();

        console.log("TimelockedGovernance deployed successfully at", address(timelockedGovernance));
    }

    function _getChainName() internal virtual returns (string memory) {
        return vm.envString("CHAIN");
    }

    function _getConfigFileName() internal virtual returns (string memory) {
        return vm.envString("TIMELOCKED_GOVERNANCE_CONFIG_FILE_NAME");
    }
}
