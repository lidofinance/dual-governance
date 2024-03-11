// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutorCall, ScenarioTestBlueprint, ExecutorCall} from "../utils/scenario-test-blueprint.sol";

contract AgentTimelockTest is ScenarioTestBlueprint {
    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ true);
    }

    function testFork_AgentTimelockHappyPath() external {
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();
        // ---
        // ACT 1. The proposal is submitted via Aragon voting
        // ---
        uint256 proposalId;
        {
            proposalId = _submitProposal("Propose to doSmth on target passing dual governance", regularStaffCalls);
            _assertSubmittedProposalData(proposalId, _config.ADMIN_EXECUTOR(), regularStaffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(proposalId, false);
        }

        // ---
        // ACT 2. THE PROPOSAL IS SCHEDULED
        // ---
        {
            // wait until the delay has passed
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(proposalId, true);

            _scheduleProposal(proposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(proposalId, /* isExecutable */ false);
            _assertCanExecuteScheduled(proposalId, false);
        }

        // ---
        // ACT 3. THE PROPOSAL CAN BE EXECUTED
        // ---
        {
            // wait until the second delay has passed
            vm.warp(block.timestamp + _config.AFTER_SCHEDULE_DELAY() + 1);

            // Now proposal can be executed
            _assertCanExecuteScheduled(proposalId, true);
            _assertProposalScheduled(proposalId, /* isExecutable */ true);

            // before the proposal is executed there are no calls to target
            _assertNoTargetCalls();

            _executeScheduledProposal(proposalId);

            // check the proposal was executed correctly
            _assertProposalExecuted(proposalId);
            _assertCanSchedule(proposalId, false);
            _assertCanExecuteScheduled(proposalId, false);
            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
        }
    }

    function testFork_TimelockEmergencyReset() external {
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();

        // ---
        // ACT 1. THE PROPOSAL IS CREATED
        // ---
        uint256 proposalId;
        {
            proposalId = _submitProposal("Propose to doSmth on target passing dual governance", regularStaffCalls);
            _assertSubmittedProposalData(proposalId, _config.ADMIN_EXECUTOR(), regularStaffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(proposalId, false);
        }

        // ---
        // ACT 2. THE PROPOSAL IS SCHEDULED
        // ---
        {
            // wait until the delay has passed
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(proposalId, true);

            _scheduleProposal(proposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(proposalId, /* isExecutable */ false);
            _assertCanExecuteScheduled(proposalId, false);
        }

        // ---
        // ACT 3. EMERGENCY MODE ACTIVATED &  GOVERNANCE RESET
        // ---
        {
            // some time passes and emergency committee activates emergency mode
            // and resets the controller
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2);

            // committee resets governance
            vm.startPrank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyActivate();
            _timelock.emergencyReset();
            vm.stopPrank();

            // proposal is canceled now
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2 + 1);

            // remove canceled call from the timelock
            _assertCanExecuteScheduled(proposalId, false);
            _assertCanExecuteSubmitted(proposalId, false);
            _assertProposalCanceled(proposalId);
        }
    }
}
