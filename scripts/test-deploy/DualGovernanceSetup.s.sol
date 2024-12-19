// SPDX-License-Identifier: MIT
/* solhint-disable no-console */

pragma solidity 0.8.26;

import {Timestamps} from "contracts/types/Timestamp.sol";
import {Durations} from "contracts/types/Duration.sol";
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
import {DeployConfig, LidoContracts, getSubCommitteeData} from "../deploy/Config.sol";

import {DeployVerification} from "../deploy/DeployVerification.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";

import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Script} from "forge-std/Script.sol";

contract DualGovernanceSetup is Script {
    struct DeployedAddresses {
        address payable adminExecutor;
        address timelock;
        address emergencyGovernance;
        address resealManager;
        address dualGovernance;
        address tiebreakerCoreCommittee;
        address[] tiebreakerSubCommittees;
    }

    function run() external view {
        address[] memory _tiebreakerSubCommittees = new address[](1);
        _tiebreakerSubCommittees[0] = address(0x990352db3d5Faf1B6A2b3C3aB005fBc0B09fC7a9);
        string memory deployedAddressesFilePath = vm.envString("DEPLOYED_ADDRESSES_FILE_PATH");
        DeployVerification.DeployedAddresses memory _dgContracts = loadDeployedAddresses(deployedAddressesFilePath);
        uint256 emergencyProtectionDuration = 86400;
        uint256 emergencyModeDuration = 86400;
        address _emergencyActivationCommitteeMultisig = address(0x8dA88a400500955E17FaB806DE606B025D033C66);
        address _emergencyExecutionCommitteeMultisig = address(0x7bAd309E8f1501C71f33dBbc843a462dAbF6Eb22);

        // Propose to set Governance, Activation Committee, Execution Committee,  Emergency Mode End Date and Emergency Mode Duration
        ExternalCall[] memory calls;
        uint256 emergencyProtectionEndsAfter = block.timestamp + emergencyProtectionDuration;
        calls = ExternalCallHelpers.create(
            [
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setGovernance.selector, address(_dgContracts.dualGovernance)
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyGovernance.selector, address(_dgContracts.emergencyGovernance)
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyProtectionActivationCommittee.selector,
                        _emergencyActivationCommitteeMultisig
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyProtectionExecutionCommittee.selector,
                        _emergencyExecutionCommitteeMultisig
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyProtectionEndDate.selector, emergencyProtectionEndsAfter
                    )
                }),
                ExternalCall({
                    target: address(_dgContracts.timelock),
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyModeDuration.selector, emergencyModeDuration
                    )
                })
            ]
        );
        console.log("Calls to set DG state:");
        printExternalCalls(calls);

        console.log("Calls encoded:");
        console.logBytes(abi.encode(calls));

        console.log("Encoded \"submitProposal\":");
        console.logBytes(
            abi.encodeWithSelector(
                TimelockedGovernance.submitProposal.selector,
                calls,
                "Reset emergency mode and set original DG as governance"
            )
        );
    }

    function printExternalCalls(ExternalCall[] memory calls) internal pure {
        console.log("[");
        for (uint256 i = 0; i < calls.length; i++) {
            string memory hexPayload = toHexString(calls[i].payload);

            if (i < calls.length - 1) {
                console.log("[\"%s\", %s, \"0x%s\"],", calls[i].target, calls[i].value, hexPayload);
            } else {
                console.log("[\"%s\", %s, \"0x%s\"]", calls[i].target, calls[i].value, hexPayload);
            }
        }
        console.log("]");
    }

    function toHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            str[i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[1 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

    function loadDeployedAddressesFile(string memory deployedAddressesFilePath)
        internal
        view
        returns (string memory deployedAddressesJson)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", deployedAddressesFilePath);
        deployedAddressesJson = vm.readFile(path);
    }

    function loadDeployedAddresses(string memory deployedAddressesFilePath)
        internal
        view
        returns (DeployVerification.DeployedAddresses memory)
    {
        string memory deployedAddressesJson = loadDeployedAddressesFile(deployedAddressesFilePath);

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
}
