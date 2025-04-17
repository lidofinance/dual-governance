// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DGSetupDeployArtifacts, DGSetupDeployedContracts} from "./contracts-deployment.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {Duration} from "contracts/types/Duration.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";

contract DGDeployArtifactLoader is Script {
    using DGSetupDeployArtifacts for DGSetupDeployArtifacts.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;

    error InvalidChainId(uint256 chainId);

    DGSetupDeployedContracts.Context internal _dgContracts;
    LidoUtils.Context internal _lidoUtils;

    function _loadEnv() internal returns (DGSetupDeployArtifacts.Context memory _deployArtifact) {
        string memory deployArtifactFileName = vm.envString("DEPLOY_ARTIFACT_FILE_NAME");

        console.log("Loading config from artifact file: %s", deployArtifactFileName);

        _deployArtifact = DGSetupDeployArtifacts.load(deployArtifactFileName);
        _dgContracts = _deployArtifact.deployedContracts;

        if (_deployArtifact.deployConfig.chainId != block.chainid) {
            revert InvalidChainId(_deployArtifact.deployConfig.chainId);
        }

        if (_deployArtifact.deployConfig.chainId == 1) {
            _lidoUtils = LidoUtils.mainnet();
        } else if (_deployArtifact.deployConfig.chainId == 17000) {
            _lidoUtils = LidoUtils.holesky();
        } else if (_deployArtifact.deployConfig.chainId == 560048) {
            _lidoUtils = LidoUtils.hoodi();
        } else {
            revert InvalidChainId(_deployArtifact.deployConfig.chainId);
        }

        console.log("Using the following DG contracts addresses (from file", deployArtifactFileName, "):");
        _dgContracts.print();
    }

    function _printExternalCalls(ExternalCall[] memory calls) internal pure {
        console.log("[");
        for (uint256 i = 0; i < calls.length; i++) {
            string memory hexPayload = _toHexString(calls[i].payload);

            if (i < calls.length - 1) {
                console.log("[\"%s\", %s, \"0x%s\"],", calls[i].target, calls[i].value, hexPayload);
            } else {
                console.log("[\"%s\", %s, \"0x%s\"]", calls[i].target, calls[i].value, hexPayload);
            }
        }
        console.log("]");
    }

    function _toHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            str[i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[1 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

    function _wait(Duration duration) internal {
        vm.warp(block.timestamp + Duration.unwrap(duration));
    }
}
