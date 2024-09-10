// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGDeployConfigProvider} from "./EnvConfig.s.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DeployConfigurable is DeployBase {
    constructor() {
        string memory chainName = vm.envString("CHAIN");
        DGDeployConfigProvider configProvider = new DGDeployConfigProvider();
        config = configProvider.loadAndValidate();
        lidoAddresses = configProvider.getLidoAddresses(chainName);
    }
}
