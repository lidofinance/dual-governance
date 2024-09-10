// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployConfig} from "./DeployConfig.sol";
import {DGDeployConfigProvider} from "./Config.s.sol";
import {DeployDGContracts, DeployedContracts} from "./DeployContracts.sol";
import {DeployValidation} from "./DeployValidation.sol";

contract DeployDG is Script {
    using DeployValidation for DeployValidation.DeployResult;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    DeployConfig internal config;
    address private deployer;
    uint256 private pk;
    string private chainName;
    uint256 private chainId;

    /* TODO:    constructor(string memory _chainName, uint256 _chainId) {
        chainName = _chainName;
        chainId = _chainId;
    } */

    function run() external {
        DGDeployConfigProvider configProvider = new DGDeployConfigProvider();
        config = configProvider.loadAndValidate();

        if (config.chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: chainId});
        }

        pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(pk);
        vm.label(deployer, "DEPLOYER");

        vm.startBroadcast(pk);

        DeployedContracts memory contracts = DeployDGContracts.deployDualGovernanceSetup(config, deployer);

        vm.stopBroadcast();

        DeployValidation.DeployResult memory res = getDeployedAddresses(contracts);

        printAddresses(res);

        console.log("Verifying deploy");

        res.check();

        console.log(unicode"Verified ✅");
    }

    function getDeployedAddresses(DeployedContracts memory contracts)
        internal
        pure
        returns (DeployValidation.DeployResult memory)
    {
        return DeployValidation.DeployResult({
            adminExecutor: payable(address(contracts.adminExecutor)),
            timelock: address(contracts.timelock),
            emergencyGovernance: address(contracts.emergencyGovernance),
            emergencyActivationCommittee: address(contracts.emergencyActivationCommittee),
            emergencyExecutionCommittee: address(contracts.emergencyExecutionCommittee),
            resealManager: address(contracts.resealManager),
            dualGovernance: address(contracts.dualGovernance),
            resealCommittee: address(contracts.resealCommittee),
            tiebreakerCoreCommittee: address(contracts.tiebreakerCoreCommittee),
            tiebreakerSubCommittees: contracts.tiebreakerSubCommittees
        });
    }

    function printAddresses(DeployValidation.DeployResult memory res) internal pure {
        console.log("DG deployed successfully");
        console.log("DualGovernance address", res.dualGovernance);
        console.log("ResealManager address", res.resealManager);
        console.log("TiebreakerCoreCommittee address", res.tiebreakerCoreCommittee);

        for (uint256 i = 0; i < config.TIEBREAKER_SUB_COMMITTEES_COUNT; ++i) {
            console.log("TiebreakerSubCommittee #", i, "address", contracts.tiebreakerSubCommittees[i]);
        }

        console.log("AdminExecutor address", res.adminExecutor);
        console.log("EmergencyProtectedTimelock address", res.timelock);
        console.log("EmergencyGovernance address", res.emergencyGovernance);
        console.log("EmergencyActivationCommittee address", res.emergencyActivationCommittee);
        console.log("EmergencyExecutionCommittee address", res.emergencyExecutionCommittee);
        console.log("ResealCommittee address", res.resealCommittee);
    }
}
