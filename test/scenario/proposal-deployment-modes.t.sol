// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExecutableProposals} from "contracts/libraries/ExecutableProposals.sol";

import {ScenarioTestBlueprint, ExternalCall} from "../utils/scenario-test-blueprint.sol";

contract ProposalDeploymentModesTest is ScenarioTestBlueprint {
    function test_regular_deployment_mode() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposalViaDualGovernance(proposalId);

        _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanScheduleViaDualGovernance(proposalId, true);
        _scheduleProposalViaDualGovernance(proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_contracts.timelock.getAdminExecutor(), regularStaffCalls);
    }

    function test_protected_deployment_mode_execute_after_timelock() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: true});

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposalViaDualGovernance(proposalId);

        _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanScheduleViaDualGovernance(proposalId, true);
        _scheduleProposalViaDualGovernance(proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_contracts.timelock.getAdminExecutor(), regularStaffCalls);
    }

    function test_protected_deployment_mode_execute_in_emergency_mode() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: true});

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposalViaDualGovernance(proposalId);

        _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanScheduleViaDualGovernance(proposalId, true);
        _scheduleProposalViaDualGovernance(proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);

        vm.prank(address(_dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE));
        _contracts.timelock.activateEmergencyMode();

        assertEq(_contracts.timelock.isEmergencyModeActive(), true);

        _assertCanExecute(proposalId, false);

        vm.prank(address(_dgDeployConfig.EMERGENCY_EXECUTION_COMMITTEE));
        _contracts.timelock.emergencyExecute(proposalId);

        _assertTargetMockCalls(_contracts.timelock.getAdminExecutor(), regularStaffCalls);
    }

    function test_protected_deployment_mode_deactivation_in_emergency_mode() external {
        _deployDualGovernanceSetup(true);

        (uint256 proposalId,) = _createAndAssertProposal();

        _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposalViaDualGovernance(proposalId);

        _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanScheduleViaDualGovernance(proposalId, true);
        _scheduleProposalViaDualGovernance(proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);

        vm.prank(address(_dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE));
        _contracts.timelock.activateEmergencyMode();

        assertEq(_contracts.timelock.isEmergencyModeActive(), true);
        assertEq(_contracts.timelock.isEmergencyProtectionEnabled(), true);
        _assertCanExecute(proposalId, false);

        // emergency protection disabled after emergency mode is activated

        _wait(_contracts.timelock.getEmergencyProtectionDetails().emergencyModeDuration.plusSeconds(1));

        assertEq(_contracts.timelock.isEmergencyModeActive(), true);
        assertEq(_contracts.timelock.isEmergencyProtectionEnabled(), true);

        _contracts.timelock.deactivateEmergencyMode();

        assertEq(_contracts.timelock.isEmergencyModeActive(), false);
        assertEq(_contracts.timelock.isEmergencyProtectionEnabled(), false);
        _assertCanExecute(proposalId, false);
    }

    function _createAndAssertProposal() internal returns (uint256, ExternalCall[] memory) {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId = _submitProposal(
            _contracts.dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
        );
        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        return (proposalId, regularStaffCalls);
    }
}
