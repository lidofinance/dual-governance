// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall, ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";
import {LidoUtils} from "../utils/lido-utils.sol";

contract AgentTimelockTest is ScenarioTestBlueprint {
    using LidoUtils for LidoUtils.Context;

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: true});
    }

    function testFork_AragonAgentAsExecutor_HappyPath() external {
        _step("0. Tweak the default setup to make Agent admin executor");

        // set the Agent as admin executor in the timelock contract
        vm.prank(address(_adminExecutor));
        _timelock.setAdminExecutor(address(_lido.agent));

        assertEq(_timelock.getAdminExecutor(), address(_lido.agent));

        // grant EXECUTE_ROLE permission to the timelock contract to allow call Agent.execute() method
        _lido.grantPermission({app: address(_lido.agent), role: _lido.agent.EXECUTE_ROLE(), grantee: address(_timelock)});

        // update proposers for the Voting
        vm.startPrank(address(_lido.agent));

        address tmpProposer = makeAddr("tmpProposer");

        _dualGovernance.registerProposer(tmpProposer, address(_lido.agent));
        _dualGovernance.unregisterProposer(address(_lido.voting));

        _dualGovernance.registerProposer(address(_lido.voting), address(_lido.agent));
        _dualGovernance.unregisterProposer(tmpProposer);
        vm.stopPrank();

        _step("Test setup preparations have done!");

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

            _assertTargetMockCalls(address(_lido.agent), regularStaffCalls);
        }
    }

    function testFork_AragonAgentAsExecutor_RevertOn_FailedCall() external {
        _step("0. Tweak the default setup to make Agent admin executor");

        // set the Agent as admin executor in the timelock contract
        vm.prank(address(_adminExecutor));
        _timelock.setAdminExecutor(address(_lido.agent));

        assertEq(_timelock.getAdminExecutor(), address(_lido.agent));

        // grant EXECUTE_ROLE permission to the timelock contract to allow call Agent.execute() method
        _lido.grantPermission({app: address(_lido.agent), role: _lido.agent.EXECUTE_ROLE(), grantee: address(_timelock)});

        // update proposers for the Voting
        vm.startPrank(address(_lido.agent));

        address tmpProposer = makeAddr("tmpProposer");

        _dualGovernance.registerProposer(tmpProposer, address(_lido.agent));
        _dualGovernance.unregisterProposer(address(_lido.voting));

        _dualGovernance.registerProposer(address(_lido.voting), address(_lido.agent));
        _dualGovernance.unregisterProposer(tmpProposer);
        vm.stopPrank();

        _step("Test setup preparations have done!");

        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        // code to invalid contract
        regularStaffCalls[0].target = makeAddr("invalidTarget");
        vm.mockCallRevert(regularStaffCalls[0].target, regularStaffCalls[0].payload, "INVALID TARGET");

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

            vm.expectRevert("INVALID TARGET");
            _executeProposal(proposalId);
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
