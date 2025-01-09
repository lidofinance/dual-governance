// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployConfig, LidoContracts} from "./Config.sol";
import {DGDeployJSONConfigProvider} from "./JsonConfig.s.sol";
import {DeployedContracts, DGContractsSet} from "./DeployedContractsSet.sol";
import {DeployVerification} from "./DeployVerification.sol";

contract Verify is Script {
    DeployConfig internal _config;
    LidoContracts internal _lidoAddresses;

    function run() external {
        string memory chainName = vm.envString("CHAIN");
        string memory _configFilePath = vm.envString("DEPLOY_CONFIG_FILE_PATH");
        string memory deployedAddressesFilePath = vm.envString("DEPLOYED_ADDRESSES_FILE_PATH");
        bool onchainVotingCheck = vm.envBool("ONCHAIN_VOTING_CHECK_MODE");

        DGDeployJSONConfigProvider configProvider = new DGDeployJSONConfigProvider(_configFilePath);
        _config = configProvider.loadAndValidate();
        _lidoAddresses = configProvider.getLidoAddresses(chainName);

        DeployedContracts memory contracts =
            DGContractsSet.loadFromFile(loadDeployedAddressesFile(deployedAddressesFilePath));

        console.log("Using the following DG contracts addresses");
        DGContractsSet.print(contracts);

        console.log("Verifying deploy");

        DeployVerification.verify(contracts, _config, _lidoAddresses, onchainVotingCheck);

        console.log(unicode"Verified ✅");
    }

    function loadDeployedAddressesFile(string memory deployedAddressesFilePath)
        internal
        view
        returns (string memory deployedAddressesJson)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", deployedAddressesFilePath);
        deployedAddressesJson = vm.readFile(path);
    }
}
