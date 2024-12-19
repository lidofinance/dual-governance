// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployConfig, LidoContracts} from "./Config.sol";
import {DGContractsDeployment, DeployedContracts} from "./ContractsDeployment.sol";
import {DeployVerification} from "./DeployVerification.sol";

abstract contract DeployBase is Script {
    using DeployVerification for DeployVerification.DeployedAddresses;

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

        DeployVerification.DeployedAddresses memory res = getDeployedAddresses(contracts);

        printAddresses(res);

        console.log("Verifying deploy");

        res.verify(config, lidoAddresses, false);

        console.log(unicode"Verified ✅");
    }

    function getDeployedAddresses(DeployedContracts memory contracts)
        internal
        pure
        returns (DeployVerification.DeployedAddresses memory)
    {
        address[] memory tiebreakerSubCommittees = new address[](contracts.tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < contracts.tiebreakerSubCommittees.length; ++i) {
            tiebreakerSubCommittees[i] = address(contracts.tiebreakerSubCommittees[i]);
        }

        return DeployVerification.DeployedAddresses({
            adminExecutor: payable(address(contracts.adminExecutor)),
            timelock: address(contracts.timelock),
            emergencyGovernance: address(contracts.emergencyGovernance),
            resealManager: address(contracts.resealManager),
            dualGovernance: address(contracts.dualGovernance),
            tiebreakerCoreCommittee: address(contracts.tiebreakerCoreCommittee),
            tiebreakerSubCommittees: tiebreakerSubCommittees,
            temporaryEmergencyGovernance: address(contracts.temporaryEmergencyGovernance)
        });
    }

    function printAddresses(DeployVerification.DeployedAddresses memory res) internal pure {
        console.log("DG deployed successfully");
        console.log("DualGovernance address", res.dualGovernance);
        console.log("ResealManager address", res.resealManager);
        console.log("TiebreakerCoreCommittee address", res.tiebreakerCoreCommittee);

        for (uint256 i = 0; i < res.tiebreakerSubCommittees.length; ++i) {
            console.log("TiebreakerSubCommittee #", i, "address", res.tiebreakerSubCommittees[i]);
        }

        console.log("AdminExecutor address", res.adminExecutor);
        console.log("EmergencyProtectedTimelock address", res.timelock);
        console.log("EmergencyGovernance address", res.emergencyGovernance);
        console.log("TemporaryEmergencyGovernance address", res.temporaryEmergencyGovernance);
    }
}
