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

    DeployConfig internal _config;
    LidoContracts internal _lidoAddresses;
    address internal _deployer;
    DeployedContracts internal _contracts;

    function run() public virtual {
        if (_lidoAddresses.chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: _lidoAddresses.chainId});
        }

        _deployer = msg.sender;
        vm.label(_deployer, "DEPLOYER");

        vm.startBroadcast();

        _contracts = DGContractsDeployment.deployDualGovernanceSetup(_config, _lidoAddresses, _deployer);

        vm.stopBroadcast();

        console.log("DG deployed successfully");
        DGContractsSet.print(_contracts);

        console.log("Verifying deploy");

        DeployVerification.verify(_contracts, _config, _lidoAddresses, false);

        console.log(unicode"Verified ✅");
    }
}
