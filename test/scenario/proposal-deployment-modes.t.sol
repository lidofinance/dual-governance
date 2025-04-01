// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {ExecutableProposals} from "contracts/libraries/ExecutableProposals.sol";

import {DGScenarioTestSetup} from "../utils/integration-tests.sol";

contract ProposalDeploymentModesScenarioTest is DGScenarioTestSetup {
    function setUp() external {}

    function testFork_RegularDeploymentMode() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        this.external__scheduleProposal(proposalId);

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(proposalId, true);
        _scheduleProposal(proposalId);
        _assertProposalScheduled(proposalId);

        _wait(_getAfterScheduleDelay());

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStaffCalls);
    }

    function testFork_ProtectedDeploymentMode_ExecuteAfterTimelock() external {
        _deployDGSetup({isEmergencyProtectionEnabled: true});

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        this.external__scheduleProposal(proposalId);

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(proposalId, true);
        _scheduleProposal(proposalId);
        _assertProposalScheduled(proposalId);

        _wait(_getAfterScheduleDelay());

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
    }

    function testFork_ProtectedDeploymentMode_ExecuteInEmergencyMode() external {
        _deployDGSetup({isEmergencyProtectionEnabled: true});

        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _createAndAssertProposal();

        _wait(_getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        this.external__scheduleProposal(proposalId);

        _wait(_getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(proposalId, true);
        _scheduleProposal(proposalId);
        _assertProposalScheduled(proposalId);

        _wait(_getAfterScheduleDelay());

        _assertCanExecute(proposalId, true);

        _activateEmergencyMode();

        _assertCanExecute(proposalId, false);

        _emergencyExecute(proposalId);
        _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
    }

    function testFork_ProtectedDeploymentMode_DeactivationInEmergencyMode() external {
        _deployDGSetup({isEmergencyProtectionEnabled: true});

        (uint256 proposalId,) = _createAndAssertProposal();

        _wait(_getAfterSubmitDelay().dividedBy(2));

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        this.external__scheduleProposal(proposalId);

        _wait(_getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(proposalId, true);
        _scheduleProposal(proposalId);
        _assertProposalScheduled(proposalId);

        _wait(_getAfterScheduleDelay());

        _assertCanExecute(proposalId, true);

        _activateEmergencyMode();

        _assertCanExecute(proposalId, false);

        // emergency protection may be disabled by anyone when full emergency mode duration has passed
        _wait(_getEmergencyModeDuration().plusSeconds(1));

        assertEq(_isEmergencyModeActive(), true);
        assertEq(_isEmergencyProtectionEnabled(), true);

        _timelock.deactivateEmergencyMode();

        assertEq(_isEmergencyModeActive(), false);
        assertEq(_isEmergencyProtectionEnabled(), false);
        _assertCanExecute(proposalId, false);
    }

    function _createAndAssertProposal() internal returns (uint256, ExternalCall[] memory) {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId = _submitProposalByAdminProposer(
            regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
        );
        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        return (proposalId, regularStaffCalls);
    }
}
