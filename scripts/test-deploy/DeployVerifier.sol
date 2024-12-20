// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeployVerification} from "../deploy/DeployVerification.sol";
import {DeployConfig, LidoContracts} from "../deploy/Config.sol";

contract DeployVerifier {
    using DeployVerification for DeployVerification.DeployedAddresses;

    event Verified();

    DeployConfig internal _config;
    LidoContracts internal _lidoAddresses;

    constructor(DeployConfig memory config, LidoContracts memory lidoAddresses) {
        _config = config;
        _lidoAddresses = lidoAddresses;
    }

    function verify(
        DeployVerification.DeployedAddresses memory dgDeployedAddresses,
        bool onchainVotingCheck
    ) external {
        dgDeployedAddresses.verify(_config, _lidoAddresses, onchainVotingCheck);

        emit Verified();
    }

    function getConfig() external view returns (DeployConfig memory) {
        return _config;
    }

    function getLidoAddresses() external view returns (LidoContracts memory) {
        return _lidoAddresses;
    }
}
