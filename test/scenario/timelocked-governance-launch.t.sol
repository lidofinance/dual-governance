// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";
import {ExecutableProposals, Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";

import {
    Duration,
    Durations,
    Timestamps,
    ContractsDeployment,
    TGScenarioTestSetup,
    DGScenarioTestSetup
} from "../utils/integration-tests.sol";

import {ExternalCallsBuilder, ExternalCall} from "scripts/utils/ExternalCallsBuilder.sol";

contract TimelockedGovernanceLaunchScenarioTest is TGScenarioTestSetup, DGScenarioTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    function setUp() external {
        _deployTGSetup({isEmergencyProtectionEnabled: true});
    }

    function testFork_TimelockedGovernanceLaunch_MigrationToDualGovernance() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        _step(unicode"1. 📈 DAO operates as usually");
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

        _step(unicode"2. 😱 DAO is under attack");
        uint256 maliciousProposalId;
        {
            // Malicious vote was proposed by the attacker with huge LDO wad (but still not the majority)
            maliciousProposalId = _submitProposal(_getMaliciousCalls(), "Rug Pool attempt");

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

        _step(unicode"3. 🔫 DAO strikes back (with a DG shipment)");
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

            _dgDeployedContracts.dualGovernance = ContractsDeployment.deployDualGovernance(
                DualGovernance.DualGovernanceComponents({
                    timelock: _timelock,
                    resealManager: _dgDeployedContracts.resealManager,
                    configProvider: _dgDeployedContracts.dualGovernanceConfigProvider
                }),
                _dgDeployConfig.dualGovernance
            );

            ExternalCallsBuilder.Context memory dgLaunchCallsBuilder = ExternalCallsBuilder.create({callsCount: 7});

            dgLaunchCallsBuilder.addCall(
                address(_dgDeployedContracts.dualGovernance),
                abi.encodeCall(
                    _dgDeployedContracts.dualGovernance.registerProposer,
                    (address(_lido.voting), _timelock.getAdminExecutor())
                )
            );

            // Only Dual Governance contract can call the Timelock contract
            dgLaunchCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setGovernance, (address(_dgDeployedContracts.dualGovernance)))
            );

            // Now the emergency mode may be deactivated (all scheduled calls will be canceled)
            dgLaunchCallsBuilder.addCall(address(_timelock), abi.encodeCall(_timelock.deactivateEmergencyMode, ()));

            // Setup emergency committee for some period of time until the Dual Governance is battle tested
            dgLaunchCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionActivationCommittee,
                    (address(_dgDeployConfig.timelock.emergencyActivationCommittee))
                )
            );

            dgLaunchCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionExecutionCommittee,
                    (address(_dgDeployConfig.timelock.emergencyExecutionCommittee))
                )
            );

            dgLaunchCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionEndDate,
                    (_DEFAULT_EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()))
                )
            );

            dgLaunchCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(_timelock.setEmergencyModeDuration, (_DEFAULT_EMERGENCY_MODE_DURATION))
            );

            // The vote to launch Dual Governance is launched and reached the quorum (the major part of LDO holder still have power)
            uint256 dualGovernanceLaunchProposalId =
                _submitProposal(dgLaunchCallsBuilder.getResult(), "Launch the Dual Governance");

            // wait until the after submit delay has passed
            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(dualGovernanceLaunchProposalId, true);
            _scheduleProposal(dualGovernanceLaunchProposalId);
            _assertProposalScheduled(dualGovernanceLaunchProposalId);

            _wait(_getAfterScheduleDelay());

            // now emergency committee may execute the proposal
            _emergencyExecute(dualGovernanceLaunchProposalId);

            assertEq(_timelock.getGovernance(), address(_dgDeployedContracts.dualGovernance));
            assertTrue(_timelock.isEmergencyProtectionEnabled());

            // malicious proposal now cancelled
            _assertProposalCancelled(maliciousProposalId);
        }

        _step(unicode"4. 🫡 Emergency committee lifetime is ended");
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

        _step(unicode"5. 🔜 New Dual Governance version is coming");
        {
            // some time later, the major Dual Governance update release is ready to be launched
            _wait(Durations.from(365 days));

            DualGovernance dualGovernanceV2 = ContractsDeployment.deployDualGovernance(
                DualGovernance.DualGovernanceComponents({
                    timelock: _timelock,
                    resealManager: _dgDeployedContracts.resealManager,
                    configProvider: _dgDeployedContracts.dualGovernanceConfigProvider
                }),
                _dgDeployConfig.dualGovernance
            );

            ExternalCallsBuilder.Context memory dualGovernanceUpdateCallsBuilder =
                ExternalCallsBuilder.create({callsCount: 4});

            dualGovernanceUpdateCallsBuilder.addCall(
                address(dualGovernanceV2),
                abi.encodeCall(
                    _dgDeployedContracts.dualGovernance.registerProposer,
                    (address(_lido.voting), _timelock.getAdminExecutor())
                )
            );
            // Update the controller for timelock
            dualGovernanceUpdateCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setGovernance, address(dualGovernanceV2))
            );
            // Assembly the emergency committee again, until the new version of Dual Governance is battle tested
            dualGovernanceUpdateCallsBuilder.addCall(
                address(_timelock),
                abi.encodeCall(
                    _timelock.setEmergencyProtectionEndDate,
                    (_DEFAULT_EMERGENCY_PROTECTION_DURATION.addTo(Timestamps.now()))
                )
            );

            Duration newEmergencyModeDuration = _DEFAULT_EMERGENCY_MODE_DURATION.plusSeconds(15 days);
            dualGovernanceUpdateCallsBuilder.addCall(
                address(_timelock), abi.encodeCall(_timelock.setEmergencyModeDuration, newEmergencyModeDuration)
            );

            uint256 updateDualGovernanceProposalId = _submitProposalByAdminProposer(
                dualGovernanceUpdateCallsBuilder.getResult(), "Update Dual Governance to V2"
            );

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
            assertEq(_getEmergencyModeDuration(), newEmergencyModeDuration);
            assertEq(_getEmergencyModeEndsAfter(), Timestamps.ZERO);

            // use the new version of the dual governance in the future calls
            _dgDeployedContracts.dualGovernance = dualGovernanceV2;
        }

        _step(unicode"6. 📆 DAO continues their regular duties (protected by Dual Governance V2)");
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
        // schedule some malicious call
        uint256 maliciousProposalId;
        {
            maliciousProposalId = _submitProposal(_getMaliciousCalls(), "Rug Pool attempt");

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

            anotherMaliciousProposalId = _submitProposal(_getMaliciousCalls(), "Another Rug Pool attempt");

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
        {
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
        _step("1. Validate that emergency governance not equal to current governance");
        {
            assertNotEq(_timelock.getGovernance(), _timelock.getEmergencyGovernance());
        }

        _step("1. Wait till the protection duration passes");
        {
            _wait(_getEmergencyProtectionDuration().plusSeconds(1));
        }

        _step("1. An attempt to activate emergency mode fails");
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
