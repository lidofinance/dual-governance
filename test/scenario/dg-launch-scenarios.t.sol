// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {LidoUtils, DGScenarioTestSetup} from "../utils/integration-tests.sol";
import {TimelockedGovernance, ContractsDeployment} from "scripts/utils/contracts-deployment.sol";

import {Durations} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";

import {DeployVerification} from "scripts/utils/DeployVerification.sol";

import {DGSetupDeployArtifacts} from "scripts/utils/contracts-deployment.sol";

import {CallsScriptBuilder} from "scripts/utils/CallsScriptBuilder.sol";
import {ExternalCallsBuilder, ExternalCall} from "scripts/utils/ExternalCallsBuilder.sol";

contract DGLaunchStrategiesScenarioTest is DGScenarioTestSetup {
    using LidoUtils for LidoUtils.Context;
    using CallsScriptBuilder for CallsScriptBuilder.Context;
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

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
            ExternalCallsBuilder.Context memory finalizeDGSetupCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 6});

            finalizeDGSetupCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setGovernance, (address(_dgDeployedContracts.dualGovernance)))
            );
            finalizeDGSetupCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyGovernance, address(_emergencyGovernance))
            );
            finalizeDGSetupCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionActivationCommittee, (_DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE)
                )
            );
            finalizeDGSetupCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionExecutionCommittee, (_DEFAULT_EMERGENCY_EXECUTION_COMMITTEE)
                )
            );
            finalizeDGSetupCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionEndDate,
                    (_deployArtifact.deployConfig.timelock.emergencyProtectionEndDate)
                )
            );
            finalizeDGSetupCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyModeDuration, (_deployArtifact.deployConfig.timelock.emergencyModeDuration)
                )
            );

            finalizeDGSetupCalls = finalizeDGSetupCallsBuilder.getResult();
        }

        _step("5. Submit proposal from the temporary governance to configure timelock for the launch");
        {
            _adoptProposal(
                _TEMPORARY_EMERGENCY_GOVERNANCE_PROPOSER, finalizeDGSetupCalls, "Dual Governance after dry-run setup"
            );
            console.log("Last Proposal Id: %d", _getLastProposalId());
        }

        _step("6. Verify the state of the DG setup after update and before voting start");
        {
            _dgDeployedContracts.emergencyGovernance = _emergencyGovernance;
            _dgDeployConfig.timelock.emergencyGovernanceProposer = address(_lido.voting);
            _deployArtifact.deployConfig = _dgDeployConfig;
            _deployArtifact.deployedContracts = _dgDeployedContracts;

            DeployVerification.verify({deployArtifact: _deployArtifact, expectedProposalsCount: 1});
        }

        _step("7. Prepare Roles Verifier");
        MockRolesVerifier rolesVerifier;
        MockDGStateVerifier dgStateVerifier;
        {
            rolesVerifier = new MockRolesVerifier();
            dgStateVerifier = new MockDGStateVerifier();
        }

        _step("7.1 Prepare Voting Permissions");
        {
            address runScriptRoleManager =
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE());

            if (runScriptRoleManager != address(_lido.voting)) {
                vm.startPrank(runScriptRoleManager);
                {
                    _lido.acl.setPermissionManager(
                        address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE()
                    );
                }
                vm.stopPrank();
            }

            address executeRoleManager =
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.EXECUTE_ROLE());

            if (executeRoleManager != address(_lido.voting)) {
                vm.startPrank(executeRoleManager);
                {
                    _lido.acl.setPermissionManager(
                        address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE()
                    );
                }
                vm.stopPrank();
            }
        }

        _step("8. Activate Dual Governance with DAO Voting");
        {
            CallsScriptBuilder.Context memory voteScriptBuilder = CallsScriptBuilder.create();

            // Grant RUN_SCRIPT_ROLE to AdminExecutor
            voteScriptBuilder.addCall(
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.grantPermission,
                    (address(_getAdminExecutor()), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
                )
            );

            // Grant EXECUTE_ROLE to AdminExecutor
            voteScriptBuilder.addCall(
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.grantPermission,
                    (address(_getAdminExecutor()), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
                )
            );

            // Transfer RUN_SCRIPT_ROLE manager to Agent
            voteScriptBuilder.addCall(
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.setPermissionManager,
                    (address(_lido.agent), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
                )
            );

            // Transfer EXECUTE_ROLE manager to Agent
            voteScriptBuilder.addCall(
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.setPermissionManager,
                    (address(_lido.agent), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
                )
            );

            ExternalCallsBuilder.Context memory dgLaunchCallsBuilder = ExternalCallsBuilder.create(2);

            dgLaunchCallsBuilder.addForwardCall({
                forwarder: address(_lido.agent),
                target: address(_lido.acl),
                payload: abi.encodeCall(
                    _lido.acl.revokePermission, (address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
                )
            });

            dgLaunchCallsBuilder.addCall({
                target: address(dgStateVerifier),
                payload: abi.encodeCall(
                    dgStateVerifier.validate,
                    (address(_dgDeployedContracts.dualGovernance), address(_dgDeployedContracts.timelock))
                )
            });

            voteScriptBuilder.addCall(
                address(rolesVerifier),
                abi.encodeCall(
                    rolesVerifier.validate,
                    (address(_dgDeployedContracts.adminExecutor), address(_dgDeployedContracts.resealManager))
                )
            );

            // submit proposal into DG to revoke Agent.RUN_SCRIPT_ROLE from voting
            voteScriptBuilder.addCall(
                address(_dgDeployedContracts.dualGovernance),
                abi.encodeCall(
                    _dgDeployedContracts.dualGovernance.submitProposal,
                    (dgLaunchCallsBuilder.getResult(), "Finally Launch DG")
                )
            );

            uint256 voteId = _lido.adoptVote("Launch DG vote", voteScriptBuilder.getResult());
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
            bytes memory revokePermissionScript = CallsScriptBuilder.create(
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.revokePermission,
                    (_getAdminExecutor(), (address(_lido.agent)), _lido.agent.RUN_SCRIPT_ROLE())
                )
            ).getResult();

            vm.prank(address(_lido.voting));
            vm.expectRevert("AGENT_CAN_NOT_FORWARD");
            _lido.agent.forward(revokePermissionScript);
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

        _step("1.1 Prepare Voting Permissions");
        {
            address runScriptRoleManager =
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE());

            if (runScriptRoleManager != address(_lido.voting)) {
                vm.startPrank(runScriptRoleManager);
                {
                    _lido.acl.setPermissionManager(
                        address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE()
                    );
                }
                vm.stopPrank();
            }

            if (!_lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())) {
                vm.startPrank(address(_lido.voting));
                _lido.acl.grantPermission(address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE());
                vm.stopPrank();
            }

            address executeRoleManager =
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.EXECUTE_ROLE());

            if (executeRoleManager != address(_lido.voting)) {
                vm.startPrank(executeRoleManager);
                {
                    _lido.acl.setPermissionManager(
                        address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE()
                    );
                }
                vm.stopPrank();
            }

            if (!_lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE())) {
                vm.startPrank(address(_lido.voting));
                _lido.acl.grantPermission(address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE());
                vm.stopPrank();
            }
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
            ExternalCallsBuilder.Context memory dgConfigurationCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 5});

            dgConfigurationCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionActivationCommittee, (_DEFAULT_EMERGENCY_ACTIVATION_COMMITTEE)
                )
            );
            dgConfigurationCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionExecutionCommittee, (_DEFAULT_EMERGENCY_EXECUTION_COMMITTEE)
                )
            );
            dgConfigurationCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setGovernance, (address(_dgDeployedContracts.dualGovernance)))
            );
            dgConfigurationCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionEndDate,
                    (_DEFAULT_EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()))
                )
            );
            dgConfigurationCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setEmergencyModeDuration, (_DEFAULT_EMERGENCY_MODE_DURATION))
            );

            CallsScriptBuilder.Context memory aragonVoteScriptBuilder = CallsScriptBuilder.create();

            // Grant RUN_SCRIPT_ROLE to AdminExecutor
            aragonVoteScriptBuilder.addCall(
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.grantPermission,
                    (address(_getAdminExecutor()), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
                )
            );

            // Grant EXECUTE_ROLE to AdminExecutor
            aragonVoteScriptBuilder.addCall(
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.grantPermission,
                    (address(_getAdminExecutor()), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
                )
            );

            // Transfer RUN_SCRIPT_ROLE manager to Agent
            aragonVoteScriptBuilder.addCall(
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.setPermissionManager,
                    (address(_lido.agent), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
                )
            );

            // Transfer EXECUTE_ROLE manager to Agent
            aragonVoteScriptBuilder.addCall(
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.setPermissionManager,
                    (address(_lido.agent), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
                )
            );

            // Submit proposal to EmergencyProtectedTimelock
            aragonVoteScriptBuilder.addCall(
                address(_dgDeployedContracts.emergencyGovernance),
                abi.encodeCall(
                    _dgDeployedContracts.emergencyGovernance.submitProposal,
                    (dgConfigurationCallsBuilder.getResult(), "Dual Governance Configuration")
                )
            );

            uint256 readyToExecuteAragonVoteId =
                _lido.adoptVote("Dual Governance Launch", aragonVoteScriptBuilder.getResult());

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
            ExternalCallsBuilder.Context memory revokePermissionsCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 2});

            revokePermissionsCallsBuilder.addForwardCall(
                address(_lido.agent),
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.revokePermission,
                    (address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
                )
            );

            revokePermissionsCallsBuilder.addForwardCall(
                address(_lido.agent),
                address(_lido.acl),
                abi.encodeCall(
                    _lido.acl.revokePermission,
                    (address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
                )
            );

            uint256 dgLaunchPoposalId =
                _submitProposalByAdminProposer(revokePermissionsCallsBuilder.getResult(), "DG Launch Final Step");
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
