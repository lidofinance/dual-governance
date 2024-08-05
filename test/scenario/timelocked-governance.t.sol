// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGovernance} from "contracts/interfaces/ITimelock.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";
import {Durations, minus} from "contracts/types/Duration.sol";
import {ExternalCall} from "contracts/libraries/ExecutableProposals.sol";
import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";

import {ScenarioTestBlueprint, ExternalCallHelpers, IDangerousContract} from "../utils/scenario-test-blueprint.sol";

contract TimelockedGovernanceScenario is ScenarioTestBlueprint {
    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployTimelockedGovernanceSetup( /* isEmergencyProtectionEnabled */ true);
    }

    function test_operatesAsDefault() external {
        // ---
        // Act 1. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_timelockedGovernance);
        }

        // ---
        // Act 2. Timeskip. Emergency protection is about to be expired.
        // ---
        EmergencyProtection.Context memory emergencyState = _timelock.getEmergencyProtectionContext();
        {
            assertEq(_timelock.isEmergencyProtectionEnabled(), true);
            Duration emergencyProtectionDuration =
                Durations.from(emergencyState.emergencyProtectionEndsAfter.toSeconds() - block.timestamp);
            _wait(emergencyProtectionDuration.plusSeconds(1));
            assertEq(_timelock.isEmergencyProtectionEnabled(), false);
        }

        // ---
        // Act 3. Emergency committee has no more power to stop proposal flow.
        //
        {
            vm.prank(address(emergencyState.emergencyActivationCommittee));

            vm.expectRevert(
                abi.encodeWithSelector(
                    EmergencyProtection.EmergencyProtectionExpired.selector,
                    emergencyState.emergencyProtectionEndsAfter.toSeconds()
                )
            );
            _timelock.activateEmergencyMode();

            assertFalse(_timelock.isEmergencyModeActive());
            assertFalse(_timelock.isEmergencyProtectionEnabled());
        }

        // ---
        // Act 4. DAO operates as usually. Emergency protection is disabled.
        //
        {
            _daoRegularOperations(_timelockedGovernance);
        }
    }

    function test_protectionAgainstCapture_cancelProposal() external {
        // ---
        // Act 1. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_timelockedGovernance);
        }

        // ---
        // Act 2. Someone creates a malicious proposal.
        // ---
        (uint256 maliciousProposalId,) = _submitAndAssertMaliciousProposal();
        {
            _wait(_timelock.getAfterSubmitDelay().dividedBy(2));
            _assertCanSchedule(_timelockedGovernance, maliciousProposalId, false);
        }

        // ---
        // Act 3. Emergency committee activates emergency mode.
        // ---
        {
            vm.prank(address(_emergencyActivationCommittee));
            _timelock.activateEmergencyMode();

            assertTrue(_timelock.isEmergencyModeActive());

            _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

            _assertCanSchedule(_timelockedGovernance, maliciousProposalId, true);
            _scheduleProposal(_timelockedGovernance, maliciousProposalId);

            _waitAfterScheduleDelayPassed();

            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeState.selector, false));
            _executeProposal(maliciousProposalId);
        }

        // ---
        // Act 4. DAO decides to cancel all pending proposals and deactivate emergency mode.
        // ---
        {
            ExternalCall[] memory deactivateEmergencyModeCall = ExternalCallHelpers.create(
                [address(_timelock)], [abi.encodeCall(_timelock.deactivateEmergencyMode, ())]
            );
            uint256 deactivateEmergencyModeProposalId =
                _submitProposal(_timelockedGovernance, "DAO deactivates emergency mode", deactivateEmergencyModeCall);

            _waitAfterSubmitDelayPassed();

            _assertCanSchedule(_timelockedGovernance, deactivateEmergencyModeProposalId, true);
            _scheduleProposal(_timelockedGovernance, deactivateEmergencyModeProposalId);
            _assertProposalScheduled(deactivateEmergencyModeProposalId);

            _waitAfterScheduleDelayPassed();

            _assertCanExecute(deactivateEmergencyModeProposalId, false);
            _executeEmergencyExecute(deactivateEmergencyModeProposalId);

            assertFalse(_timelock.isEmergencyModeActive());
            assertFalse(_timelock.isEmergencyProtectionEnabled());

            _timelock.getProposal(maliciousProposalId);
            _assertProposalCancelled(maliciousProposalId);
        }

        // ---
        // Act 4. DAO operates as usually. Emergency protection is disabled.
        //
        {
            _daoRegularOperations(_timelockedGovernance);
        }
    }

    function test_protectionAgainstCapture_stakersQuit() external {
        // ---
        // Act 1. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_timelockedGovernance);
        }

        // ---
        // Act 2. Someone creates a malicious proposal.
        // ---
        (uint256 maliciousProposalId,) = _submitAndAssertMaliciousProposal();
        {
            _wait(_timelock.getAfterSubmitDelay().dividedBy(2));
            _assertCanSchedule(_timelockedGovernance, maliciousProposalId, false);
        }

        // ---
        // Act 3. Emergency committee activates emergency mode.
        // ---
        {
            vm.prank(address(_emergencyActivationCommittee));
            _timelock.activateEmergencyMode();

            assertTrue(_timelock.isEmergencyModeActive());

            _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

            _assertCanSchedule(_timelockedGovernance, maliciousProposalId, true);
            _scheduleProposal(_timelockedGovernance, maliciousProposalId);

            _waitAfterScheduleDelayPassed();

            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeState.selector, false));
            _executeProposal(maliciousProposalId);
        }

        // ---
        // Act 4. DAO decides to not deactivate emergency mode and allow stakers to quit.
        // ---
        {
            EmergencyProtection.Context memory emergencyState = _timelock.getEmergencyProtectionContext();
            assertTrue(_timelock.isEmergencyModeActive());

            _wait(
                Durations.from(emergencyState.emergencyModeEndsAfter.toSeconds()).minusSeconds(block.timestamp)
                    .plusSeconds(2)
            );
            _timelock.deactivateEmergencyMode();

            assertFalse(_timelock.isEmergencyModeActive());
        }

        // ---
        // Act 5. DAO operates as usually. Emergency protection is disabled.
        //
        {
            _daoRegularOperations(_timelockedGovernance);
        }
    }

    function test_timelockedGovernance_upgradeTo_dualGovernance_andBack() external {
        // ---
        // Act 1. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_timelockedGovernance);
        }

        // ---
        // Act 2. DAO decides to upgrade system to dual governance.
        // ---
        {
            _deployDualGovernance();

            ExternalCall[] memory dualGovernanceLaunchCalls = ExternalCallHelpers.create(
                [address(_timelock)], [abi.encodeCall(_timelock.setGovernance, (address(_dualGovernance)))]
            );

            uint256 dualGovernanceLunchProposalId =
                _submitProposal(_timelockedGovernance, "Launch the Dual Governance", dualGovernanceLaunchCalls);

            _waitAfterSubmitDelayPassed();

            _assertCanSchedule(_timelockedGovernance, dualGovernanceLunchProposalId, true);
            _scheduleProposal(_timelockedGovernance, dualGovernanceLunchProposalId);
            _assertProposalScheduled(dualGovernanceLunchProposalId);

            _waitAfterScheduleDelayPassed();

            _executeProposal(dualGovernanceLunchProposalId);

            assertEq(_timelock.getGovernance(), address(_dualGovernance));
        }

        // ---
        // Act 3. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_dualGovernance);
        }

        // ---
        // Act 4. Someone finds a bug in dual governance. Emergency committee decides to activate emergency mode and DAO decides to downgrade system to single governance.
        // ---
        {
            vm.prank(address(_emergencyActivationCommittee));
            _timelock.activateEmergencyMode();

            assertTrue(_timelock.isEmergencyModeActive());

            ExternalCall[] memory timelockedGovernanceLaunchCalls = ExternalCallHelpers.create(
                address(_timelock),
                [
                    abi.encodeCall(_timelock.setGovernance, (address(_timelockedGovernance))),
                    abi.encodeCall(_timelock.deactivateEmergencyMode, ())
                ]
            );

            uint256 timelockedGovernanceLunchProposalId =
                _submitProposal(_dualGovernance, "Launch the Timelocked Governance", timelockedGovernanceLaunchCalls);

            _waitAfterSubmitDelayPassed();

            _assertCanSchedule(_dualGovernance, timelockedGovernanceLunchProposalId, true);
            _scheduleProposal(_dualGovernance, timelockedGovernanceLunchProposalId);

            _waitAfterScheduleDelayPassed();

            _assertCanExecute(timelockedGovernanceLunchProposalId, false);
            _executeEmergencyExecute(timelockedGovernanceLunchProposalId);

            assertEq(_timelock.getGovernance(), address(_timelockedGovernance));
        }

        // ---
        // Act 5. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_timelockedGovernance);
        }
    }

    function _submitAndAssertProposal(IGovernance governance) internal returns (uint256, ExternalCall[] memory) {
        ExternalCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();
        uint256 proposalId =
            _submitProposal(governance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls);

        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        return (proposalId, regularStaffCalls);
    }

    function _submitAndAssertMaliciousProposal() internal returns (uint256, ExternalCall[] memory) {
        ExternalCall[] memory maliciousCalls =
            ExternalCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()));

        uint256 proposalId = _submitProposal(
            _timelockedGovernance, "DAO does malicious staff on potentially dangerous contract", maliciousCalls
        );

        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, maliciousCalls);

        return (proposalId, maliciousCalls);
    }

    function _daoRegularOperations(IGovernance governance) internal {
        (uint256 proposalId, ExternalCall[] memory regularStaffCalls) = _submitAndAssertProposal(governance);

        _waitAfterSubmitDelayPassed();

        _assertCanSchedule(governance, proposalId, true);
        _scheduleProposal(governance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStaffCalls);
    }
}
