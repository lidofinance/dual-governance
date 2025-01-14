// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {CONFIG_FILES_DIR, DGDeployTOMLConfigProvider} from "./TomlConfig.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {DGContractsSet} from "./DeployedContractsSet.sol";
import {SerializedJson, SerializedJsonLib} from "../utils/SerializedJson.sol";

contract DeployConfigurable is DeployBase {
    using SerializedJsonLib for SerializedJson;

    DGDeployTOMLConfigProvider internal _configProvider;
    string internal _chainName;
    string internal _configFileName;

    constructor() {
        _chainName = _getChainName();
        _configFileName = _getConfigFileName();

        _configProvider = new DGDeployTOMLConfigProvider(_configFileName);
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
        addrsJson.set("EMERGENCY_ACTIVATION_COMMITTEE", _config.EMERGENCY_ACTIVATION_COMMITTEE);
        addrsJson.set("EMERGENCY_EXECUTION_COMMITTEE", _config.EMERGENCY_EXECUTION_COMMITTEE);
        addrsJson.set("RESEAL_COMMITTEE", _config.RESEAL_COMMITTEE);
        addrsJson.set("chainName", _chainName);
        addrsJson.set("timestamp", block.timestamp);
    }

    function _saveDeployedAddressesToFile(string memory deployedAddrsJson) internal {
        string memory addressesFileName =
            string.concat("deployed-addrs-", _chainName, "-", Strings.toString(block.timestamp), ".json");
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", CONFIG_FILES_DIR, "/", addressesFileName);

        stdJson.write(deployedAddrsJson, path);

        console.log("The deployed contracts' addresses are saved to file", path);
    }

    function _getChainName() internal virtual returns (string memory) {
        return vm.envString("CHAIN");
    }

    function _getConfigFileName() internal virtual returns (string memory) {
        return vm.envString("DEPLOY_CONFIG_FILE_NAME");
    }
}
