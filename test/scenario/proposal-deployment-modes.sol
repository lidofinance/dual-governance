// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EmergencyState} from "contracts/libraries/EmergencyProtection.sol";
import {Proposals} from "contracts/libraries/Proposals.sol";
import {Durations, Timestamps} from "test/utils/unit-test.sol";

import {percents, ScenarioTestBlueprint, ExecutorCall} from "../utils/scenario-test-blueprint.sol";

contract ProposalDeploymentModesTest is ScenarioTestBlueprint {
    function setUp() external {
        _selectFork();

        _deployTarget();
    }

    function test_regular_deployment_mode() external {
        _deployDualGovernanceSetup(false);

        (uint256 proposalId, ExecutorCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
    }

    function test_protected_deployment_mode_execute_after_timelock() external {
        _deployDualGovernanceSetup(true);

        (uint256 proposalId, ExecutorCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
    }

    function test_protected_deployment_mode_execute_in_emergency_mode() external {
        _deployDualGovernanceSetup(true);

        (uint256 proposalId, ExecutorCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);

        vm.prank(address(_emergencyActivationCommittee));
        _timelock.activateEmergencyMode();

        EmergencyState memory emergencyState = _timelock.getEmergencyState();

        assertEq(emergencyState.isEmergencyModeActivated, true);

        _assertCanExecute(proposalId, false);

        vm.prank(address(_emergencyExecutionCommittee));
        _timelock.emergencyExecute(proposalId);

        _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
    }

    function test_protected_deployment_mode_deactivation_in_emergency_mode() external {
        _deployDualGovernanceSetup(true);

        (uint256 proposalId, ExecutorCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);

        vm.prank(address(_emergencyActivationCommittee));
        _timelock.activateEmergencyMode();

        EmergencyState memory emergencyState = _timelock.getEmergencyState();

        assertEq(emergencyState.isEmergencyModeActivated, true);
        _assertCanExecute(proposalId, false);

        _wait(emergencyState.emergencyModeDuration.plusSeconds(1));

        _timelock.deactivateEmergencyMode();

        _assertCanExecute(proposalId, false);
        assertEq(_timelock.isEmergencyProtectionEnabled(), false);
    }

    function _createAndAssertProposal() internal returns (uint256, ExecutorCall[] memory) {
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();

        uint256 proposalId = _submitProposal(
            _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
        );
        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        return (proposalId, regularStaffCalls);
    }
}
