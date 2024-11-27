// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Proposers} from "contracts/libraries/Proposers.sol";

import {ExternalCall, ExternalCallHelpers, ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";
import {LidoUtils} from "../utils/lido-utils.sol";

contract AgentTimelockTest is ScenarioTestBlueprint {
    using LidoUtils for LidoUtils.Context;

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: true});
    }

    function testFork_AragonAgentAsExecutor_HappyPath() external {
        _step("0. Grant EXECUTE_ROLE permission to the timelock on the Agent contract");
        {
            _lido.grantPermission(address(_lido.agent), _lido.agent.EXECUTE_ROLE(), address(_timelock));
            assertTrue(_lido.acl.hasPermission(address(_timelock), address(_lido.agent), _lido.agent.EXECUTE_ROLE()));
        }

        address agentProposer = makeAddr("AGENT_PROPOSER");
        _step("1. Submit proposal to register Aragon as the executor");
        {
            ExternalCall[] memory externalCalls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        value: 0,
                        target: address(_dualGovernance),
                        payload: abi.encodeCall(_dualGovernance.registerProposer, (agentProposer, address(_lido.agent)))
                    })
                ]
            );
            uint256 addAgentProposerProposalId =
                _submitProposalViaDualGovernance("Add Aragon Agent as proposer to the Dual Governance", externalCalls);

            _assertProposalSubmitted(addAgentProposerProposalId);
            _waitAfterSubmitDelayPassed();

            _scheduleProposalViaDualGovernance(addAgentProposerProposalId);
            _assertProposalScheduled(addAgentProposerProposalId);

            _waitAfterScheduleDelayPassed();
            _executeProposal(addAgentProposerProposalId);
            _assertProposalExecuted(addAgentProposerProposalId);

            Proposers.Proposer[] memory proposers = _dualGovernance.getProposers();

            assertEq(proposers.length, 2);
            assertEq(proposers[1].account, agentProposer);
            assertEq(proposers[1].executor, address(_lido.agent));
        }

        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 agentActionsProposalId;
        _step("2. Submit proposal via the Agent proposer");
        {
            vm.prank(agentProposer);
            agentActionsProposalId =
                _dualGovernance.submitProposal(regularStaffCalls, "Make regular staff using Agent as executor");

            _assertSubmittedProposalData(agentActionsProposalId, address(_lido.agent), regularStaffCalls);
        }

        _step("3. Execute the proposal");
        {
            _assertProposalSubmitted(agentActionsProposalId);
            _waitAfterSubmitDelayPassed();

            _scheduleProposalViaDualGovernance(agentActionsProposalId);
            _assertProposalScheduled(agentActionsProposalId);

            _waitAfterScheduleDelayPassed();
            _executeProposal(agentActionsProposalId);
            _assertProposalExecuted(agentActionsProposalId);

            _assertTargetMockCalls(address(_lido.agent), regularStaffCalls);
        }
    }

    function testFork_AragonAgentAsExecutor_RevertOn_FailedCall() external {
        _step("0. Grant EXECUTE_ROLE permission to the timelock on the Agent contract");
        {
            _lido.grantPermission(address(_lido.agent), _lido.agent.EXECUTE_ROLE(), address(_timelock));
            assertTrue(_lido.acl.hasPermission(address(_timelock), address(_lido.agent), _lido.agent.EXECUTE_ROLE()));
        }

        address agentProposer = makeAddr("AGENT_PROPOSER");
        _step("1. Submit proposal to register Aragon as the executor");
        {
            ExternalCall[] memory externalCalls = ExternalCallHelpers.create(
                [
                    ExternalCall({
                        value: 0,
                        target: address(_dualGovernance),
                        payload: abi.encodeCall(_dualGovernance.registerProposer, (agentProposer, address(_lido.agent)))
                    })
                ]
            );
            uint256 addAgentProposerProposalId =
                _submitProposalViaDualGovernance("Add Aragon Agent as proposer to the Dual Governance", externalCalls);

            _assertProposalSubmitted(addAgentProposerProposalId);
            _waitAfterSubmitDelayPassed();

            _scheduleProposalViaDualGovernance(addAgentProposerProposalId);
            _assertProposalScheduled(addAgentProposerProposalId);

            _waitAfterScheduleDelayPassed();
            _executeProposal(addAgentProposerProposalId);
            _assertProposalExecuted(addAgentProposerProposalId);

            Proposers.Proposer[] memory proposers = _dualGovernance.getProposers();

            assertEq(proposers.length, 2);
            assertEq(proposers[1].account, agentProposer);
            assertEq(proposers[1].executor, address(_lido.agent));
        }

        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
        vm.mockCallRevert(regularStaffCalls[0].target, regularStaffCalls[0].payload, "INVALID TARGET");

        uint256 agentActionsProposalId;
        _step("2. Submit proposal which should revert via the Agent proposer");
        {
            vm.prank(agentProposer);
            agentActionsProposalId =
                _dualGovernance.submitProposal(regularStaffCalls, "Make regular staff using Agent as executor");

            _assertSubmittedProposalData(agentActionsProposalId, address(_lido.agent), regularStaffCalls);
        }

        _step("3. The execution of the proposal fails");
        {
            _assertProposalSubmitted(agentActionsProposalId);
            _waitAfterSubmitDelayPassed();

            _scheduleProposalViaDualGovernance(agentActionsProposalId);
            _assertProposalScheduled(agentActionsProposalId);

            _waitAfterScheduleDelayPassed();

            vm.expectRevert("INVALID TARGET");
            _executeProposal(agentActionsProposalId);

            _assertNoTargetMockCalls();
        }
    }

    function testFork_AgentTimelockHappyPath() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. THE PROPOSAL IS SUBMITTED");
        {
            proposalId = _submitProposalViaDualGovernance(
                "Propose to doSmth on target passing dual governance", regularStaffCalls
            );

            _assertSubmittedProposalData(proposalId, _getAdminExecutor(), regularStaffCalls);
            _assertCanScheduleViaDualGovernance(proposalId, false);
        }

        _step("2. THE PROPOSAL IS SCHEDULED");
        {
            _waitAfterSubmitDelayPassed();
            _assertCanScheduleViaDualGovernance(proposalId, true);
            _scheduleProposalViaDualGovernance(proposalId);

            _assertProposalScheduled(proposalId);
            _assertCanExecute(proposalId, false);
        }

        _step("3. THE PROPOSAL CAN BE EXECUTED");
        {
            // wait until the second delay has passed
            _waitAfterScheduleDelayPassed();

            // Now proposal can be executed
            _assertCanExecute(proposalId, true);

            _assertNoTargetMockCalls();

            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);

            _assertCanExecute(proposalId, false);
            _assertCanScheduleViaDualGovernance(proposalId, false);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }
    }

    function testFork_TimelockEmergencyReset() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        // ---
        // 1. THE PROPOSAL IS SUBMITTED
        // ---
        uint256 proposalId;
        {
            proposalId = _submitProposalViaDualGovernance(
                "Propose to doSmth on target passing dual governance", regularStaffCalls
            );
            _assertSubmittedProposalData(proposalId, _getAdminExecutor(), regularStaffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanScheduleViaDualGovernance(proposalId, false);
        }

        // ---
        // 2. THE PROPOSAL IS SCHEDULED
        // ---
        {
            // wait until the delay has passed
            _wait(_timelock.getAfterSubmitDelay().plusSeconds(1));

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanScheduleViaDualGovernance(proposalId, true);

            _scheduleProposalViaDualGovernance(proposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(proposalId);
            _assertCanExecute(proposalId, false);
        }

        // ---
        // 3. EMERGENCY MODE ACTIVATED &  GOVERNANCE RESET
        // ---
        {
            // some time passes and emergency committee activates emergency mode
            // and resets the controller
            _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

            // committee resets governance
            vm.prank(address(_emergencyActivationCommittee));
            _timelock.activateEmergencyMode();

            vm.prank(address(_emergencyExecutionCommittee));
            _timelock.emergencyReset();

            // proposal is canceled now
            _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

            // remove canceled call from the timelock
            _assertCanExecute(proposalId, false);
            _assertProposalCancelled(proposalId);
        }
    }
}
