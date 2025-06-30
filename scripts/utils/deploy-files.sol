// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable custom-errors */

import {Vm} from "forge-std/Vm.sol";

// solhint-disable-next-line const-name-snakecase
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

library DeployFiles {
    string internal constant DEPLOY_CONFIGS_DIR = "deploy-config";
    string internal constant DEPLOY_ARTIFACTS_DIR = "deploy-artifacts";

    function resolveDeployConfig(string memory fileName) internal view returns (string memory) {
        if (bytes(fileName).length == 0) {
            revert("fileName is empty");
        }
        return string.concat(vm.projectRoot(), "/", DEPLOY_CONFIGS_DIR, "/", fileName);
    }

    function resolveDeployArtifact(string memory fileName) internal view returns (string memory) {
        if (bytes(fileName).length == 0) {
            revert("fileName is empty");
        }
        return string.concat(vm.projectRoot(), "/", DEPLOY_ARTIFACTS_DIR, "/", fileName);
    }
}
