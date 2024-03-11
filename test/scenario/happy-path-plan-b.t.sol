// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    EmergencyState,
    ProposalStatus,
    EmergencyProtection,
    IDangerousContract,
    ScenarioTestBlueprint,
    ExecutorCall,
    ExecutorCallHelpers,
    EmergencyProtectedTimelock,
    DualGovernanceTimelockController
} from "../utils/scenario-test-blueprint.sol";

import {DAO_VOTING} from "../utils/mainnet-addresses.sol";

import {Proposals} from "contracts/libraries/Proposals.sol";

contract PlanBSetup is ScenarioTestBlueprint {
    function setUp() external {
        _selectFork();
        _deployTarget();
        _deploySingleGovernanceSetup( /* isEmergencyProtectionEnabled */ true);
    }

    function testFork_PlanB_Scenario() external {
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();

        // ---
        // ACT 1. 📈 DAO OPERATES AS USUALLY
        // ---
        {
            uint256 proposalId =
                _submitProposal("DAO does regular staff on potentially dangerous contract", regularStaffCalls);
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);

            // wait until submitted call becomes schedulable
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            // schedule the proposal
            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);

            // wait while the after schedule delay has passed
            vm.warp(block.timestamp + _config.AFTER_SCHEDULE_DELAY() + 1);

            // execute the proposal
            _assertCanExecuteScheduled(proposalId, true);
            _executeScheduledProposal(proposalId);

            // call successfully executed
            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
        }

        // ---
        // ACT 2. 😱 DAO IS UNDER ATTACK
        // ---
        uint256 maliciousProposalId;
        EmergencyState memory emergencyState;
        {
            // Malicious vote was proposed by the attacker with huge LDO wad (but still not the majority)
            ExecutorCall[] memory maliciousCalls =
                ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()));

            maliciousProposalId = _submitProposal("Rug Pool attempt", maliciousCalls);

            // the call isn't executable until the delay has passed
            _assertProposalSubmitted(maliciousProposalId);
            _assertCanSchedule(maliciousProposalId, false);
            _assertCanExecuteScheduled(maliciousProposalId, false);

            // some time required to assemble the emergency committee and activate emergency mode
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2);

            // malicious call still not executable
            _assertCanSchedule(maliciousProposalId, false);
            _assertCanExecuteScheduled(maliciousProposalId, false);

            vm.expectRevert(
                abi.encodeWithSelector(
                    Proposals.InvalidProposalStatus.selector, ProposalStatus.Submitted, ProposalStatus.Scheduled
                )
            );
            _timelock.executeScheduled(maliciousProposalId);

            vm.expectRevert(EmergencyProtectedTimelock.UnscheduledExecutionForbidden.selector);
            _timelock.executeSubmitted(maliciousProposalId);

            // emergency committee activates emergency mode
            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyActivate();

            // emergency mode was successfully activated
            uint256 expectedEmergencyModeEndTimestamp = block.timestamp + _EMERGENCY_MODE_DURATION;
            emergencyState = _timelock.getEmergencyState();
            assertTrue(emergencyState.isEmergencyModeActivated);
            assertEq(emergencyState.emergencyModeEndsAfter, expectedEmergencyModeEndTimestamp);

            // after the submit delay has passed, the call still may be scheduled, but executed
            // only the emergency committee
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2 + 1);

            // malicious call still not executable
            _assertCanSchedule(maliciousProposalId, true);
            _scheduleProposal(maliciousProposalId);

            // wait until the after schedule delay has passed
            vm.warp(block.timestamp + _config.AFTER_SCHEDULE_DELAY() + 1);

            // but the call still not executable
            _assertCanExecuteScheduled(maliciousProposalId, false);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _timelock.executeScheduled(maliciousProposalId);
        }

        // ---
        // ACT 3. 🔫 DAO STRIKES BACK (WITH DUAL GOVERNANCE SHIPMENT)
        // ---
        {
            // Lido contributors work hard to implement and ship the Dual Governance mechanism
            // before the emergency mode is over
            vm.warp(block.timestamp + _EMERGENCY_PROTECTION_DURATION / 2);

            // Time passes but malicious proposal still on hold
            _assertCanExecuteScheduled(maliciousProposalId, false);

            // Dual Governance is deployed into mainnet
            _deployDualGovernanceTimelockController();

            ExecutorCall[] memory dualGovernanceLaunchCalls = ExecutorCallHelpers.create(
                address(_timelock),
                [
                    // Only Dual Governance contract can call the Timelock contract
                    abi.encodeCall(_timelock.setController, (address(_dualGovernanceTimelockController))),
                    // Now the emergency mode may be deactivated (all scheduled calls will be canceled)
                    abi.encodeCall(_timelock.emergencyDeactivate, ()),
                    // Setup emergency committee for some period of time until the Dual Governance is battle tested
                    abi.encodeCall(
                        _timelock.setEmergencyProtection, (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, 30 days)
                    )
                ]
            );

            // The vote to launch Dual Governance is launched and reached the quorum (the major part of LDO holder still have power)
            uint256 dualGovernanceLunchProposalId =
                _submitProposal("Launch the Dual Governance", dualGovernanceLaunchCalls);

            // wait until the after submit delay has passed
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            _scheduleProposal(dualGovernanceLunchProposalId);
            _assertProposalScheduled(dualGovernanceLunchProposalId, /* isExecutable */ false);

            // wait until the after schedule delay has passed
            vm.warp(block.timestamp + _config.AFTER_SCHEDULE_DELAY() + 1);

            // now emergency committee may execute the proposal
            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyExecute(dualGovernanceLunchProposalId);

            // malicious proposal now cancelled
            _assertProposalCanceled(maliciousProposalId);
        }

        // ---
        // ACT 4. 🫡 EMERGENCY COMMITTEE LIFETIME IS ENDED
        // ---
        {
            vm.warp(block.timestamp + _EMERGENCY_PROTECTION_DURATION + 1);
            assertFalse(_timelock.isEmergencyProtectionEnabled());

            // now calls proposed without scheduling
            uint256 proposalId =
                _submitProposal("DAO continues regular staff on potentially dangerous contract", regularStaffCalls);
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);

            // wait until submitted call becomes executable
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            // execute the proposal
            _assertCanSchedule(proposalId, false);
            _assertCanExecuteSubmitted(proposalId, true);

            _executeSubmittedProposal(proposalId);

            // call successfully executed
            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
        }

        // ---
        // ACT 5. 🔜 NEW DUAL GOVERNANCE VERSION IS COMING
        // ---
        {
            // some time later, the major Dual Governance update release is ready to be launched
            vm.warp(block.timestamp + 365 days);
            DualGovernanceTimelockController dualGovernanceTimelockControllerV2 =
                new DualGovernanceTimelockController(address(_config), address(_timelock), address(_escrowMasterCopy));

            ExecutorCall[] memory dualGovernanceUpdateCalls = ExecutorCallHelpers.create(
                address(_timelock),
                [
                    // Update the controller for timelock
                    abi.encodeCall(_timelock.setController, address(dualGovernanceTimelockControllerV2)),
                    // Assembly the emergency committee again, until the new version of Dual Governance is battle tested
                    abi.encodeCall(
                        _timelock.setEmergencyProtection, (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, 30 days)
                    )
                ]
            );

            uint256 updateDualGovernanceProposalId =
                _submitProposal("Update Dual Governance to V2", dualGovernanceUpdateCalls);

            // wait until the proposal is executable
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            _assertCanExecuteSubmitted(updateDualGovernanceProposalId, true);
            _executeSubmittedProposal(updateDualGovernanceProposalId);

            // validate the proposal was applied correctly:

            // new version of dual governance attached to timelock
            assertEq(_timelock.getController(), address(dualGovernanceTimelockControllerV2));

            // - emergency protection enabled
            assertTrue(_timelock.isEmergencyProtectionEnabled());

            emergencyState = _timelock.getEmergencyState();
            assertEq(emergencyState.committee, _EMERGENCY_COMMITTEE);
            assertFalse(emergencyState.isEmergencyModeActivated);
            assertEq(emergencyState.emergencyModeDuration, 30 days);
            assertEq(emergencyState.emergencyModeEndsAfter, 0);

            // use the new version of the dual governance in the future calls
            _dualGovernanceTimelockController = dualGovernanceTimelockControllerV2;
        }

        // ---
        // ACT 7. 📆 DAO CONTINUES THEIR REGULAR DUTIES (PROTECTED BY DUAL GOVERNANCE V2)
        // ---
        {
            uint256 proposalId =
                _submitProposal("DAO does regular staff on potentially dangerous contract", regularStaffCalls);
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);

            // wait until submitted call becomes schedulable
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            // schedule the proposal
            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);

            // wait while the after schedule delay has passed
            vm.warp(block.timestamp + _config.AFTER_SCHEDULE_DELAY() + 1);

            // execute the proposal
            _assertCanExecuteScheduled(proposalId, true);
            _executeScheduledProposal(proposalId);

            // call successfully executed
            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
        }
    }

    function testFork_ScheduledCallsCantBeExecutedAfterEmergencyModeDeactivation() external {
        ExecutorCall[] memory maliciousCalls =
            ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()));

        // schedule some malicious call
        uint256 maliciousProposalId;
        {
            maliciousProposalId = _submitProposal("Rug Pool attempt", maliciousCalls);

            // malicious calls can't be executed until the delays have passed
            _assertCanExecuteScheduled(maliciousProposalId, false);
            _assertCanExecuteSubmitted(maliciousProposalId, false);
        }

        // activate emergency mode
        EmergencyState memory emergencyState;
        {
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2);

            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyActivate();

            emergencyState = _timelock.getEmergencyState();
            assertTrue(emergencyState.isEmergencyModeActivated);
        }

        // delay for malicious proposal has passed, but it can't be executed because of emergency mode was activated
        {
            // the after submit delay has passed, and proposal can be scheduled, but not executed
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2 + 1);
            _assertCanSchedule(maliciousProposalId, true);

            _scheduleProposal(maliciousProposalId);

            vm.warp(block.timestamp + _config.AFTER_SCHEDULE_DELAY() + 1);
            _assertCanExecuteScheduled(maliciousProposalId, false);
            _assertCanExecuteSubmitted(maliciousProposalId, false);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _timelock.executeScheduled(maliciousProposalId);
        }

        // another malicious call is scheduled during the emergency mode also can't be executed
        uint256 anotherMaliciousProposalId;
        {
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);

            // emergency mode still active
            assertTrue(emergencyState.emergencyModeEndsAfter > block.timestamp);

            anotherMaliciousProposalId = _submitProposal("Another Rug Pool attempt", maliciousCalls);

            // malicious calls can't be executed until the delays have passed
            _assertCanExecuteScheduled(anotherMaliciousProposalId, false);
            _assertCanExecuteSubmitted(anotherMaliciousProposalId, false);

            // the after submit delay has passed, and proposal can be scheduled, but not executed
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);
            _assertCanSchedule(anotherMaliciousProposalId, true);

            _timelock.schedule(anotherMaliciousProposalId);

            vm.warp(block.timestamp + _config.AFTER_SCHEDULE_DELAY() + 1);
            _assertCanExecuteScheduled(anotherMaliciousProposalId, false);
            _assertCanExecuteSubmitted(anotherMaliciousProposalId, false);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _executeScheduledProposal(anotherMaliciousProposalId);
        }

        // emergency mode is over but proposals can't be executed until the emergency mode turned off manually
        {
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);
            assertTrue(emergencyState.emergencyModeEndsAfter < block.timestamp);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _executeScheduledProposal(maliciousProposalId);

            vm.expectRevert(EmergencyProtectedTimelock.UnscheduledExecutionForbidden.selector);
            _executeSubmittedProposal(anotherMaliciousProposalId);
        }

        // anyone can deactivate emergency mode when it's over
        {
            _timelock.emergencyDeactivate();

            emergencyState = _timelock.getEmergencyState();
            assertFalse(emergencyState.isEmergencyModeActivated);
            assertFalse(_timelock.isEmergencyProtectionEnabled());
        }

        // all malicious calls is canceled now and can't be executed
        {
            _assertProposalCanceled(maliciousProposalId);
            _assertProposalCanceled(anotherMaliciousProposalId);

            vm.expectRevert(
                abi.encodeWithSelector(
                    Proposals.InvalidProposalStatus.selector, ProposalStatus.Canceled, ProposalStatus.Scheduled
                )
            );
            _executeScheduledProposal(maliciousProposalId);

            vm.expectRevert(
                abi.encodeWithSelector(
                    Proposals.InvalidProposalStatus.selector, ProposalStatus.Canceled, ProposalStatus.Submitted
                )
            );
            _executeSubmittedProposal(anotherMaliciousProposalId);
        }
    }

    function testFork_EmergencyResetGovernance() external {
        // deploy dual governance full setup
        {
            _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ true);
            assertNotEq(_timelock.getController(), address(0));
        }

        // emergency committee activates emergency mode
        EmergencyState memory emergencyState;
        {
            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyActivate();

            emergencyState = _timelock.getEmergencyState();
            assertTrue(emergencyState.isEmergencyModeActivated);
        }

        // before the end of the emergency mode emergency committee can reset the controller to
        // disable dual governance
        {
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);
            assertTrue(emergencyState.emergencyModeEndsAfter > block.timestamp);

            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyReset();

            assertEq(_timelock.getGovernance(), address(_proposersTimelockLaunchpad));
            assertEq(_timelock.getController(), address(0));

            emergencyState = _timelock.getEmergencyState();
            assertEq(emergencyState.committee, address(0));
            assertEq(emergencyState.emergencyModeDuration, 0);
            assertEq(emergencyState.emergencyModeEndsAfter, 0);
            assertFalse(emergencyState.isEmergencyModeActivated);
        }
    }

    function testFork_ExpiredEmergencyCommitteeHasNoPower() external {
        // deploy dual governance full setup
        {
            _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ true);
            assertNotEq(_timelock.getController(), address(0));
        }

        // wait till the protection duration passes
        {
            vm.warp(block.timestamp + _EMERGENCY_PROTECTION_DURATION + 1);
        }

        // attempt to activate emergency protection fails
        {
            vm.expectRevert(EmergencyProtection.EmergencyCommitteeExpired.selector);
            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyActivate();
        }
    }
}
