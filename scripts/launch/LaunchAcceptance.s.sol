// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, custom-errors, reason-string */

// import {console} from "forge-std/Test.sol";

// import {DeployScriptBase} from "./DeployScriptBase.sol";
// import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
// import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
// import {ExternalCallHelpers} from "test/utils/executor-calls.sol";
// import {LidoUtils} from "test/utils/lido-utils.sol";

// import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
// import {IAragonForwarder} from "test/utils/interfaces/IAragonForwarder.sol";
// import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
// import {IAragonACL} from "test/utils/interfaces/IAragonACL.sol";
// import {IAragonAgent} from "test/utils/interfaces/IAragonAgent.sol";
// import {IGovernance} from "contracts/interfaces/IDualGovernance.sol";

// import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

// import {DeployVerification} from "../utils/DeployVerification.sol";

// contract LaunchAcceptance is DeployScriptBase {
//     using LidoUtils for LidoUtils.Context;

//     function run() external {
//         _loadEnv();

//         uint256 fromStep = vm.envUint("FROM_STEP");
//         require(fromStep < 10, "Invalid value of env variable FROM_STEP, should not exceed 10");

//         console.log("========= Starting from step ", fromStep, " =========");

//         IEmergencyProtectedTimelock timelock = _dgContracts.timelock;

//         uint256 proposalId = 1;

//         if (fromStep == 0) {
//             DeployVerification.verify(_deployArtifact);
//         } else {
//             console.log("STEP 0 SKIPPED - All contracts are deployed");
//         }

//         if (fromStep <= 1) {
//             console.log("STEP 1 - Activate Emergency Mode");
//             // Activate Dual Governance Emergency Mode
//             vm.prank(_config.timelock.emergencyActivationCommittee);
//             timelock.activateEmergencyMode();

//             console.log("Emergency mode activated");
//         } else {
//             console.log("STEP 1 SKIPPED - Emergency Mode already activated");
//         }

//         if (fromStep <= 2) {
//             console.log("STEP 2 - Reset Emergency Mode");
//             // Check pre-conditions for emergency mode reset
//             require(timelock.isEmergencyModeActive() == true, "Emergency mode is not active");

//             // Emergency Committee execute emergencyReset()
//             vm.prank(_config.timelock.emergencyExecutionCommittee);
//             timelock.emergencyReset();

//             console.log("Emergency mode reset");
//         } else {
//             console.log("STEP 2 SKIPPED - Emergency Mode already reset");
//         }

//         if (fromStep <= 3) {
//             console.log("STEP 3 - Set DG state");
//             require(
//                 timelock.getGovernance() == address(_dgContracts.emergencyGovernance),
//                 "Incorrect governance address in EmergencyProtectedTimelock"
//             );
//             require(timelock.isEmergencyModeActive() == false, "Emergency mode is active");

//             // Propose to set Governance, Activation Committee, Execution Committee,  Emergency Mode End Date and Emergency Mode Duration
//             ExternalCall[] memory calls;
//             uint256 emergencyProtectionEndsAfter = _config.timelock.emergencyProtectionEndDate.toSeconds();
//             calls = ExternalCallHelpers.create(
//                 [
//                     ExternalCall({
//                         target: address(timelock),
//                         value: 0,
//                         payload: abi.encodeWithSelector(timelock.setGovernance.selector, address(_dgContracts.dualGovernance))
//                     }),
//                     ExternalCall({
//                         target: address(timelock),
//                         value: 0,
//                         payload: abi.encodeWithSelector(
//                             timelock.setEmergencyGovernance.selector, address(_dgContracts.emergencyGovernance)
//                         )
//                     }),
//                     ExternalCall({
//                         target: address(timelock),
//                         value: 0,
//                         payload: abi.encodeWithSelector(
//                             timelock.setEmergencyProtectionActivationCommittee.selector,
//                             _config.timelock.emergencyActivationCommittee
//                         )
//                     }),
//                     ExternalCall({
//                         target: address(timelock),
//                         value: 0,
//                         payload: abi.encodeWithSelector(
//                             timelock.setEmergencyProtectionExecutionCommittee.selector,
//                             _config.timelock.emergencyExecutionCommittee
//                         )
//                     }),
//                     ExternalCall({
//                         target: address(timelock),
//                         value: 0,
//                         payload: abi.encodeWithSelector(
//                             timelock.setEmergencyProtectionEndDate.selector, emergencyProtectionEndsAfter
//                         )
//                     }),
//                     ExternalCall({
//                         target: address(timelock),
//                         value: 0,
//                         payload: abi.encodeWithSelector(
//                             timelock.setEmergencyModeDuration.selector, _config.timelock.emergencyModeDuration.toSeconds()
//                         )
//                     })
//                 ]
//             );

