//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Duration} from "contracts/types/Duration.sol";
import {DeployConfig, LidoContracts} from "../deploy/config/Config.sol";
import {CONFIG_FILES_DIR, DGDeployConfigProvider} from "../deploy/config/ConfigProvider.sol";
import {DeployedContracts, DGContractsSet} from "../deploy/DeployedContractsSet.sol";
import {DeployVerifier} from "./DeployVerifier.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

contract DeployScriptBase is Script {
    DeployConfig internal _config;
    LidoContracts internal _lidoAddresses;
    DeployedContracts internal _dgContracts;
    string internal _chainName;
    string internal _deployArtifactFileName;
    DeployVerifier internal _deployVerifier;

    function _loadEnv() internal {
        _chainName = vm.envString("CHAIN");
        _deployArtifactFileName = vm.envString("DEPLOY_ARTIFACT_FILE_NAME");

        DGDeployConfigProvider configProvider = new DGDeployConfigProvider(_deployArtifactFileName);

        _config = configProvider.loadAndValidate();
        _lidoAddresses = configProvider.getLidoAddresses(_chainName);
        _dgContracts = DGContractsSet.loadFromFile(_loadDeployedAddressesFile(_deployArtifactFileName));

        console.log("Using the following DG contracts addresses (from file", _deployArtifactFileName, "):");
        console.log("=====================================");
        DGContractsSet.print(_dgContracts);
        console.log("=====================================");

        _deployVerifier = new DeployVerifier(_config, _lidoAddresses);
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

    function _loadDeployedAddressesFile(string memory deployedAddressesFileName)
        internal
        view
        returns (string memory deployedAddressesJson)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", CONFIG_FILES_DIR, "/", deployedAddressesFileName);
        deployedAddressesJson = vm.readFile(path);
    }

    function _encodeExternalCalls(ExternalCall[] memory calls) internal pure returns (bytes memory result) {
        result = abi.encodePacked(bytes4(uint32(1)));

        for (uint256 i = 0; i < calls.length; ++i) {
            ExternalCall memory call = calls[i];
            result = abi.encodePacked(result, bytes20(call.target), bytes4(uint32(call.payload.length)), call.payload);
        }
    }

    function _wait(Duration duration) internal {
        vm.warp(block.timestamp + Duration.unwrap(duration));
    }
}
