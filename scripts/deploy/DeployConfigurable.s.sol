// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGDeployJSONConfigProvider} from "./JsonConfig.s.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DeployConfigurable is DeployBase {
    constructor() {
        string memory chainName = vm.envString("CHAIN");
        string memory configFilePath = vm.envString("DEPLOY_CONFIG_FILE_PATH");

        DGDeployJSONConfigProvider configProvider = new DGDeployJSONConfigProvider(configFilePath);
        config = configProvider.loadAndValidate();
        lidoAddresses = configProvider.getLidoAddresses(chainName);
    }
}
