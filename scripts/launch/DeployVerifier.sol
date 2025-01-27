// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeployedContracts} from "../deploy/DeployedContractsSet.sol";
import {DeployVerification} from "../deploy/DeployVerification.sol";
import {DeployConfig, LidoContracts} from "../deploy/config/Config.sol";
import {DeployConfigStorage} from "../utils/DeployConfigStorage.sol";

contract DeployVerifier is DeployConfigStorage {
    event Verified();

    LidoContracts internal _lidoAddresses;

    constructor(DeployConfig memory config, LidoContracts memory lidoAddresses) {
        _fillConfig(config);
        _lidoAddresses = lidoAddresses;
    }

    function verify(DeployedContracts memory dgContracts, bool onchainVotingCheck) external {
        DeployVerification.checkContractsConfiguration(dgContracts, _config, onchainVotingCheck);

        emit Verified();
    }

    function getConfig() external view returns (DeployConfig memory) {
        return _config;
    }

    function getLidoAddresses() external view returns (LidoContracts memory) {
        return _lidoAddresses;
    }
}
