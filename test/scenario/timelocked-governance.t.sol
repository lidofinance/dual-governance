// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration, Durations} from "contracts/types/Duration.sol";

import {IGovernance} from "contracts/interfaces/IGovernance.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ExternalCall} from "contracts/libraries/ExecutableProposals.sol";
import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";

import {ScenarioTestBlueprint, ExternalCallHelpers} from "../utils/scenario-test-blueprint.sol";

import {IPotentiallyDangerousContract} from "../utils/interfaces/IPotentiallyDangerousContract.sol";

contract TimelockedGovernanceScenario is ScenarioTestBlueprint {
    function setUp() external {
        _deployTimelockedGovernanceSetup({isEmergencyProtectionEnabled: true});
    }

    function test_operatesAsDefault() external {
        // ---
        // Act 1. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_contracts.emergencyGovernance);
        }

        // ---
        // Act 2. Timeskip. Emergency protection is about to be expired.
        // ---
        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory emergencyState =
            _contracts.timelock.getEmergencyProtectionDetails();
        {
            assertEq(_contracts.timelock.isEmergencyProtectionEnabled(), true);
            Duration emergencyProtectionDuration =
                Durations.from(emergencyState.emergencyProtectionEndsAfter.toSeconds() - block.timestamp);
            _wait(emergencyProtectionDuration.plusSeconds(1));
            assertEq(_contracts.timelock.isEmergencyProtectionEnabled(), false);
        }

        // ---
        // Act 3. Emergency committee has no more power to stop proposal flow.
        //
        {
            vm.prank(address(_contracts.timelock.getEmergencyActivationCommittee()));

            vm.expectRevert(
                abi.encodeWithSelector(
                    EmergencyProtection.EmergencyProtectionExpired.selector,
                    emergencyState.emergencyProtectionEndsAfter.toSeconds()
                )
            );
            _contracts.timelock.activateEmergencyMode();

            assertFalse(_contracts.timelock.isEmergencyModeActive());
            assertFalse(_contracts.timelock.isEmergencyProtectionEnabled());
        }

        // ---
        // Act 4. DAO operates as usually. Emergency protection is disabled.
        //
        {
            _daoRegularOperations(_contracts.emergencyGovernance);
        }
    }

    function test_protectionAgainstCapture_cancelProposal() external {
        // ---
        // Act 1. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_contracts.emergencyGovernance);
        }

        // ---
        // Act 2. Someone creates a malicious proposal.
        // ---
        (uint256 maliciousProposalId,) = _submitAndAssertMaliciousProposal();
        {
            _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2));
            _assertCanScheduleViaTimelockedGovernance(maliciousProposalId, false);
        }

        // ---
        // Act 3. Emergency committee activates emergency mode.
        // ---
        {
            vm.prank(address(_dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE));
            _contracts.timelock.activateEmergencyMode();

            assertTrue(_contracts.timelock.isEmergencyModeActive());

            _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

            _assertCanScheduleViaTimelockedGovernance(maliciousProposalId, true);
            _scheduleProposalViaTimelockedGovernance(maliciousProposalId);

            _waitAfterScheduleDelayPassed();

            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(maliciousProposalId);
        }

        // ---
        // Act 4. DAO decides to cancel all pending proposals and deactivate emergency mode.
        // ---
        {
            ExternalCall[] memory deactivateEmergencyModeCall = ExternalCallHelpers.create(
                [address(_contracts.timelock)], [abi.encodeCall(_contracts.timelock.deactivateEmergencyMode, ())]
            );
            uint256 deactivateEmergencyModeProposalId = _submitProposal(
                _contracts.emergencyGovernance, "DAO deactivates emergency mode", deactivateEmergencyModeCall
            );

            _waitAfterSubmitDelayPassed();

            _assertCanScheduleViaTimelockedGovernance(deactivateEmergencyModeProposalId, true);
            _scheduleProposalViaTimelockedGovernance(deactivateEmergencyModeProposalId);
            _assertProposalScheduled(deactivateEmergencyModeProposalId);

            _waitAfterScheduleDelayPassed();

            _assertCanExecute(deactivateEmergencyModeProposalId, false);
            _executeEmergencyExecute(deactivateEmergencyModeProposalId);

            assertFalse(_contracts.timelock.isEmergencyModeActive());
            assertFalse(_contracts.timelock.isEmergencyProtectionEnabled());

            _contracts.timelock.getProposal(maliciousProposalId);
            _assertProposalCancelled(maliciousProposalId);
        }

        // ---
        // Act 4. DAO operates as usually. Emergency protection is disabled.
        //
        {
            _daoRegularOperations(_contracts.emergencyGovernance);
        }
    }

    function test_protectionAgainstCapture_stakersQuit() external {
        // ---
        // Act 1. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_contracts.emergencyGovernance);
        }

        // ---
        // Act 2. Someone creates a malicious proposal.
        // ---
        (uint256 maliciousProposalId,) = _submitAndAssertMaliciousProposal();
        {
            _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2));
            _assertCanScheduleViaTimelockedGovernance(maliciousProposalId, false);
        }

        // ---
        // Act 3. Emergency committee activates emergency mode.
        // ---
        {
            vm.prank(address(_dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE));
            _contracts.timelock.activateEmergencyMode();

            assertTrue(_contracts.timelock.isEmergencyModeActive());

            _wait(_contracts.timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

            _assertCanScheduleViaTimelockedGovernance(maliciousProposalId, true);
            _scheduleProposalViaTimelockedGovernance(maliciousProposalId);

            _waitAfterScheduleDelayPassed();

            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(maliciousProposalId);
        }

        // ---
        // Act 4. DAO decides to not deactivate emergency mode and allow stakers to quit.
        // ---
        {
            IEmergencyProtectedTimelock.EmergencyProtectionDetails memory emergencyState =
                _contracts.timelock.getEmergencyProtectionDetails();
            assertTrue(_contracts.timelock.isEmergencyModeActive());

            _wait(
                Durations.from(emergencyState.emergencyModeEndsAfter.toSeconds()).minusSeconds(block.timestamp)
                    .plusSeconds(2)
            );
            _contracts.timelock.deactivateEmergencyMode();

            assertFalse(_contracts.timelock.isEmergencyModeActive());
        }

        // ---
        // Act 5. DAO operates as usually. Emergency protection is disabled.
        //
        {
            _daoRegularOperations(_contracts.emergencyGovernance);
        }
    }

    function test_timelockedGovernance_upgradeTo_dualGovernance_andBack() external {
        // ---
        // Act 1. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_contracts.emergencyGovernance);
        }

        // ---
        // Act 2. DAO decides to upgrade system to dual governance.
        // ---
        {
            _contracts.resealManager = _deployResealManager(_contracts.timelock);
            _dualGovernanceConfigProvider = _deployDualGovernanceConfigProvider();
            _contracts.dualGovernance = _deployDualGovernance({
                timelock: _contracts.timelock,
                resealManager: _contracts.resealManager,
                configProvider: _dualGovernanceConfigProvider
            });

            ExternalCall[] memory dualGovernanceLaunchCalls = ExternalCallHelpers.create(
                [address(_contracts.dualGovernance), address(_contracts.timelock)],
                [
                    abi.encodeCall(
                        _contracts.dualGovernance.registerProposer,
                        (address(_lido.voting), _contracts.timelock.getAdminExecutor())
                    ),
                    abi.encodeCall(_contracts.timelock.setGovernance, (address(_contracts.dualGovernance)))
                ]
            );

            uint256 dualGovernanceLunchProposalId =
                _submitProposal(_contracts.emergencyGovernance, "Launch the Dual Governance", dualGovernanceLaunchCalls);

            _waitAfterSubmitDelayPassed();

            _assertCanScheduleViaTimelockedGovernance(dualGovernanceLunchProposalId, true);
            _scheduleProposalViaTimelockedGovernance(dualGovernanceLunchProposalId);
            _assertProposalScheduled(dualGovernanceLunchProposalId);

            _waitAfterScheduleDelayPassed();

            _executeProposal(dualGovernanceLunchProposalId);

            assertEq(_contracts.timelock.getGovernance(), address(_contracts.dualGovernance));
        }

        // ---
        // Act 3. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_contracts.dualGovernance);
        }

        // ---
        // Act 4. Someone finds a bug in dual governance. Emergency committee decides to activate emergency mode and DAO decides to downgrade system to single governance.
        // ---
        {
            vm.prank(address(_dgDeployConfig.EMERGENCY_ACTIVATION_COMMITTEE));
            _contracts.timelock.activateEmergencyMode();

            assertTrue(_contracts.timelock.isEmergencyModeActive());

            ExternalCall[] memory timelockedGovernanceLaunchCalls = ExternalCallHelpers.create(
                address(_contracts.timelock),
                [
                    abi.encodeCall(_contracts.timelock.setGovernance, (address(_contracts.emergencyGovernance))),
                    abi.encodeCall(_contracts.timelock.deactivateEmergencyMode, ())
                ]
            );

            uint256 timelockedGovernanceLunchProposalId = _submitProposal(
                _contracts.dualGovernance, "Launch the Timelocked Governance", timelockedGovernanceLaunchCalls
            );

            _waitAfterSubmitDelayPassed();

            _assertCanScheduleViaDualGovernance(timelockedGovernanceLunchProposalId, true);
            _scheduleProposalViaDualGovernance(timelockedGovernanceLunchProposalId);

            _waitAfterScheduleDelayPassed();

            _assertCanExecute(timelockedGovernanceLunchProposalId, false);
            _executeEmergencyExecute(timelockedGovernanceLunchProposalId);

            assertEq(_contracts.timelock.getGovernance(), address(_contracts.emergencyGovernance));
        }

        // ---
        // Act 5. DAO operates as usually. Emergency protection is enabled.
        // ---
        {
            _daoRegularOperations(_contracts.emergencyGovernance);
        }
    }

    function _submitAndAssertProposal(IGovernance governance) internal returns (uint256, ExternalCall[] memory) {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
        uint256 proposalId =
            _submitProposal(governance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls);

        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        return (proposalId, regularStaffCalls);
    }

    function _submitAndAssertMaliciousProposal() internal returns (uint256, ExternalCall[] memory) {
        ExternalCall[] memory maliciousCalls = ExternalCallHelpers.create(
            address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ())
        );

        uint256 proposalId = _submitProposal(
            _contracts.emergencyGovernance, "DAO does malicious staff on potentially dangerous contract", maliciousCalls
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

        _assertTargetMockCalls(_contracts.timelock.getAdminExecutor(), regularStaffCalls);
    }
}
