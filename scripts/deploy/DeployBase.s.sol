// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployConfig, LidoContracts} from "./Config.sol";
import {DeployedContracts, DGContractsSet} from "./DeployedContractsSet.sol";
import {DGContractsDeployment} from "./ContractsDeployment.sol";
import {DeployVerification} from "./DeployVerification.sol";

abstract contract DeployBase is Script {
    error ChainIdMismatch(uint256 actual, uint256 expected);

    DeployConfig internal config;
    LidoContracts internal lidoAddresses;
    address private deployer;

    function run() external {
        if (lidoAddresses.chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: lidoAddresses.chainId});
        }

        deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");

        vm.startBroadcast();

        DeployedContracts memory contracts =
            DGContractsDeployment.deployDualGovernanceSetup(config, lidoAddresses, deployer);

        vm.stopBroadcast();

        console.log("DG deployed successfully");
        DGContractsSet.print(contracts);

        console.log("Verifying deploy");

        DeployVerification.verify(contracts, config, lidoAddresses, false);

        console.log(unicode"Verified ✅");
    }
}