//             if (fromStep == 3) {
//                 console.log("Calls to set DG state:");
//                 console.logBytes(abi.encode(calls));

//                 console.log("Calls encoded:");
//                 console.logBytes(abi.encode(calls));

//                 console.log("Submit proposal to set DG state calldata");
//                 console.logBytes(
//                     abi.encodeWithSelector(
//                         IGovernance.submitProposal.selector,
//                         calls,
//                         "Reset emergency mode and set original DG as governance"
//                     )
//                 );
//             }

//             vm.prank(_config.);
//             proposalId = _dgContracts.temporaryEmergencyGovernance.submitProposal(
//                 calls, "Reset emergency mode and set original DG as governance"
//             );

//             console.log("Proposal submitted");

//             console.log("Proposal ID", proposalId);
//         } else {
//             console.log("STEP 3 SKIPPED - DG state proposal already submitted");
//         }

//         // if (fromStep <= 4) {
//         //     console.log("STEP 4 - Execute proposal");
//         //     // Schedule and execute the proposal
//         //     vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY.toSeconds());
//         //     _dgContracts.temporaryEmergencyGovernance.scheduleProposal(proposalId);
//         //     vm.warp(block.timestamp + _config.AFTER_SCHEDULE_DELAY.toSeconds());
//         //     timelock.execute(proposalId);

//         //     console.log("Proposal executed");
//         // } else {
//         //     console.log("STEP 4 SKIPPED - Proposal to set DG state already executed");
//         // }

//         // if (fromStep <= 5) {
//         //     console.log("STEP 5 - Verify DG state");
//         //     // Verify state after proposal execution
//         //     require(
//         //         timelock.getGovernance() == address(_dgContracts.dualGovernance),
//         //         "Incorrect governance address in EmergencyProtectedTimelock"
//         //     );
//         //     require(
//         //         timelock.getEmergencyGovernance() == address(_dgContracts.emergencyGovernance),
//         //         "Incorrect governance address in EmergencyProtectedTimelock"
//         //     );
//         //     require(timelock.isEmergencyModeActive() == false, "Emergency mode is not active");
//         //     require(
//         //         timelock.getEmergencyActivationCommittee() == _config.EMERGENCY_ACTIVATION_COMMITTEE,
//         //         "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
//         //     );
//         //     require(
//         //         timelock.getEmergencyExecutionCommittee() == _config.EMERGENCY_EXECUTION_COMMITTEE,
//         //         "Incorrect emergencyExecutionCommittee address in EmergencyProtectedTimelock"
//         //     );
//         //     IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
//         //         timelock.getEmergencyProtectionDetails();
//         //     require(
//         //         details.emergencyModeDuration == _config.EMERGENCY_MODE_DURATION,
//         //         "Incorrect emergencyModeDuration in EmergencyProtectedTimelock"
//         //     );
//         //     require(
//         //         details.emergencyProtectionEndsAfter == _config.EMERGENCY_PROTECTION_END_DATE,
//         //         "Incorrect emergencyProtectionEndsAfter in EmergencyProtectedTimelock"
//         //     );
//         // } else {
//         //     console.log("STEP 5 SKIPPED - DG state already verified");
//         // }

//         // if (fromStep <= 6) {
//         //     console.log("STEP 6 - Submitting DAO Voting proposal to activate Dual Governance");

