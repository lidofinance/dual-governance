// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {CONFIG_FILES_DIR, DGDeployJSONConfigProvider} from "./JsonConfig.s.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {DGContractsSet} from "./DeployedContractsSet.sol";
import {SerializedJson} from "../utils/SerializedJson.sol";

contract DeployConfigurable is DeployBase {
    DGDeployJSONConfigProvider internal _configProvider;
    string internal _chainName;
    string internal _configFileName;

    constructor() {
        _chainName = vm.envString("CHAIN");
        _configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");

        _configProvider = new DGDeployJSONConfigProvider(_configFileName);
        _config = _configProvider.loadAndValidate();
        _lidoAddresses = _configProvider.getLidoAddresses(_chainName);
    }

    function run() public override {
        super.run();

        SerializedJson memory addrsJson = _serializeDeployedContracts();

        _configProvider.writeDeployedAddressesToConfigFile(addrsJson.str);
        _saveDeployedAddressesToFile(addrsJson.str);
    }

    function _serializeDeployedContracts() internal returns (SerializedJson memory addrsJson) {
        addrsJson = DGContractsSet.serialize(_contracts);
        addrsJson.str = stdJson.serialize(
            addrsJson.serializationId, "EMERGENCY_ACTIVATION_COMMITTEE", _config.EMERGENCY_ACTIVATION_COMMITTEE
        );
        addrsJson.str = stdJson.serialize(
            addrsJson.serializationId, "EMERGENCY_EXECUTION_COMMITTEE", _config.EMERGENCY_EXECUTION_COMMITTEE
        );
        addrsJson.str = stdJson.serialize(addrsJson.serializationId, "RESEAL_COMMITTEE", _config.RESEAL_COMMITTEE);
        addrsJson.str = stdJson.serialize(addrsJson.serializationId, "chainName", _chainName);
        addrsJson.str = stdJson.serialize(addrsJson.serializationId, "timestamp", block.timestamp);
    }

    function _saveDeployedAddressesToFile(string memory deployedAddrsJson) internal {
        string memory addressesFileName = string.concat("deployed-addrs-", Strings.toString(block.timestamp), ".json");
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", CONFIG_FILES_DIR, "/", addressesFileName);

        stdJson.write(deployedAddrsJson, path);

        console.log("The deployed contracts' addresses are saved to file", path);
    }
}
