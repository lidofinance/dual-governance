// SPDX-License-Identifier: MIT
/* solhint-disable no-console */

pragma solidity 0.8.26;

import {DeployScriptBase} from "./DeployScriptBase.sol";
import {DGDeployJSONConfigProvider} from "../deploy/JsonConfig.s.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";

import {console} from "forge-std/console.sol";

contract DualGovernanceSetup is DeployScriptBase {
    function run() external {
        _loadEnv();

        // Propose to set Governance, Activation Committee, Execution Committee,  Emergency Mode End Date and Emergency Mode Duration
        ExternalCall[] memory calls;
        uint256 emergencyProtectionEndsAfter = block.timestamp + _config.EMERGENCY_PROTECTION_DURATION.toSeconds();

        calls = ExternalCallHelpers.create(
            [
                ExternalCall({
                    target: _dgContracts.timelock,
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setGovernance.selector, _dgContracts.dualGovernance
                    )
                }),
                ExternalCall({
                    target: _dgContracts.timelock,
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyGovernance.selector, _dgContracts.emergencyGovernance
                    )
                }),
                ExternalCall({
                    target: _dgContracts.timelock,
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyProtectionActivationCommittee.selector,
                        _config.EMERGENCY_ACTIVATION_COMMITTEE
                    )
                }),
                ExternalCall({
                    target: _dgContracts.timelock,
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyProtectionExecutionCommittee.selector,
                        _config.EMERGENCY_EXECUTION_COMMITTEE
                    )
                }),
                ExternalCall({
                    target: _dgContracts.timelock,
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyProtectionEndDate.selector, emergencyProtectionEndsAfter
                    )
                }),
                ExternalCall({
                    target: _dgContracts.timelock,
                    value: 0,
                    payload: abi.encodeWithSelector(
                        IEmergencyProtectedTimelock.setEmergencyModeDuration.selector, _config.EMERGENCY_MODE_DURATION
                    )
                })
            ]
        );
        console.log("Calls to set DG state:");
        _printExternalCalls(calls);

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
}
