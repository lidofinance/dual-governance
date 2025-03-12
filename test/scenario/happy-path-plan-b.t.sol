// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";
import {ExecutableProposals, Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";

import {
    Durations,
    Timestamps,
    ContractsDeployment,
    IPotentiallyDangerousContract,
    TGScenarioTestSetup,
    DGScenarioTestSetup,
    ExternalCall,
    ExternalCallHelpers
} from "../utils/integration-tests.sol";

contract PlanBSetup is TGScenarioTestSetup, DGScenarioTestSetup {
    function setUp() external {
        _deployTGSetup({isEmergencyProtectionEnabled: true});
    }

    function testFork_TimelockedGovernanceMigrationToDualGovernance() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        // ---
        // ACT 1. 📈 DAO OPERATES AS USUALLY
        // ---
        {
            uint256 proposalId =
                _submitProposal(regularStaffCalls, "DAO does regular staff on potentially dangerous contract");

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
            _assertCanSchedule(proposalId, false);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
        }

        // ---
        // ACT 2. 😱 DAO IS UNDER ATTACK
        // ---
        uint256 maliciousProposalId;
        {
            // Malicious vote was proposed by the attacker with huge LDO wad (but still not the majority)
            ExternalCall[] memory maliciousCalls = ExternalCallHelpers.create(
                address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ())
            );

            maliciousProposalId = _submitProposal(maliciousCalls, "Rug Pool attempt");

            // the call isn't executable until the delay has passed
            _assertProposalSubmitted(maliciousProposalId);
            _assertCanSchedule(maliciousProposalId, false);

            // some time required to assemble the emergency committee and activate emergency mode
            _wait(_getAfterSubmitDelay().dividedBy(2));

            // malicious call still can't be scheduled
            _assertCanSchedule(maliciousProposalId, false);

            // emergency committee activates emergency mode
            _activateEmergencyMode();

            // after the submit delay has passed, the call still may be scheduled, but executed
            // only the emergency committee
            _wait(_getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

            _assertCanSchedule(maliciousProposalId, true);
            _scheduleProposal(maliciousProposalId);

            _wait(_getAfterScheduleDelay());

            // but the call still not executable
            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(maliciousProposalId);
        }

        // ---
        // ACT 3. 🔫 DAO STRIKES BACK (WITH DUAL GOVERNANCE SHIPMENT)
        // ---
        {
            // Lido contributors work hard to implement and ship the Dual Governance mechanism
            // before the emergency mode is over
            _wait(_getEmergencyModeDuration().dividedBy(2));

            // Time passes but malicious proposal still on hold
            _assertCanExecute(maliciousProposalId, false);

            // Dual Governance is deployed into mainnet
            _setDGDeployConfig(_getDefaultDGDeployConfig({emergencyGovernanceProposer: address(_lido.voting)}));

            _dgDeployedContracts.resealManager = ContractsDeployment.deployResealManager(_timelock);
            _dgDeployedContracts.dualGovernanceConfigProvider =
                ContractsDeployment.deployDualGovernanceConfigProvider(_dgDeployConfig.dualGovernanceConfigProvider);

            _dgDeployedContracts.dualGovernance = ContractsDeployment.deployDualGovernance({
                components: DualGovernance.DualGovernanceComponents({
                    timelock: _timelock,
                    resealManager: _dgDeployedContracts.resealManager,
                    configProvider: _dgDeployedContracts.dualGovernanceConfigProvider
                }),
                signallingTokens: _dgDeployConfig.dualGovernance.signallingTokens,
                sanityCheckParams: _dgDeployConfig.dualGovernance.sanityCheckParams
            });

            ExternalCall[] memory dualGovernanceLaunchCalls = ExternalCallHelpers.create(
                [
                    address(_dgDeployedContracts.dualGovernance),
                    address(_timelock),
                    address(_timelock),
                    address(_timelock),
                    address(_timelock),
                    address(_timelock),
                    address(_timelock)
                ],
                [
                    abi.encodeCall(
                        _dgDeployedContracts.dualGovernance.registerProposer,
                        (address(_lido.voting), _timelock.getAdminExecutor())
                    ),
                    // Only Dual Governance contract can call the Timelock contract
                    abi.encodeCall(_timelock.setGovernance, (address(_dgDeployedContracts.dualGovernance))),
                    // Now the emergency mode may be deactivated (all scheduled calls will be canceled)
                    abi.encodeCall(_timelock.deactivateEmergencyMode, ()),
                    // Setup emergency committee for some period of time until the Dual Governance is battle tested
                    abi.encodeCall(
                        _timelock.setEmergencyProtectionActivationCommittee,
                        (address(_dgDeployConfig.timelock.emergencyActivationCommittee))
                    ),
                    abi.encodeCall(
                        _timelock.setEmergencyProtectionExecutionCommittee,
                        (address(_dgDeployConfig.timelock.emergencyExecutionCommittee))
                    ),
                    abi.encodeCall(
                        _timelock.setEmergencyProtectionEndDate,
                        (_DEFAULT_EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()))
                    ),
                    abi.encodeCall(_timelock.setEmergencyModeDuration, (_DEFAULT_EMERGENCY_MODE_DURATION))
                ]
            );

            // The vote to launch Dual Governance is launched and reached the quorum (the major part of LDO holder still have power)
            uint256 dualGovernanceLunchProposalId =
                _submitProposal(dualGovernanceLaunchCalls, "Launch the Dual Governance");

            // wait until the after submit delay has passed
            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(dualGovernanceLunchProposalId, true);
            _scheduleProposal(dualGovernanceLunchProposalId);
            _assertProposalScheduled(dualGovernanceLunchProposalId);

            _wait(_getAfterScheduleDelay());

            // now emergency committee may execute the proposal
            _emergencyExecute(dualGovernanceLunchProposalId);

            assertEq(_timelock.getGovernance(), address(_dgDeployedContracts.dualGovernance));
            // TODO: check emergency protection also was applied

            // malicious proposal now cancelled
            _assertProposalCancelled(maliciousProposalId);
        }

        // ---
        // ACT 4. 🫡 EMERGENCY COMMITTEE LIFETIME IS ENDED
        // ---
        {
            _wait(_getEmergencyProtectionDuration().plusSeconds(1));
            assertFalse(_timelock.isEmergencyProtectionEnabled());

            uint256 proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO continues regular staff on potentially dangerous contract"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);

            _wait(_getAfterScheduleDelay());

            // but the call still not executable
            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStaffCalls);
        }

        // ---
        // ACT 5. 🔜 NEW DUAL GOVERNANCE VERSION IS COMING
        // ---
        {
            // some time later, the major Dual Governance update release is ready to be launched
            _wait(Durations.from(365 days));

            DualGovernance dualGovernanceV2 = ContractsDeployment.deployDualGovernance({
                components: DualGovernance.DualGovernanceComponents({
                    timelock: _timelock,
                    resealManager: _dgDeployedContracts.resealManager,
                    configProvider: _dgDeployedContracts.dualGovernanceConfigProvider
                }),
                signallingTokens: _dgDeployConfig.dualGovernance.signallingTokens,
                sanityCheckParams: _dgDeployConfig.dualGovernance.sanityCheckParams
            });

            ExternalCall[] memory dualGovernanceUpdateCalls = ExternalCallHelpers.create(
                [address(dualGovernanceV2), address(_timelock), address(_timelock), address(_timelock)],
                [
                    abi.encodeCall(
                        _dgDeployedContracts.dualGovernance.registerProposer,
                        (address(_lido.voting), _timelock.getAdminExecutor())
                    ),
                    // Update the controller for timelock
                    abi.encodeCall(_timelock.setGovernance, address(dualGovernanceV2)),
                    // Assembly the emergency committee again, until the new version of Dual Governance is battle tested
                    abi.encodeCall(
                        _timelock.setEmergencyProtectionEndDate,
                        (_DEFAULT_EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()))
                    ),
                    abi.encodeCall(_timelock.setEmergencyModeDuration, (Durations.from(30 days)))
                ]
            );

            uint256 updateDualGovernanceProposalId =
                _submitProposalByAdminProposer(dualGovernanceUpdateCalls, "Update Dual Governance to V2");

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(updateDualGovernanceProposalId, true);
            _scheduleProposal(updateDualGovernanceProposalId);

            _wait(_getAfterScheduleDelay());

            // but the call still not executable
            _assertCanExecute(updateDualGovernanceProposalId, true);
            _executeProposal(updateDualGovernanceProposalId);

            // new version of dual governance attached to timelock
            assertEq(_timelock.getGovernance(), address(dualGovernanceV2));

            // - emergency protection enabled
            assertTrue(_timelock.isEmergencyProtectionEnabled());

            assertFalse(_timelock.isEmergencyModeActive());

            assertEq(
                _timelock.getEmergencyActivationCommittee(),
                address(_dgDeployConfig.timelock.emergencyActivationCommittee)
            );
            assertEq(
                _timelock.getEmergencyExecutionCommittee(),
                address(_dgDeployConfig.timelock.emergencyExecutionCommittee)
            );
            assertEq(_getEmergencyModeDuration(), Durations.from(30 days));
            assertEq(_getEmergencyModeEndsAfter(), Timestamps.ZERO);

            // use the new version of the dual governance in the future calls
            _dgDeployedContracts.dualGovernance = dualGovernanceV2;
        }

        // ---
        // ACT 7. 📆 DAO CONTINUES THEIR REGULAR DUTIES (PROTECTED BY DUAL GOVERNANCE V2)
        // ---
        {
            uint256 proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            // wait while the after schedule delay has passed
            _wait(_getAfterScheduleDelay());

            // execute the proposal
            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);

            // call successfully executed
            _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStaffCalls);
        }
    }

    function testFork_SubmittedCallsCantBeExecutedAfterEmergencyModeDeactivation() external {
        ExternalCall[] memory maliciousCalls = ExternalCallHelpers.create(
            address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ())
        );

        // schedule some malicious call
        uint256 maliciousProposalId;
        {
            maliciousProposalId = _submitProposal(maliciousCalls, "Rug Pool attempt");

            // malicious calls can't be executed until the delays have passed
            _assertCanSchedule(maliciousProposalId, false);
        }

        // activate emergency mode
        EmergencyProtection.Context memory emergencyState;
        {
            _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

            _activateEmergencyMode();
        }

        // delay for malicious proposal has passed, but it can't be executed because of emergency mode was activated
        {
            // the after submit delay has passed, and proposal can be scheduled, but not executed
            _wait(_timelock.getAfterScheduleDelay() + Durations.from(1 seconds));
            _wait(_timelock.getAfterSubmitDelay().plusSeconds(1));
            _assertCanSchedule(maliciousProposalId, true);

            _scheduleProposal(maliciousProposalId);

            _wait(_timelock.getAfterScheduleDelay().plusSeconds(1));
            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(maliciousProposalId);
        }

        // another malicious call is scheduled during the emergency mode also can't be executed
        uint256 anotherMaliciousProposalId;
        {
            _wait(_getEmergencyModeDuration().dividedBy(2));

            // emergency mode still active
            assertTrue(_timelock.getEmergencyProtectionDetails().emergencyModeEndsAfter > Timestamps.now());

            anotherMaliciousProposalId = _submitProposal(maliciousCalls, "Another Rug Pool attempt");

            // malicious calls can't be executed until the delays have passed
            _assertCanExecute(anotherMaliciousProposalId, false);

            // the after submit delay has passed, and proposal can not be executed
            _wait(_timelock.getAfterSubmitDelay().plusSeconds(1));
            _assertCanSchedule(anotherMaliciousProposalId, true);

            _wait(_timelock.getAfterScheduleDelay().plusSeconds(1));
            _assertCanExecute(anotherMaliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(anotherMaliciousProposalId);
        }

        // emergency mode is over but proposals can't be executed until the emergency mode turned off manually
        {
            _wait(_getEmergencyModeDuration().dividedBy(2));
            assertTrue(emergencyState.emergencyModeEndsAfter < Timestamps.now());

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(maliciousProposalId);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(anotherMaliciousProposalId);
        }

        // anyone can deactivate emergency mode when it's over
        {
            _timelock.deactivateEmergencyMode();

            assertFalse(_timelock.isEmergencyModeActive());
            assertFalse(_timelock.isEmergencyProtectionEnabled());
        }

        // all malicious calls is canceled now and can't be executed
        {
            _assertProposalCancelled(maliciousProposalId);
            _assertProposalCancelled(anotherMaliciousProposalId);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ExecutableProposals.UnexpectedProposalStatus.selector, maliciousProposalId, ProposalStatus.Cancelled
                )
            );
            _executeProposal(maliciousProposalId);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ExecutableProposals.UnexpectedProposalStatus.selector,
                    anotherMaliciousProposalId,
                    ProposalStatus.Cancelled
                )
            );
            _executeProposal(anotherMaliciousProposalId);
        }
    }

    function testFork_EmergencyResetGovernance() external {
        // deploy dual governance full setup
        {
            _deployDGSetup({isEmergencyProtectionEnabled: true});
            assertNotEq(_timelock.getGovernance(), _timelock.getEmergencyGovernance());
        }

        // emergency committee activates emergency mode
        {
            _activateEmergencyMode();
        }

        // before the end of the emergency mode emergency committee can reset the controller to
        // disable dual governance
        {
            _wait(_getEmergencyModeDuration().dividedBy(2));

            assertTrue(_getEmergencyModeEndsAfter() > Timestamps.now());

            _emergencyReset();
        }
    }

    function testFork_ExpiredEmergencyCommitteeHasNoPower() external {
        // deploy dual governance full setup
        {
            _deployDGSetup({isEmergencyProtectionEnabled: true});
            assertNotEq(_timelock.getGovernance(), _timelock.getEmergencyGovernance());
        }

        // wait till the protection duration passes
        {
            _wait(_getEmergencyModeDuration().plusSeconds(1));
        }

        // attempt to activate emergency protection fails
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    EmergencyProtection.EmergencyProtectionExpired.selector, _getEmergencyProtectionEndsAfter()
                )
            );
            this.external__activateEmergencyMode();
        }
    }
}