//         //     // Prepare RolesVerifier
//         //     // TODO: Sync with the actual voting script roles checker
//         //     address[] memory ozContracts = new address[](1);
//         //     RolesVerifier.OZRoleInfo[] memory roles = new RolesVerifier.OZRoleInfo[](2);
//         //     address[] memory pauseRoleHolders = new address[](2);
//         //     pauseRoleHolders[0] = address(0x79243345eDbe01A7E42EDfF5900156700d22611c);
//         //     pauseRoleHolders[1] = address(_dgContracts.resealManager);
//         //     address[] memory resumeRoleHolders = new address[](1);
//         //     resumeRoleHolders[0] = address(_dgContracts.resealManager);

//         //     ozContracts[0] = address(_lidoUtils.withdrawalQueue);

//         //     roles[0] =
//         //         RolesVerifier.OZRoleInfo({role: _lidoUtils.withdrawalQueue.PAUSE_ROLE(), accounts: pauseRoleHolders});
//         //     roles[1] =
//         //         RolesVerifier.OZRoleInfo({role: _lidoUtils.withdrawalQueue.RESUME_ROLE(), accounts: resumeRoleHolders});

//         //     _rolesVerifier = new RolesVerifier(ozContracts, roles);

//         //     // DAO Voting to activate Dual Governance
//         //     // Prepare calls to execute by Agent
//         //     ExternalCall[] memory roleGrantingCalls;
//         //     roleGrantingCalls = ExternalCallHelpers.create(
//         //         [
//         //             ExternalCall({
//         //                 target: address(_lidoUtils.withdrawalQueue),
//         //                 value: 0,
//         //                 payload: abi.encodeWithSelector(
//         //                     IAccessControl.grantRole.selector,
//         //                     IWithdrawalQueue(_lidoUtils.withdrawalQueue).PAUSE_ROLE(),
//         //                     address(_dgContracts.resealManager)
//         //                 )
//         //             }),
//         //             ExternalCall({
//         //                 target: address(_lidoUtils.withdrawalQueue),
//         //                 value: 0,
//         //                 payload: abi.encodeWithSelector(
//         //                     IAccessControl.grantRole.selector,
//         //                     IWithdrawalQueue(_lidoUtils.withdrawalQueue).RESUME_ROLE(),
//         //                     address(_dgContracts.resealManager)
//         //                 )
//         //             }),
//         //             ExternalCall({
//         //                 target: address(_lidoUtils.acl),
//         //                 value: 0,
//         //                 payload: abi.encodeWithSelector(
//         //                     IAragonACL.grantPermission.selector,
//         //                     address(_dgContracts.adminExecutor),
//         //                     _lidoUtils.agent,
//         //                     IAragonAgent(_lidoUtils.agent).RUN_SCRIPT_ROLE()
//         //                 )
//         //             })
//         //         ]
//         //     );

//         //     // Propose to revoke Agent forward permission from Voting
//         //     ExternalCall[] memory revokeAgentForwardCall;
//         //     revokeAgentForwardCall = ExternalCallHelpers.create(
//         //         [
//         //             ExternalCall({
//         //                 target: address(_lidoUtils.acl),
//         //                 value: 0,
//         //                 payload: abi.encodeWithSelector(
//         //                     IAragonACL.revokePermission.selector,
//         //                     _lidoUtils.voting,
//         //                     _lidoUtils.agent,
//         //                     IAragonAgent(_lidoUtils.agent).RUN_SCRIPT_ROLE()
//         //                 )
//         //             })
//         //         ]
//         //     );

//         //     ExternalCall[] memory revokeAgentForwardCallDualGovernanceProposal;
//         //     revokeAgentForwardCallDualGovernanceProposal = ExternalCallHelpers.create(
//         //         [
//         //             ExternalCall({
//         //                 target: address(_lidoUtils.agent),
//         //                 value: 0,
//         //                 payload: abi.encodeWithSelector(
//         //                     IAragonForwarder.forward.selector, _encodeExternalCalls(revokeAgentForwardCall)
//         //                 )
//         //             })
//         //         ]
//         //     );

