// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {stdJson} from "forge-std/StdJson.sol";
import {DGDeployJSONConfigProvider} from "./JsonConfig.s.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {DGContractsSet} from "./DeployedContractsSet.sol";
import {SerializedJson} from "../utils/SerializedJson.sol";

contract DeployConfigurable is DeployBase {
    DGDeployJSONConfigProvider internal _configProvider;
    string internal _chainName;
    string internal _configFilePath;

    constructor() {
        _chainName = vm.envString("CHAIN");
        _configFilePath = vm.envString("DEPLOY_CONFIG_FILE_PATH");

        _configProvider = new DGDeployJSONConfigProvider(_configFilePath);
        _config = _configProvider.loadAndValidate();
        _lidoAddresses = _configProvider.getLidoAddresses(_chainName);
    }

    function run() public override {
        super.run();

        SerializedJson memory addrsJson = _serializeDeployedContracts();

        _configProvider.writeDeployedAddressesToConfigFile(addrsJson.str);
        // TODO: write to deployed-addrs-timestamp.json
    }

    function _serializeDeployedContracts() internal returns (SerializedJson memory addrsJson) {
        addrsJson = DGContractsSet.serialize(_contracts);
        addrsJson.str =
            stdJson.serialize(addrsJson.ref, "EMERGENCY_ACTIVATION_COMMITTEE", _config.EMERGENCY_ACTIVATION_COMMITTEE);
        addrsJson.str =
            stdJson.serialize(addrsJson.ref, "EMERGENCY_EXECUTION_COMMITTEE", _config.EMERGENCY_EXECUTION_COMMITTEE);
        addrsJson.str = stdJson.serialize(addrsJson.ref, "RESEAL_COMMITTEE", _config.RESEAL_COMMITTEE);
        addrsJson.str = stdJson.serialize(addrsJson.ref, "chainName", _chainName);
        addrsJson.str = stdJson.serialize(addrsJson.ref, "timestamp", block.timestamp);
    }
}
