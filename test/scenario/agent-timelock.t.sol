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

        uint256 proposalId;
        _step("1. THE PROPOSAL IS SUBMITTED");
        {
            proposalId = _submitProposal(
                _dualGovernance, "Propose to doSmth on target passing dual governance", regularStaffCalls
            );

            _assertSubmittedProposalData(proposalId, _config.ADMIN_EXECUTOR(), regularStaffCalls);
            _assertCanSchedule(_dualGovernance, proposalId, false);
        }

        _step("2. THE PROPOSAL IS SCHEDULED");
        {
            _waitAfterSubmitDelayPassed();
            _assertCanSchedule(_dualGovernance, proposalId, true);
            _scheduleProposal(_dualGovernance, proposalId);

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
            _assertCanSchedule(_dualGovernance, proposalId, false);

            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
        }
    }

    function testFork_TimelockEmergencyReset() external {
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();

        // ---
        // 1. THE PROPOSAL IS SUBMITTED
        // ---
        uint256 proposalId;
        {
            proposalId = _submitProposal(
                _dualGovernance, "Propose to doSmth on target passing dual governance", regularStaffCalls
            );
            _assertSubmittedProposalData(proposalId, _config.ADMIN_EXECUTOR(), regularStaffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(_dualGovernance, proposalId, false);
        }

        // ---
        // 2. THE PROPOSAL IS SCHEDULED
        // ---
        {
            // wait until the delay has passed
            _wait(_config.AFTER_SUBMIT_DELAY().plusSeconds(1));

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(_dualGovernance, proposalId, true);

            _scheduleProposal(_dualGovernance, proposalId);

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
            _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2));

            // committee resets governance
            vm.prank(address(_emergencyActivationCommittee));
            _timelock.activateEmergencyMode();

            vm.prank(address(_emergencyExecutionCommittee));
            _timelock.emergencyReset();

            // proposal is canceled now
            _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2).plusSeconds(1));

            // remove canceled call from the timelock
            _assertCanExecute(proposalId, false);
            _assertProposalCanceled(proposalId);
        }
    }
}
