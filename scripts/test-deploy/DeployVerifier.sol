// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeployVerification} from "../deploy/DeployVerification.sol";
import {DeployConfig, LidoContracts} from "../deploy/Config.sol";
import {DeployedContracts} from "../deploy/ContractsDeployment.sol";

contract DeployVerifier {
    using DeployVerification for DeployVerification.DeployedAddresses;

    event Verified();

    function verify(
        DeployConfig memory config,
        LidoContracts memory lidoAddresses,
        DeployedContracts memory _dgContracts
    ) external {
        address[] memory _tiebreakerSubCommittees = new address[](_dgContracts.tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < _dgContracts.tiebreakerSubCommittees.length; ++i) {
            _tiebreakerSubCommittees[i] = address(_dgContracts.tiebreakerSubCommittees[i]);
        }

        DeployVerification.DeployedAddresses memory dgDeployedAddresses = DeployVerification.DeployedAddresses({
            adminExecutor: payable(address(_dgContracts.adminExecutor)),
            timelock: address(_dgContracts.timelock),
            emergencyGovernance: address(_dgContracts.emergencyGovernance),
            resealManager: address(_dgContracts.resealManager),
            dualGovernance: address(_dgContracts.dualGovernance),
            tiebreakerCoreCommittee: address(_dgContracts.tiebreakerCoreCommittee),
            tiebreakerSubCommittees: _tiebreakerSubCommittees,
            temporaryEmergencyGovernance: address(_dgContracts.temporaryEmergencyGovernance)
        });

        dgDeployedAddresses.verify(config, lidoAddresses);

        emit Verified();
    }
}
