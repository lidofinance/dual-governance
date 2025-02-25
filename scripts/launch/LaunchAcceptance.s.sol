// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, custom-errors, reason-string */

import {console} from "forge-std/Test.sol";

import {DeployScriptBase} from "./DeployScriptBase.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";

import {IAragonForwarder} from "test/utils/interfaces/IAragonForwarder.sol";
import {IAragonACL} from "test/utils/interfaces/IAragonACL.sol";
import {IAragonAgent} from "test/utils/interfaces/IAragonAgent.sol";
import {IGovernance} from "contracts/interfaces/IDualGovernance.sol";

import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";

import {DeployVerification} from "../utils/DeployVerification.sol";

import {DGSetupDeployArtifacts, DGSetupDeployConfig} from "../utils/contracts-deployment.sol";

import {HoleskyDryRunDAOVotingCalldataProvider} from "./HoleskyDryRunDAOVotingCalldataProvider.sol";

contract LaunchAcceptance is DeployScriptBase {
    using LidoUtils for LidoUtils.Context;

    function run() external {
        address daoEmergencyGovernance = 0x3B20930B143F21C4a837a837cBBcd15ac0B93504;

        DGSetupDeployArtifacts.Context memory _deployArtifact = _loadEnv();

        DGSetupDeployConfig.Context memory _config = _deployArtifact.deployConfig;
        uint256 fromStep = vm.envUint("FROM_STEP");
        require(fromStep < 10, "Invalid value of env variable FROM_STEP, should not exceed 10");

        console.log("========= Starting from step ", fromStep, " =========");

        IEmergencyProtectedTimelock timelock = _dgContracts.timelock;

        uint256 proposalId = 1;

        if (fromStep == 0) {
            DeployVerification.verify(_deployArtifact);
        } else {
            console.log("STEP 0 SKIPPED - All contracts are deployed");
        }

        if (fromStep <= 1) {
            console.log("STEP 1 - Activate Emergency Mode");
            // Activate Dual Governance Emergency Mode
            vm.prank(_config.timelock.emergencyActivationCommittee);
            timelock.activateEmergencyMode();

            console.log("Emergency mode activated");
        } else {
            console.log("STEP 1 SKIPPED - Emergency Mode already activated");
        }

        if (fromStep <= 2) {
            console.log("STEP 2 - Reset Emergency Mode");
            // Check pre-conditions for emergency mode reset
            require(timelock.isEmergencyModeActive() == true, "Emergency mode is not active");

            // Emergency Committee execute emergencyReset()
            vm.prank(_config.timelock.emergencyExecutionCommittee);
            timelock.emergencyReset();

            console.log("Emergency mode reset");
        } else {
            console.log("STEP 2 SKIPPED - Emergency Mode already reset");
        }

        if (fromStep <= 3) {
            console.log("STEP 3 - Set DG state");
            require(
                timelock.getGovernance() == address(_dgContracts.emergencyGovernance),
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(timelock.isEmergencyModeActive() == false, "Emergency mode is active");

            // Propose to set Governance, Activation Committee, Execution Committee,  Emergency Mode End Date and Emergency Mode Duration
            ExternalCall[] memory calls;

            calls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(timelock.setGovernance.selector, address(_dgContracts.dualGovernance))
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(timelock.setEmergencyGovernance.selector, daoEmergencyGovernance)
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyProtectionActivationCommittee.selector,
                            _config.timelock.emergencyActivationCommittee
                        )
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyProtectionExecutionCommittee.selector,
                            _config.timelock.emergencyExecutionCommittee
                        )
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyProtectionEndDate.selector,
                            _config.timelock.emergencyProtectionEndDate.toSeconds()
                        )
                    }),
                    ExternalCall({
                        target: address(timelock),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            timelock.setEmergencyModeDuration.selector, _config.timelock.emergencyModeDuration.toSeconds()
                        )
                    })
                ]
            );

            if (fromStep == 3) {
                console.log("Calls to set DG state:");
                console.logBytes(abi.encode(calls));

                console.log("Calls encoded:");
                console.logBytes(abi.encode(calls));

                console.log("Submit proposal to set DG state calldata");
                console.logBytes(
                    abi.encodeWithSelector(
                        IGovernance.submitProposal.selector,
                        calls,
                        "Reset emergency mode and set original DG as governance"
                    )
                );
            }

            vm.prank(_config.timelock.emergencyGovernanceProposer);
            proposalId = _dgContracts.emergencyGovernance.submitProposal(
                calls, "Reset emergency mode and set original DG as governance"
            );

            console.log("Proposal submitted");

            console.log("Proposal ID", proposalId);
        } else {
            console.log("STEP 3 SKIPPED - DG state proposal already submitted");
        }

        if (fromStep <= 4) {
            console.log("STEP 4 - Execute proposal");
            // Schedule and execute the proposal
            vm.warp(block.timestamp + _config.timelock.afterSubmitDelay.toSeconds());
            _dgContracts.emergencyGovernance.scheduleProposal(proposalId);
            vm.warp(block.timestamp + _config.timelock.afterScheduleDelay.toSeconds());
            timelock.execute(proposalId);

            _dgContracts.emergencyGovernance = TimelockedGovernance(daoEmergencyGovernance);

            console.log("Proposal executed");

            console.log("Emergency Governance set to", address(_dgContracts.emergencyGovernance));
        } else {
            console.log("STEP 4 SKIPPED - Proposal to set DG state already executed");
        }

        if (fromStep <= 5) {
            console.log("STEP 5 - Verify DG state");
            // Verify state after proposal execution
            require(
                timelock.getGovernance() == address(_dgContracts.dualGovernance),
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(
                timelock.getEmergencyGovernance() == address(_dgContracts.emergencyGovernance),
                "Incorrect governance address in EmergencyProtectedTimelock"
            );
            require(timelock.isEmergencyModeActive() == false, "Emergency mode is not active");
            require(
                timelock.getEmergencyActivationCommittee() == _config.timelock.emergencyActivationCommittee,
                "Incorrect emergencyActivationCommittee address in EmergencyProtectedTimelock"
            );
            require(
                timelock.getEmergencyExecutionCommittee() == _config.timelock.emergencyExecutionCommittee,
                "Incorrect emergencyExecutionCommittee address in EmergencyProtectedTimelock"
            );
            IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details =
                timelock.getEmergencyProtectionDetails();
            require(
                details.emergencyModeDuration == _config.timelock.emergencyModeDuration,
                "Incorrect emergencyModeDuration in EmergencyProtectedTimelock"
            );
            require(
                details.emergencyProtectionEndsAfter == _config.timelock.emergencyProtectionEndDate,
                "Incorrect emergencyProtectionEndsAfter in EmergencyProtectedTimelock"
            );
        } else {
            console.log("STEP 5 SKIPPED - DG state already verified");
        }

        if (fromStep <= 6) {
            console.log("STEP 6 - Submitting DAO Voting proposal to activate Dual Governance");

            bytes memory _encodedDAOVotingCalls = HoleskyDryRunDAOVotingCalldataProvider.votingCalldata();
            uint256 voteId = _lidoUtils.adoptVotePreparedBytecode(_encodedDAOVotingCalls);
            console.log("Vote ID", voteId);
        } else {
            console.log("STEP 6 SKIPPED - Dual Governance activation vote already submitted");
        }

        if (fromStep <= 7) {
            uint256 voteId = 503;
            require(voteId != 0);
            console.log("STEP 7 - Enacting DAO Voting proposal to activate Dual Governance");
            _lidoUtils.executeVote(voteId);
        } else {
            console.log("STEP 7 SKIPPED - Dual Governance activation vote already executed");
        }

        if (fromStep <= 8) {
            console.log("STEP 8 - Wait for Dual Governance after submit delay and enacting proposal");

            uint256 expectedProposalId = 2;

            // Schedule and execute the proposal
            _wait(_config.timelock.afterSubmitDelay);
            _dgContracts.dualGovernance.scheduleProposal(expectedProposalId);
            _wait(_config.timelock.afterScheduleDelay);
            timelock.execute(expectedProposalId);
        } else {
            console.log("STEP 8 SKIPPED - Dual Governance proposal already executed");
        }

        if (fromStep <= 9) {
            console.log("STEP 9 - Verify DAO has no agent forward permission from Voting");
            // Verify that Voting has no permission to forward to Agent
            ExternalCall[] memory someAgentForwardCall;
            someAgentForwardCall = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(_lidoUtils.acl),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            IAragonACL.revokePermission.selector,
                            address(_dgContracts.adminExecutor),
                            _lidoUtils.agent,
                            IAragonAgent(_lidoUtils.agent).RUN_SCRIPT_ROLE()
                        )
                    })
                ]
            );

            vm.expectRevert("ACL_AUTH_NO_MANAGER");
            vm.prank(address(_lidoUtils.voting));
            IAragonForwarder(_lidoUtils.agent).forward(_encodeExternalCalls(someAgentForwardCall));
        } else {
            console.log("STEP 9 SKIPPED - Agent forward permission already revoked");
        }
    }
}
