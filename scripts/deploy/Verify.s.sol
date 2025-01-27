// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployConfig, LidoContracts} from "./config/Config.sol";
import {CONFIG_FILES_DIR, DGDeployConfigProvider} from "./config/ConfigProvider.sol";
import {DeployedContracts, DGContractsSet} from "./DeployedContractsSet.sol";
import {DeployVerification} from "./DeployVerification.sol";
import {DeployConfigStorage} from "../utils/DeployConfigStorage.sol";

contract Verify is Script, DeployConfigStorage {
    LidoContracts internal _lidoAddresses;

    function run() external {
        string memory deployArtifactFileName = vm.envString("DEPLOY_ARTIFACT_FILE_NAME");
        bool onchainVotingCheck = vm.envBool("ONCHAIN_VOTING_CHECK_MODE");

        DGDeployConfigProvider configProvider = new DGDeployConfigProvider(deployArtifactFileName);
        _fillConfig(configProvider.loadAndValidate());
        _lidoAddresses = configProvider.getLidoAddresses();

        DeployedContracts memory contracts =
            DGContractsSet.loadFromFile(_loadDeployArtifactFile(deployArtifactFileName));

        console.log("Using the following DG contracts addresses (from file", deployArtifactFileName, "):");
        DGContractsSet.print(contracts);

        console.log("Verifying deploy");

        DeployVerification.verify(contracts, _config, _lidoAddresses, onchainVotingCheck);

        console.log(unicode"Verified ✅");
    }

    function _loadDeployArtifactFile(string memory deployArtifactFileName)
        internal
        view
        returns (string memory deployedAddressesJson)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", CONFIG_FILES_DIR, "/", deployArtifactFileName);
        deployedAddressesJson = vm.readFile(path);
    }
}
