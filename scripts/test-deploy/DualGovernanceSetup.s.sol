// SPDX-License-Identifier: MIT
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

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";

import {console} from "forge-std/console.sol";

contract DualGovernanceSetup {
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
        DeployedAddresses memory _dgContracts = DeployedAddresses(
            payable(0x2eBc9078d98054BEC36b58D3d353F8510b01667A),
            address(0x8AB225606B43fCCf5E045a80129D9721C8AC59A4),
            address(0xF56ebAD4BC30930Bf9Ad35f3B7eD1d72f59e676F),
            address(0xdC016348fad1Db202E7a301112D9aC8f67ce6354),
            address(0xaE3f77a037Ad3a718bA70Dcf9E3612D94691250C),
            address(0x096d26356e28644CaA08dFD5CeeA2C3d87273Fb3),
            _tiebreakerSubCommittees
        );
        uint256 emergencyProtectionDuration = 86400;
        uint256 emergencyModeDuration = 86400;
        address _emergencyActivationCommitteeMultisig = address(0x990352db3d5Faf1B6A2b3C3aB005fBc0B09fC7a9);
        address _emergencyExecutionCommitteeMultisig = address(0x990352db3d5Faf1B6A2b3C3aB005fBc0B09fC7a9);

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
}
