// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Timestamps} from "contracts/types/Timestamp.sol";

import {LidoUtils} from "test/utils/lido-utils.sol";
import {EvmScriptUtils} from "test/utils/evm-script-utils.sol";

import {ExternalCall, ExternalCallHelpers, ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";

contract DGLaunchTest is ScenarioTestBlueprint {
    using LidoUtils for LidoUtils.Context;

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: true});
    }

    function testFork_DualGovernanceLaunchFromAragonVote() external {
        _step("0. Validate The DG Initial State After Deployment");
        // TODO: call DeployVerification lib
        assertNotEq(address(_emergencyGovernance), address(0));
        assertEq(_timelock.getEmergencyGovernance(), address(_emergencyGovernance));

        _step("1. Activate Emergency Mode");
        {
            assertFalse(_timelock.isEmergencyModeActive());

            vm.prank(_emergencyActivationCommittee);
            _timelock.activateEmergencyMode();

            assertTrue(_timelock.isEmergencyModeActive());
        }

        _step("2. Make Emergency Reset");
        {
            assertEq(_timelock.getGovernance(), address(_dualGovernance));

            vm.prank(_emergencyExecutionCommittee);
            _timelock.emergencyReset();

            assertEq(_timelock.getGovernance(), address(_emergencyGovernance));
        }

        _step("3. Prepare Aragon Vote With Roles Transfer & DG Configuration");
        {
            ExternalCall[] memory dgConfigurationProposalCalls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        value: 0,
                        target: address(_timelock),
                        payload: abi.encodeCall(
                            _timelock.setEmergencyProtectionActivationCommittee, (_emergencyActivationCommittee)
                        )
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_timelock),
                        payload: abi.encodeCall(
                            _timelock.setEmergencyProtectionExecutionCommittee, (_emergencyExecutionCommittee)
                        )
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_timelock),
                        payload: abi.encodeCall(_timelock.setGovernance, (address(_dualGovernance)))
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_timelock),
                        payload: abi.encodeCall(
                            _timelock.setEmergencyProtectionEndDate,
                            (_dgDeployConfig.EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()))
                        )
                    }),
                    ExternalCall({
                        value: 0,
                        target: address(_timelock),
                        payload: abi.encodeCall(_timelock.setEmergencyModeDuration, (_dgDeployConfig.EMERGENCY_MODE_DURATION))
                    })
                ]
            );

            EvmScriptUtils.EvmScriptCall[] memory aragonVoteCalls = new EvmScriptUtils.EvmScriptCall[](5);

            // Grant RUN_SCRIPT_ROLE to AdminExecutor
            aragonVoteCalls[0].target = address(_lido.acl);
            aragonVoteCalls[0].data = abi.encodeCall(
                _lido.acl.grantPermission,
                (address(_adminExecutor), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            // Grant EXECUTE_ROLE to AdminExecutor
            aragonVoteCalls[1].target = address(_lido.acl);
            aragonVoteCalls[1].data = abi.encodeCall(
                _lido.acl.grantPermission, (address(_adminExecutor), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
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
            aragonVoteCalls[4].target = address(_emergencyGovernance);
            aragonVoteCalls[4].data = abi.encodeCall(
                _emergencyGovernance.submitProposal, (dgConfigurationProposalCalls, "Dual Governance Configuration")
            );

            bytes memory script = EvmScriptUtils.encodeEvmCallScript(aragonVoteCalls);

            uint256 readyToExecuteAragonVoteId = _lido.adoptVote("Dual Governance Launch", script);

            _lido.executeVote(readyToExecuteAragonVoteId);
        }

        _step("4. Wait & Execute Timelock Proposal");
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
                _lido.acl.hasPermission(address(_adminExecutor), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );
            assertTrue(
                _lido.acl.hasPermission(address(_adminExecutor), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            uint256 launchProposalId = 1;
            assertEq(_timelock.getProposalsCount(), 1);

            _waitAfterSubmitDelayPassed();
            _scheduleProposal(_emergencyGovernance, launchProposalId);

            _waitAfterScheduleDelayPassed();
            _executeProposal(launchProposalId);
        }

        _step("5. Validate The State Before Final Step Of DG Launch");
        {
            assertTrue(_lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE()));
            assertTrue(
                _lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            assertTrue(
                _lido.acl.hasPermission(address(_adminExecutor), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );
            assertTrue(
                _lido.acl.hasPermission(address(_adminExecutor), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            assertEq(
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.EXECUTE_ROLE()), address(_lido.agent)
            );

            assertEq(
                _lido.acl.getPermissionManager(address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE()),
                address(_lido.agent)
            );
        }

        _step("6. Submit Dual Governance To Revoke Agent Forwarding From Voting");
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
                _submitProposal(_dualGovernance, "DG Launch Final Step", votingRevokePermissionsCalls);
            assertEq(_timelock.getProposalsCount(), 2);

            _waitAfterSubmitDelayPassed();
            _scheduleProposalViaDualGovernance(dgLaunchPoposalId);

            _waitAfterScheduleDelayPassed();
            _executeProposal(dgLaunchPoposalId);
        }

        _step("7. Validate The Voting Has No Permission to Forward to Agent");
        {
            assertFalse(
                _lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );
            assertFalse(
                _lido.acl.hasPermission(address(_lido.voting), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
            );

            assertTrue(
                _lido.acl.hasPermission(address(_adminExecutor), address(_lido.agent), _lido.agent.EXECUTE_ROLE())
            );
            assertTrue(
                _lido.acl.hasPermission(address(_adminExecutor), address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE())
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
