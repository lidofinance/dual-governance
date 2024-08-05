// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";

import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";
import {ExecutableProposals} from "contracts/libraries/ExecutableProposals.sol";

import {percents, ScenarioTestBlueprint, ExternalCall} from "../utils/scenario-test-blueprint.sol";

contract ProposalDeploymentModesTest is ScenarioTestBlueprint {
    function setUp() external {
        _selectFork();

        _deployTarget();
    }

    function test_regular_deployment_mode() external {
        _deployDualGovernanceSetup(false);

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStaffCalls);
    }

    function test_protected_deployment_mode_execute_after_timelock() external {
        _deployDualGovernanceSetup(true);

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStaffCalls);
    }

    function test_protected_deployment_mode_execute_in_emergency_mode() external {
        _deployDualGovernanceSetup(true);

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);

        vm.prank(address(_emergencyActivationCommittee));
        _timelock.activateEmergencyMode();

        assertEq(_timelock.isEmergencyModeActive(), true);

        _assertCanExecute(proposalId, false);

        vm.prank(address(_emergencyExecutionCommittee));
        _timelock.emergencyExecute(proposalId);

        _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStaffCalls);
    }

    function test_protected_deployment_mode_deactivation_in_emergency_mode() external {
        _deployDualGovernanceSetup(true);

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);

        vm.prank(address(_emergencyActivationCommittee));
        _timelock.activateEmergencyMode();

        assertEq(_timelock.isEmergencyModeActive(), true);
        assertEq(_timelock.isEmergencyProtectionEnabled(), true);
        _assertCanExecute(proposalId, false);

        // emergency protection disabled after emergency mode is activated

        _wait(_timelock.getEmergencyProtectionContext().emergencyModeDuration.plusSeconds(1));

        assertEq(_timelock.isEmergencyModeActive(), true);
        assertEq(_timelock.isEmergencyProtectionEnabled(), true);

        _timelock.deactivateEmergencyMode();

        assertEq(_timelock.isEmergencyModeActive(), false);
        assertEq(_timelock.isEmergencyProtectionEnabled(), false);
        _assertCanExecute(proposalId, false);
    }

    function _createAndAssertProposal() internal returns (uint256, ExternalCall[] memory) {
        ExternalCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();

        uint256 proposalId = _submitProposal(
            _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
        );
        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        return (proposalId, regularStaffCalls);
    }
}
