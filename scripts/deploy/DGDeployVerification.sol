// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGDeployConfig, DGDeployedContracts} from "scripts/deploy/ContractsDeploymentNew.sol";

library DGDeployVerification {
    function verify(DGDeployConfig.Context memory config, DGDeployedContracts.Context memory contracts) internal view {
        // TODO: implement all checks from the DeployVerification lib
    }
}
