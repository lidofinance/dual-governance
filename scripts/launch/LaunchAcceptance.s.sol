// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console, custom-errors, reason-string */

import {console} from "forge-std/Test.sol";

import {DGDeployArtifactLoader} from "../utils/DGDeployArtifactLoader.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ExternalCallHelpers} from "test/utils/executor-calls.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";

import {IAragonForwarder} from "test/utils/interfaces/IAragonForwarder.sol";
import {IAragonACL} from "test/utils/interfaces/IAragonACL.sol";
import {IAragonAgent} from "test/utils/interfaces/IAragonAgent.sol";
import {IGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";

import {Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";

import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";

import {DeployVerification} from "../utils/DeployVerification.sol";

import {DGSetupDeployArtifacts, DGSetupDeployConfig} from "../utils/contracts-deployment.sol";

contract LaunchAcceptance is DGDeployArtifactLoader {
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
            uint256 dgProposalId = _dgContracts.emergencyGovernance.submitProposal(
                calls, "Reset emergency mode and set original DG as governance"
            );

            console.log("DG Proposal submitted");

            console.log("DG Proposal ID", dgProposalId);
        } else {
            console.log("STEP 3 SKIPPED - DG state proposal already submitted");
        }

        if (fromStep <= 4) {
            console.log("STEP 4 - Execute DG proposal to set DG state");

            uint256 dgProposalId = _dgContracts.timelock.getProposalsCount();
            vm.warp(block.timestamp + _config.timelock.afterSubmitDelay.toSeconds());
            vm.assertTrue(_dgContracts.timelock.canSchedule(dgProposalId));

            _dgContracts.emergencyGovernance.scheduleProposal(proposalId);
            ITimelock.ProposalDetails memory proposalDetails = _dgContracts.timelock.getProposalDetails(dgProposalId);
            assert(proposalDetails.status == ProposalStatus.Scheduled);

            console.log("DG Proposal scheduled: ", dgProposalId);
        } else {
            console.log("STEP 4 SKIPPED - DG Proposal to set DG state already scheduled");
        }

        if (fromStep <= 5) {
            console.log("STEP 5 - Execute proposal");

            uint256 dgProposalId = _dgContracts.timelock.getProposalsCount();
            vm.warp(block.timestamp + _config.timelock.afterScheduleDelay.toSeconds());
            vm.assertTrue(_dgContracts.timelock.canExecute(dgProposalId));

            timelock.execute(dgProposalId);

            _dgContracts.emergencyGovernance = TimelockedGovernance(daoEmergencyGovernance);
            ITimelock.ProposalDetails memory proposalDetails = _dgContracts.timelock.getProposalDetails(dgProposalId);
            assert(proposalDetails.status == ProposalStatus.Executed);

            console.log("DG proposal executed: ", dgProposalId);

            console.log("Emergency Governance set to", address(_dgContracts.emergencyGovernance));
        } else {
            console.log("STEP 5 SKIPPED - Proposal to set DG state already executed");
        }

        if (fromStep <= 6) {
            console.log("STEP 6 - Verify DG state");
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

            console.log("Submitting DAO Voting proposal to activate Dual Governance");
            uint256 voteId = _lidoUtils.adoptVoteEVMScript(_dgActivationVotingCalldata, "Activate Dual Governance");
            console.log("Vote ID", voteId);
        } else {
            console.log("STEP 6 SKIPPED - Dual Governance activation vote already submitted");
        }

        if (fromStep <= 7) {
            console.log("STEP 7 - Enacting DAO Voting proposal to activate Dual Governance");
            uint256 voteId = _lidoUtils.getLastVoteId();
            console.log("Enacting vote with ID", voteId);
            _lidoUtils.executeVote(voteId);
        } else {
            console.log("STEP 7 SKIPPED - Dual Governance activation vote already executed");
        }

        if (fromStep <= 8) {
            console.log("STEP 8 - Wait for Dual Governance after submit delay");

            _wait(_config.timelock.afterSubmitDelay);

            uint256 dgProposalId = _dgContracts.timelock.getProposalsCount();
            vm.assertTrue(_dgContracts.timelock.canSchedule(dgProposalId));

            console.log("Scheduling DG proposal with ID", dgProposalId);
            _dgContracts.dualGovernance.scheduleProposal(dgProposalId);

            ITimelock.ProposalDetails memory proposalDetails = _dgContracts.timelock.getProposalDetails(dgProposalId);
            assert(proposalDetails.status == ProposalStatus.Scheduled);

            console.log("DG Proposal scheduled: ", dgProposalId);
        } else {
            console.log("STEP 8 SKIPPED - Dual Governance proposal already scheduled");
        }

        if (fromStep <= 9) {
            console.log("STEP 9 - Wait for Dual Governance after schedule delay and execute proposal");

            uint256 dgProposalId = _dgContracts.timelock.getProposalsCount();
            _wait(_config.timelock.afterScheduleDelay);
            vm.assertTrue(_dgContracts.timelock.canExecute(dgProposalId));

            console.log("Executing proposal with ID", dgProposalId);
            timelock.execute(dgProposalId);

            ITimelock.ProposalDetails memory proposalDetails = _dgContracts.timelock.getProposalDetails(dgProposalId);
            assert(proposalDetails.status == ProposalStatus.Executed);

            console.log("DG proposal executed: ", dgProposalId);
        } else {
            console.log("STEP 9 SKIPPED - Dual Governance proposal already executed");
        }

        if (fromStep <= 10) {
            console.log("STEP 10 - Verify DAO has no agent forward permission from Voting");
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
            console.log("Agent forward permission revoked");
        } else {
            console.log("STEP 10 SKIPPED - Agent forward permission already revoked");
        }
    }
}
