// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    EmergencyState,
    EmergencyProtection,
    IDangerousContract,
    ScenarioTestBlueprint,
    ExecutorCall,
    ExecutorCallHelpers,
    DualGovernance
} from "../utils/scenario-test-blueprint.sol";

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
            uint256 proposalId = _submitProposal(
                _singleGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);

            // wait until submitted call becomes executable
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            // execute the proposal

            // execute the proposal
            _assertCanExecute(_singleGovernance, proposalId, true);
            _executeProposal(_singleGovernance, proposalId);

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

            maliciousProposalId = _submitProposal(_singleGovernance, "Rug Pool attempt", maliciousCalls);

            // the call isn't executable until the delay has passed
            _assertProposalSubmitted(maliciousProposalId);
            _assertCanExecute(_singleGovernance, maliciousProposalId, false);

            // some time required to assemble the emergency committee and activate emergency mode
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() / 2);

            // malicious call still not executable
            _assertCanExecute(_singleGovernance, maliciousProposalId, false);

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

            // but the call still not executable
            _assertCanExecute(_singleGovernance, maliciousProposalId, false);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _executeProposal(_singleGovernance, maliciousProposalId);
        }

        // ---
        // ACT 3. 🔫 DAO STRIKES BACK (WITH DUAL GOVERNANCE SHIPMENT)
        // ---
        {
            // Lido contributors work hard to implement and ship the Dual Governance mechanism
            // before the emergency mode is over
            vm.warp(block.timestamp + _EMERGENCY_PROTECTION_DURATION / 2);

            // Time passes but malicious proposal still on hold
            _assertCanExecute(_singleGovernance, maliciousProposalId, false);

            // Dual Governance is deployed into mainnet
            _deployDualGovernance();

            ExecutorCall[] memory dualGovernanceLaunchCalls = ExecutorCallHelpers.create(
                address(_timelock),
                [
                    // Only Dual Governance contract can call the Timelock contract
                    abi.encodeCall(_timelock.setGovernance, (address(_dualGovernance))),
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
                _submitProposal(_singleGovernance, "Launch the Dual Governance", dualGovernanceLaunchCalls);

            // wait until the after submit delay has passed
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

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
            uint256 proposalId = _submitProposal(
                _dualGovernance, "DAO continues regular staff on potentially dangerous contract", regularStaffCalls
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);

            // wait until submitted call becomes executable
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            // execute the proposal
            _assertCanSchedule(proposalId, false);
            _assertCanExecute(_dualGovernance, proposalId, true);

            _executeProposal(_dualGovernance, proposalId);

            // call successfully executed
            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
        }

        // ---
        // ACT 5. 🔜 NEW DUAL GOVERNANCE VERSION IS COMING
        // ---
        {
            // some time later, the major Dual Governance update release is ready to be launched
            vm.warp(block.timestamp + 365 days);
            DualGovernance dualGovernanceV2 =
                new DualGovernance(address(_config), address(_timelock), address(_escrowMasterCopy), _ADMIN_PROPOSER);

            ExecutorCall[] memory dualGovernanceUpdateCalls = ExecutorCallHelpers.create(
                address(_timelock),
                [
                    // Update the controller for timelock
                    abi.encodeCall(_timelock.setGovernance, address(dualGovernanceV2)),
                    // Assembly the emergency committee again, until the new version of Dual Governance is battle tested
                    abi.encodeCall(
                        _timelock.setEmergencyProtection, (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, 30 days)
                    )
                ]
            );

            uint256 updateDualGovernanceProposalId =
                _submitProposal(_dualGovernance, "Update Dual Governance to V2", dualGovernanceUpdateCalls);

            // wait until the proposal is executable
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);

            _assertCanExecute(_dualGovernance, updateDualGovernanceProposalId, true);
            _executeProposal(_dualGovernance, updateDualGovernanceProposalId);

            // validate the proposal was applied correctly:

            // new version of dual governance attached to timelock
            assertEq(_timelock.getGovernance(), address(dualGovernanceV2));

            // - emergency protection enabled
            assertTrue(_timelock.isEmergencyProtectionEnabled());

            emergencyState = _timelock.getEmergencyState();
            assertEq(emergencyState.committee, _EMERGENCY_COMMITTEE);
            assertFalse(emergencyState.isEmergencyModeActivated);
            assertEq(emergencyState.emergencyModeDuration, 30 days);
            assertEq(emergencyState.emergencyModeEndsAfter, 0);

            // use the new version of the dual governance in the future calls
            _dualGovernance = dualGovernanceV2;
        }

        // ---
        // ACT 7. 📆 DAO CONTINUES THEIR REGULAR DUTIES (PROTECTED BY DUAL GOVERNANCE V2)
        // ---
        {
            uint256 proposalId = _submitProposal(
                _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
            );
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
            _assertCanExecute(_dualGovernance, proposalId, true);
            _executeProposal(_dualGovernance, proposalId);

            // call successfully executed
            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
        }
    }

    function testFork_SubmittedCallsCantBeExecutedAfterEmergencyModeDeactivation() external {
        ExecutorCall[] memory maliciousCalls =
            ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()));

        // schedule some malicious call
        uint256 maliciousProposalId;
        {
            maliciousProposalId = _submitProposal(_singleGovernance, "Rug Pool attempt", maliciousCalls);

            // malicious calls can't be executed until the delays have passed
            _assertCanExecute(_singleGovernance, maliciousProposalId, false);
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
            _assertCanExecute(_singleGovernance, maliciousProposalId, false);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _executeProposal(_singleGovernance, maliciousProposalId);
        }

        // another malicious call is scheduled during the emergency mode also can't be executed
        uint256 anotherMaliciousProposalId;
        {
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);

            // emergency mode still active
            assertTrue(emergencyState.emergencyModeEndsAfter > block.timestamp);

            anotherMaliciousProposalId = _submitProposal(_singleGovernance, "Another Rug Pool attempt", maliciousCalls);

            // malicious calls can't be executed until the delays have passed
            _assertCanExecute(_singleGovernance, anotherMaliciousProposalId, false);

            // the after submit delay has passed, and proposal can not be executed
            vm.warp(block.timestamp + _config.AFTER_SUBMIT_DELAY() + 1);
            _assertCanExecute(_singleGovernance, anotherMaliciousProposalId, false);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _executeProposal(_singleGovernance, anotherMaliciousProposalId);
        }

        // emergency mode is over but proposals can't be executed until the emergency mode turned off manually
        {
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);
            assertTrue(emergencyState.emergencyModeEndsAfter < block.timestamp);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _executeProposal(_singleGovernance, maliciousProposalId);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _executeProposal(_singleGovernance, anotherMaliciousProposalId);
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

            vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, maliciousProposalId));
            _executeProposal(_singleGovernance, maliciousProposalId);

            vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotSubmitted.selector, anotherMaliciousProposalId));
            _executeProposal(_singleGovernance, anotherMaliciousProposalId);
        }
    }

    function testFork_EmergencyResetGovernance() external {
        // deploy dual governance full setup
        {
            _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ true);
            assertNotEq(_timelock.getGovernance(), _config.EMERGENCY_CONTROLLER());
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

            assertEq(_timelock.getGovernance(), _config.EMERGENCY_CONTROLLER());

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
            assertNotEq(_timelock.getGovernance(), _config.EMERGENCY_CONTROLLER());
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
