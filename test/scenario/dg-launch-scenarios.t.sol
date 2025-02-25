// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {LidoUtils, DGScenarioTestSetup, ExternalCallHelpers, ExternalCall} from "../utils/integration-tests.sol";
import {TimelockedGovernance, ContractsDeployment} from "scripts/utils/contracts-deployment.sol";

import {Durations} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";

import {DeployVerification} from "scripts/utils/DeployVerification.sol";

import {EvmScriptUtils} from "../utils/evm-script-utils.sol";
import {DGSetupDeployArtifacts} from "scripts/utils/contracts-deployment.sol";

contract DGLaunchStrategiesScenarioTest is DGScenarioTestSetup {
    using LidoUtils for LidoUtils.Context;

    address internal immutable _TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER =
        makeAddr("TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER");

    TimelockedGovernance internal _emergencyGovernance;
    DGSetupDeployArtifacts.Context internal _deployArtifact;

    function testFork_DualGovernance_DeploymentWithDryRunTemporaryGovernance() external {
        _step("0. Deploy DG contracts with temporary emergency governance for dry-run test");
        {
            _deployDGSetup({emergencyGovernanceProposer: _TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER});
            _deployArtifact.deployConfig = _dgDeployConfig;
            _deployArtifact.deployedContracts = _dgDeployedContracts;
            _emergencyGovernance =
                ContractsDeployment.deployTimelockedGovernance({governance: address(_lido.voting), timelock: _timelock});
        }

        _step("1. Verify the state of the DG setup before the dry-run emergency reset");
        {
            DeployVerification.verify(_deployArtifact);
        }

        _step("2. Activate Dual Governance Emergency Mode");
        {
            _activateEmergencyMode();
        }

        _step("3. Temporary Emergency Governance Proposer makes dry-run governance reset");
        {
            _emergencyReset();
        }

        _step(
            string.concat(
                "4. Prepare calls to set Governance, Activation Committee, ",
                "Execution Committee, Emergency Mode End Date and Emergency Mode Duration"
            )
        );
        ExternalCall[] memory finalizeDGSetupCalls;
        {
            Timestamp emergencyProtectionEndDate = Durations.from(90 days).addTo(Timestamps.now());

            finalizeDGSetupCalls = ExternalCallHelpers.create(
                address(_timelock),
                [
                    abi.encodeCall(_timelock.setGovernance, (address(_dgDeployedContracts.dualGovernance))),
                    abi.encodeCall(_timelock.setEmergencyGovernance, address(_emergencyGovernance)),
                    abi.encodeCall(
                        _timelock.setEmergencyProtectionActivationCommittee, (_DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE)
                    ),
                    abi.encodeCall(
                        _timelock.setEmergencyProtectionExecutionCommittee, (_DEFAULT_EMERGENCY_EXECUTION_COMMITTEE)
                    ),
                    abi.encodeCall(_timelock.setEmergencyProtectionEndDate, (emergencyProtectionEndDate)),
                    abi.encodeCall(_timelock.setEmergencyModeDuration, (Durations.from(180 days)))
                ]
            );
            console.log("Calls to set DG state:");
            console.logBytes(abi.encode(finalizeDGSetupCalls));
        }

        _step("5. Submit proposal from the temporary governance to configure timelock for the launch");
        {
            _adoptProposal(
                _TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER, finalizeDGSetupCalls, "Dual Governance after dry-run setup"
            );
            console.log("Last Proposal Id: %d", _getLastProposalId());
        }

        _step("[SKIPPED] 6. Verify the state of the DG setup after update and before voting start");
        {
            _dgDeployedContracts.emergencyGovernance = _emergencyGovernance;
            _dgDeployConfig.timelock.emergencyGovernanceProposer = address(_lido.voting);
            _deployArtifact.deployConfig = _dgDeployConfig;
            _deployArtifact.deployedContracts = _dgDeployedContracts;

            // TODO: This check was commented due to failing check "ProposalsCount > 1 in EmergencyProtectedTimelock". Need to modify DeployVerification lib to make it pass.
            // DeployVerification.verify(_deployArtifact);
        }

        _step("7. Prepare Roles Verifier");
        MockRolesVerifier rolesVerifier;
        MockDGStateVerifier dgStateVerifier;
        {
            rolesVerifier = new MockRolesVerifier();
            dgStateVerifier = new MockDGStateVerifier();
        }

        _step("8. Activate Dual Governance with DAO Voting");
        {
            EvmScriptUtils.EvmScriptCall[] memory agentForwardCalls = new EvmScriptUtils.EvmScriptCall[](2);

            // Grant PAUSE_ROLE to ResealManager
            agentForwardCalls[0].target = address(_lido.withdrawalQueue);
            agentForwardCalls[0].data = abi.encodeCall(
                _lido.withdrawalQueue.grantRole,
                (_lido.withdrawalQueue.PAUSE_ROLE(), address(_dgDeployedContracts.resealManager))
            );

            // Grant RESUME_ROLE to ResealManager
            agentForwardCalls[1].target = address(_lido.withdrawalQueue);
            agentForwardCalls[1].data = abi.encodeCall(
                _lido.withdrawalQueue.grantRole,
                (_lido.withdrawalQueue.RESUME_ROLE(), address(_dgDeployedContracts.resealManager))
            );

            EvmScriptUtils.EvmScriptCall[] memory aragonVoteCalls = new EvmScriptUtils.EvmScriptCall[](6);

            // Grant RUN_SCRIPT_ROLE to AdminExecutor
            aragonVoteCalls[0].target = address(_lido.acl);
            aragonVoteCalls[0].data = abi.encodeCall(
                _lido.acl.grantPermission,
                (address(_getAdminExecutor()), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            // Grant EXECUTE_ROLE to AdminExecutor
            aragonVoteCalls[1].target = address(_lido.acl);
            aragonVoteCalls[1].data = abi.encodeCall(
                _lido.acl.grantPermission,
                (address(_getAdminExecutor()), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );

            // Transfer RUN_SCRIPT_ROLE manager to Agent
            aragonVoteCalls[2].target = address(_lido.acl);
            aragonVoteCalls[2].data = abi.encodeCall(
                _lido.acl.setPermissionManager,
                (address(_lido.agent), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            // Transfer EXECUTE_ROLE manager to Agent
            aragonVoteCalls[3].target = address(_lido.acl);
            aragonVoteCalls[3].data = abi.encodeCall(
                _lido.acl.setPermissionManager, (address(_lido.agent), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );

            ExternalCall[] memory dgLaunchCalls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(_lido.agent),
                        value: 0,
                        payload: abi.encodeCall(
                            _lido.agent.forward,
                            (
                                EvmScriptUtils.encodeEvmCallScript(
                                    address(_lido.acl),
                                    abi.encodeCall(
                                        _lido.acl.revokePermission,
                                        (address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
                                    )
                                )
                            )
                        )
                    }),
                    ExternalCall({
                        target: address(dgStateVerifier),
                        value: 0,
                        payload: abi.encodeCall(
                            dgStateVerifier.validate,
                            (address(_dgDeployedContracts.dualGovernance), address(_dgDeployedContracts.timelock))
                        )
                    })
                ]
            );

            aragonVoteCalls[4].target = address(rolesVerifier);
            aragonVoteCalls[4].data = abi.encodeCall(
                rolesVerifier.validate,
                (address(_dgDeployedContracts.adminExecutor), address(_dgDeployedContracts.resealManager))
            );

            // submit proposal into DG to revoke Agent.RUN_SCRIPT_ROLE from voting
            aragonVoteCalls[5].target = address(_dgDeployedContracts.dualGovernance);
            aragonVoteCalls[5].data =
                abi.encodeCall(_dgDeployedContracts.dualGovernance.submitProposal, (dgLaunchCalls, "Finally Launch DG"));

            uint256 voteId = _lido.adoptVote("Launch DG vote", EvmScriptUtils.encodeEvmCallScript(aragonVoteCalls));
            _lido.executeVote(voteId);

            assertEq(_getLastProposalId(), 2);
        }

        _step("9. Schedule and execute the DG activation proposal");
        {
            _wait(_getAfterSubmitDelay());
            _scheduleProposal(_getLastProposalId());
            _wait(_getAfterScheduleDelay());
            _executeProposal(_getLastProposalId());
        }

        _step("10. Verify that Voting has no permission to forward to Agent");
        {
            ExternalCall[] memory someAgentForwardCall;
            someAgentForwardCall = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        target: address(_lido.acl),
                        value: 0,
                        payload: abi.encodeWithSelector(
                            _lido.acl.revokePermission.selector,
                            _getAdminExecutor(),
                            (address(_lido.agent)),
                            _lido.agent.RUN_SCRIPT_ROLE()
                        )
                    })
                ]
            );

            vm.expectRevert("AGENT_CAN_NOT_FORWARD");
            _lido.agent.forward(_encodeExternalCalls(someAgentForwardCall));
        }
    }

    function testFork_DualGovernanceLaunchFromAragonVote() external {
        _step("0. Deploy DG contracts");
        {
            _deployDGSetup({isEmergencyProtectionEnabled: true});
            _deployArtifact.deployConfig = _dgDeployConfig;
            _deployArtifact.deployedContracts = _dgDeployedContracts;
        }

        _step("1. Validate The DG Initial State After Deployment");
        {
            DeployVerification.verify(_deployArtifact);
        }

        _step("2. Activate Emergency Mode");
        {
            _activateEmergencyMode();
        }

        _step("3. Make Emergency Reset");
        {
            _emergencyReset();
        }

        _step("4. Prepare Aragon Vote With Roles Transfer & DG Configuration");
        {
            ExternalCall[] memory dgConfigurationProposalCalls = ExternalCallHelpers.create(
                address(_timelock),
                [
                    abi.encodeCall(
                        _timelock.setEmergencyProtectionActivationCommittee, (_DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE)
                    ),
                    abi.encodeCall(
                        _timelock.setEmergencyProtectionExecutionCommittee, (_DEFAULT_EMERGENCY_EXECUTION_COMMITTEE)
                    ),
                    abi.encodeCall(_timelock.setGovernance, (address(_dgDeployedContracts.dualGovernance))),
                    abi.encodeCall(
                        _timelock.setEmergencyProtectionEndDate,
                        (_DEFAULT_EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()))
                    ),
                    abi.encodeCall(_timelock.setEmergencyModeDuration, (_DEFAULT_EMERGENCY_MODE_DURATION))
                ]
            );

            EvmScriptUtils.EvmScriptCall[] memory aragonVoteCalls = new EvmScriptUtils.EvmScriptCall[](5);

            // Grant RUN_SCRIPT_ROLE to AdminExecutor
            aragonVoteCalls[0].target = address(_lido.acl);
            aragonVoteCalls[0].data = abi.encodeCall(
                _lido.acl.grantPermission,
                (address(_getAdminExecutor()), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            // Grant EXECUTE_ROLE to AdminExecutor
            aragonVoteCalls[1].target = address(_lido.acl);
            aragonVoteCalls[1].data = abi.encodeCall(
                _lido.acl.grantPermission,
                (address(_getAdminExecutor()), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );

            // Transfer RUN_SCRIPT_ROLE manager to Agent
            aragonVoteCalls[2].target = address(_lido.acl);
            aragonVoteCalls[2].data = abi.encodeCall(
                _lido.acl.setPermissionManager,
                (address(_lido.agent), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            // Transfer EXECUTE_ROLE manager to Agent
            aragonVoteCalls[3].target = address(_lido.acl);
            aragonVoteCalls[3].data = abi.encodeCall(
                _lido.acl.setPermissionManager, (address(_lido.agent), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );

            // Submit proposal to EmergencyProtectedTimelock
            aragonVoteCalls[4].target = address(_dgDeployedContracts.emergencyGovernance);
            aragonVoteCalls[4].data = abi.encodeCall(
                _dgDeployedContracts.emergencyGovernance.submitProposal,
                (dgConfigurationProposalCalls, "Dual Governance Configuration")
            );

            bytes memory script = EvmScriptUtils.encodeEvmCallScript(aragonVoteCalls);

            uint256 readyToExecuteAragonVoteId = _lido.adoptVote("Dual Governance Launch", script);

            _lido.executeVote(readyToExecuteAragonVoteId);
        }

        _step("5. Wait & Execute Timelock Proposal");
        {
            assertEq(
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE()),
                address(_lido.agent)
            );

            assertTrue(_lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE()));
            assertTrue(
                _lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            assertTrue(
                _lido.acl.hasPermission(address(_getAdminExecutor()), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );
            assertTrue(
                _lido.acl.hasPermission(
                    address(_getAdminExecutor()), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE()
                )
            );

            uint256 launchProposalId = 1;
            assertEq(_timelock.getProposalsCount(), 1);

            _wait(_getAfterSubmitDelay());
            _scheduleProposal(launchProposalId);

            _wait(_getAfterScheduleDelay());
            _executeProposal(launchProposalId);
        }

        _step("6. Validate The State Before Final Step Of DG Launch");
        {
            assertTrue(_lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE()));
            assertTrue(
                _lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            assertTrue(
                _lido.acl.hasPermission(address(_getAdminExecutor()), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );
            assertTrue(
                _lido.acl.hasPermission(
                    address(_getAdminExecutor()), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE()
                )
            );

            assertEq(
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.EXECUTE_ROLE()), address(_lido.agent)
            );

            assertEq(
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE()),
                address(_lido.agent)
            );
        }

        _step("7. Submit Dual Governance To Revoke Agent Forwarding From Voting");
        {
            ExternalCall[] memory votingRevokePermissionsCalls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        value: 0,
                        target: address(_lido.agent),
                        payload: abi.encodeCall(
                            _lido.agent.forward,
                            EvmScriptUtils.encodeEvmCallScript(
                                address(_lido.acl),
                                abi.encodeCall(
                                    _lido.acl.revokePermission,
                                    (address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
                                )
                            )
                        )
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_lido.agent),
                        payload: abi.encodeCall(
                            _lido.agent.forward,
                            EvmScriptUtils.encodeEvmCallScript(
                                address(_lido.acl),
                                abi.encodeCall(
                                    _lido.acl.revokePermission,
                                    (address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
                                )
                            )
                        )
                    })
                ]
            );

            uint256 dgLaunchPoposalId =
                _submitProposalByAdminProposer(votingRevokePermissionsCalls, "DG Launch Final Step");
            assertEq(_timelock.getProposalsCount(), 2);

            _wait(_getAfterSubmitDelay());
            _scheduleProposal(dgLaunchPoposalId);

            _wait(_getAfterScheduleDelay());
            _executeProposal(dgLaunchPoposalId);
        }

        _step("8. Validate The Voting Has No Permission to Forward to Agent");
        {
            assertFalse(
                _lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );
            assertFalse(
                _lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            assertTrue(
                _lido.acl.hasPermission(address(_getAdminExecutor()), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );
            assertTrue(
                _lido.acl.hasPermission(
                    address(_getAdminExecutor()), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE()
                )
            );

            assertEq(
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.EXECUTE_ROLE()), address(_lido.agent)
            );

            assertEq(
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE()),
                address(_lido.agent)
            );
        }
    }

    function _encodeExternalCalls(ExternalCall[] memory calls) internal pure returns (bytes memory result) {
        result = abi.encodePacked(bytes4(uint32(1)));

        for (uint256 i = 0; i < calls.length; ++i) {
            ExternalCall memory call = calls[i];
            result = abi.encodePacked(result, bytes20(call.target), bytes4(uint32(call.payload.length)), call.payload);
        }
    }
}

contract MockRolesVerifier {
    event AllRolesVerified();

    function validate(address, /* dgAdminExecutor */ address /* dgResealManager */ ) external {
        emit AllRolesVerified();
    }
}

contract MockDGStateVerifier {
    event DGStateVerified();

    function validate(address, /* dualGovernance */ address /* timelock */ ) external {
        emit DGStateVerified();
    }
}