//         //     // Prepare calls to execute Voting
//         //     bytes memory setPermissionPayload = abi.encodeWithSelector(
//         //         IAragonACL.setPermissionManager.selector,
//         //         _lidoUtils.agent,
//         //         _lidoUtils.agent,
//         //         IAragonAgent(_lidoUtils.agent).RUN_SCRIPT_ROLE()
//         //     );

//         //     bytes memory forwardRolePayload =
//         //         abi.encodeWithSelector(IAragonForwarder.forward.selector, _encodeExternalCalls(roleGrantingCalls));

//         //     bytes memory verifyOZRolesPayload = abi.encodeWithSelector(RolesVerifier.verifyOZRoles.selector);

//         //     bytes memory submitProposalPayload = abi.encodeWithSelector(
//         //         IGovernance.submitProposal.selector,
//         //         revokeAgentForwardCallDualGovernanceProposal,
//         //         "Revoke Agent forward permission from Voting"
//         //     );

//         //     ExternalCall[] memory activateCalls = ExternalCallHelpers.create(
//         //         [
//         //             ExternalCall({target: address(_lidoUtils.acl), value: 0, payload: setPermissionPayload}),
//         //             ExternalCall({target: address(_lidoUtils.agent), value: 0, payload: forwardRolePayload}),
//         //             // TODO: set real RolesVerifier contract address
//         //             // ExternalCall({target: address(_rolesVerifier), value: 0, payload: verifyOZRolesPayload}),
//         //             ExternalCall({target: address(_dgContracts.dualGovernance), value: 0, payload: submitProposalPayload})
//         //         ]
//         //     );
//         //     uint256 voteId =
//         //         _lidoUtils.adoptVote("Dual Governance activation vote", _encodeExternalCalls(activateCalls));
//         //     console.log("Vote ID", voteId);
//         // } else {
//         //     console.log("STEP 6 SKIPPED - Dual Governance activation vote already submitted");
//         // }

//         // if (fromStep <= 7) {
//         //     uint256 voteId = 0;
//         //     require(voteId != 0);
//         //     console.log("STEP 7 - Enacting DAO Voting proposal to activate Dual Governance");
//         //     _lidoUtils.executeVote(voteId);
//         // } else {
//         //     console.log("STEP 7 SKIPPED - Dual Governance activation vote already executed");
//         // }

//         // if (fromStep <= 8) {
//         //     console.log("STEP 8 - Wait for Dual Governance after submit delay and enacting proposal");

//         //     uint256 expectedProposalId = 2;

//         //     // Schedule and execute the proposal
//         //     _wait(_config.AFTER_SUBMIT_DELAY);
//         //     _dgContracts.dualGovernance.scheduleProposal(expectedProposalId);
//         //     _wait(_config.AFTER_SCHEDULE_DELAY);
//         //     timelock.execute(expectedProposalId);
//         // } else {
//         //     console.log("STEP 8 SKIPPED - Dual Governance proposal already executed");
//         // }

//         // if (fromStep <= 9) {
//         //     console.log("STEP 9 - Verify DAO has no agent forward permission from Voting");
//         //     // Verify that Voting has no permission to forward to Agent
//         //     ExternalCall[] memory someAgentForwardCall;
//         //     someAgentForwardCall = ExternalCallHelpers.create(
//         //         [
//         //             ExternalCall({
//         //                 target: address(_lidoUtils.acl),
//         //                 value: 0,
//         //                 payload: abi.encodeWithSelector(
//         //                     IAragonACL.revokePermission.selector,
//         //                     address(_dgContracts.adminExecutor),
//         //                     _lidoUtils.agent,
//         //                     IAragonAgent(_lidoUtils.agent).RUN_SCRIPT_ROLE()
//         //                 )
//         //             })
//         //         ]
//         //     );

//         //     vm.expectRevert("AGENT_CAN_NOT_FORWARD");
//         //     vm.prank(_lidoUtils.voting);
//         //     IAragonForwarder(_lidoUtils.agent).forward(_encodeExternalCalls(someAgentForwardCall));
//         // } else {
//         //     console.log("STEP 9 SKIPPED - Agent forward permission already revoked");
//         // }
//     }
// }
