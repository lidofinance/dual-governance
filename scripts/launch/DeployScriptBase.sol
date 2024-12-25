//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations, Duration} from "contracts/types/Duration.sol";
import {Executor} from "contracts/Executor.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";
import {IEscrowBase} from "contracts/interfaces/IEscrowBase.sol";
import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {Escrow} from "contracts/Escrow.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {State} from "contracts/libraries/DualGovernanceStateMachine.sol";
import {IWithdrawalQueue} from "test/utils/interfaces/IWithdrawalQueue.sol";

import {IAragonForwarder} from "test/utils/interfaces/IAragonAgent.sol";

import {DeployConfig, LidoContracts} from "../deploy/Config.sol";
import {DGDeployJSONConfigProvider} from "../deploy/JsonConfig.s.sol";
import {DeployVerification} from "../deploy/DeployVerification.sol";
import {DeployVerifier} from "./DeployVerifier.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";

contract DeployScriptBase is Script {
    using DeployVerification for DeployVerification.DeployedAddresses;

    DeployConfig internal _config;
    LidoContracts internal _lidoAddresses;
    DeployVerification.DeployedAddresses internal _dgContracts;
    string internal _chainName;
    string internal _configFilePath;
    string internal _deployedAddressesFilePath;
    DeployVerifier internal _deployVerifier;

    function _loadEnv() internal {
        _chainName = vm.envString("CHAIN");
        _configFilePath = vm.envString("DEPLOY_CONFIG_FILE_PATH");
        _deployedAddressesFilePath = vm.envString("DEPLOYED_ADDRESSES_FILE_PATH");

        DGDeployJSONConfigProvider configProvider = new DGDeployJSONConfigProvider(_configFilePath);

        _config = configProvider.loadAndValidate();
        _lidoAddresses = configProvider.getLidoAddresses(_chainName);
        _dgContracts = _loadDeployedAddresses(_deployedAddressesFilePath);

        console.log("Deployed DG contracts");
        console.log("=====================================");
        _printAddresses(_dgContracts);
        console.log("=====================================");

        _deployVerifier = new DeployVerifier(_config, _lidoAddresses);
    }

    function _printExternalCalls(ExternalCall[] memory calls) internal pure {
        console.log("[");
        for (uint256 i = 0; i < calls.length; i++) {
            string memory hexPayload = _toHexString(calls[i].payload);

            if (i < calls.length - 1) {
                console.log("[\"%s\", %s, \"0x%s\"],", calls[i].target, calls[i].value, hexPayload);
            } else {
                console.log("[\"%s\", %s, \"0x%s\"]", calls[i].target, calls[i].value, hexPayload);
            }
        }
        console.log("]");
    }

    function _toHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            str[i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[1 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

    function _loadDeployedAddresses(string memory deployedAddressesFilePath)
        internal
        view
        returns (DeployVerification.DeployedAddresses memory)
    {
        string memory deployedAddressesJson = _loadDeployedAddressesFile(deployedAddressesFilePath);

        return DeployVerification.DeployedAddresses({
            adminExecutor: payable(stdJson.readAddress(deployedAddressesJson, ".ADMIN_EXECUTOR")),
            timelock: stdJson.readAddress(deployedAddressesJson, ".TIMELOCK"),
            emergencyGovernance: stdJson.readAddress(deployedAddressesJson, ".EMERGENCY_GOVERNANCE"),
            resealManager: stdJson.readAddress(deployedAddressesJson, ".RESEAL_MANAGER"),
            dualGovernance: stdJson.readAddress(deployedAddressesJson, ".DUAL_GOVERNANCE"),
            tiebreakerCoreCommittee: stdJson.readAddress(deployedAddressesJson, ".TIEBREAKER_CORE_COMMITTEE"),
            tiebreakerSubCommittees: stdJson.readAddressArray(deployedAddressesJson, ".TIEBREAKER_SUB_COMMITTEES"),
            temporaryEmergencyGovernance: stdJson.readAddress(deployedAddressesJson, ".TEMPORARY_EMERGENCY_GOVERNANCE")
        });
    }

    function _printAddresses(DeployVerification.DeployedAddresses memory res) internal pure {
        console.log("Using the following DG contracts addresses");
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

    function _loadDeployedAddressesFile(string memory deployedAddressesFilePath)
        internal
        view
        returns (string memory deployedAddressesJson)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", deployedAddressesFilePath);
        deployedAddressesJson = vm.readFile(path);
    }

    function _encodeExternalCalls(ExternalCall[] memory calls) internal pure returns (bytes memory result) {
        result = abi.encodePacked(bytes4(uint32(1)));

        for (uint256 i = 0; i < calls.length; ++i) {
            ExternalCall memory call = calls[i];
            result = abi.encodePacked(result, bytes20(call.target), bytes4(uint32(call.payload.length)), call.payload);
        }
    }

    function _wait(Duration duration) internal {
        vm.warp(block.timestamp + Duration.unwrap(duration));
    }
}
