// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall, ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";

contract AgentTimelockTest is ScenarioTestBlueprint {
    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: true});
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
