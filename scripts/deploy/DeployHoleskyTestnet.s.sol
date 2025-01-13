// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeployConfigurable} from "./DeployConfigurable.s.sol";
import {DGDeployTOMLConfigProvider} from "./TomlConfig.s.sol";

contract DeployHoleskyTestnet is DeployConfigurable {
    function _getChainName() internal override returns (string memory) {
        return "holesky";
    }

    function _getConfigFileName() internal override returns (string memory) {
        return "deploy-config-holesky-testnet.toml";
    }
}
