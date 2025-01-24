// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, var-name-mixedcase */

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {ConfigFileReader} from "../deploy/config/ConfigFileReader.sol";

string constant CONFIG_FILES_DIR = "deploy-config";

contract TimelockedGovernanceConfigProvider {
    struct DeployConfig {
        address GOVERNANCE;
        address TIMELOCK;
    }

    using ConfigFileReader for ConfigFileReader.Context;

    // solhint-disable-next-line const-name-snakecase
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error InvalidParameter(string parameter);

    string private _configFileName;

    constructor(string memory configFileName) {
        _configFileName = configFileName;
    }

    function loadAndValidate() external view returns (DeployConfig memory config) {
        ConfigFileReader.Context memory configFile = _loadConfigFile();

        config = _parse(configFile);

        _validateConfig(config);
        _printConfig(configFile.content);
    }

    function _parse(ConfigFileReader.Context memory configFile) internal pure returns (DeployConfig memory config) {
        config = DeployConfig({
            GOVERNANCE: configFile.readAddress(".TIMELOCKED_GOVERNANCE.GOVERNANCE"),
            TIMELOCK: configFile.readAddress(".TIMELOCKED_GOVERNANCE.TIMELOCK")
        });
    }

    function _validateConfig(DeployConfig memory config) internal pure {
        if (config.GOVERNANCE == address(0)) {
            revert InvalidParameter("GOVERNANCE");
        }
        if (config.TIMELOCK == address(0)) {
            revert InvalidParameter("TIMELOCK");
        }
    }

    function _printConfig(string memory configFile) internal pure {
        console.log("=================================================");
        console.log("Loaded valid config file:");
        console.log(configFile);
        console.log("=================================================");
    }

    function _loadConfigFile() internal view returns (ConfigFileReader.Context memory configFile) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", CONFIG_FILES_DIR, "/", _configFileName);
        configFile = ConfigFileReader.load(path);
    }
}
