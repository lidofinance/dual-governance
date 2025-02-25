// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall} from "contracts/libraries/ExecutableProposals.sol";
import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {
    ContractsDeployment,
    TGScenarioTestSetup,
    DGScenarioTestSetup,
    ExternalCall,
    ExternalCallHelpers
} from "../utils/integration-tests.sol";

import {IPotentiallyDangerousContract} from "../utils/interfaces/IPotentiallyDangerousContract.sol";

contract TimelockedGovernanceScenario is TGScenarioTestSetup, DGScenarioTestSetup {
    function setUp() external {
        _deployTGSetup({isEmergencyProtectionEnabled: true});
    }

    function testFork_ProtectionAgainstCapture_CancelAllPendingProposals() external {
        _step("1. DAO operates as usually. Emergency protection is enabled");
        {
            _adoptProposal(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }

        _step("2.  Malicious proposal is submitted");
        (uint256 maliciousProposalId,) = _submitAndAssertMaliciousProposal();
        {
            _wait(_getAfterSubmitDelay().dividedBy(2));
            _assertCanSchedule(maliciousProposalId, false);
        }

        _step("3. Emergency mode is activate");
        {
            _activateEmergencyMode();

            _wait(_getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

            _assertCanSchedule(maliciousProposalId, true);
            _scheduleProposal(maliciousProposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(maliciousProposalId);
        }

        _step("4. DAO decides to cancel all pending proposals and deactivate emergency mode");
        {
            ExternalCall[] memory deactivateEmergencyModeCall = ExternalCallHelpers.create(
                [address(_timelock)], [abi.encodeCall(_timelock.deactivateEmergencyMode, ())]
            );
            uint256 deactivateEmergencyModeProposalId =
                _submitProposal(deactivateEmergencyModeCall, "DAO deactivates emergency mode");

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(deactivateEmergencyModeProposalId, true);
            _scheduleProposal(deactivateEmergencyModeProposalId);
            _assertProposalScheduled(deactivateEmergencyModeProposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(deactivateEmergencyModeProposalId, false);
            _emergencyExecute(deactivateEmergencyModeProposalId);

            assertFalse(_timelock.isEmergencyModeActive());
            assertFalse(_timelock.isEmergencyProtectionEnabled());

            _timelock.getProposal(maliciousProposalId);
            _assertProposalCancelled(maliciousProposalId);
        }

        _step("5. DAO decides to cancel all pending proposals and deactivate emergency mode");
        {
            _adoptProposal(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }
    }

    function testFork_ProtectionAgainstCapture_StakersExodus() external {
        _step("1. DAO operates as usually. Emergency protection is enabled");
        {
            _adoptProposal(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }

        _step("2. Malicious proposal is submitted");
        (uint256 maliciousProposalId,) = _submitAndAssertMaliciousProposal();
        {
            _wait(_getAfterSubmitDelay().dividedBy(2));
            _assertCanSchedule(maliciousProposalId, false);
        }

        _step("3. Emergency committee activates emergency mode");
        {
            _activateEmergencyMode();

            _wait(_getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

            _assertCanSchedule(maliciousProposalId, true);
            _scheduleProposal(maliciousProposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(maliciousProposalId, false);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
            _executeProposal(maliciousProposalId);
        }

        _step("4. DAO decides to not deactivate emergency mode and allow stakers to quit");
        {
            assertTrue(_isEmergencyModeActive());

            vm.warp(_getEmergencyModeEndsAfter().toSeconds() + 1);

            _timelock.deactivateEmergencyMode();

            assertFalse(_isEmergencyModeActive());
        }

        _step("5. DAO operates as usually. Emergency protection is disabled");
        {
            _adoptProposal(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }
    }

    function testFork_TimelockedGovernanceUpgradeToDualGovernanceAndEmergencyReset() external {
        _step("1. DAO operates as usually. Emergency protection is enabled");
        {
            _adoptProposal(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }

        _step("2. DAO decides to upgrade system to dual governance");
        {
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
                _dgDeployConfig.dualGovernance.signallingTokens,
                _dgDeployConfig.dualGovernance.sanityCheckParams
            );

            ExternalCall[] memory dualGovernanceLaunchCalls = ExternalCallHelpers.create(
                [address(_dgDeployedContracts.dualGovernance), address(_timelock)],
                [
                    abi.encodeCall(
                        _dgDeployedContracts.dualGovernance.registerProposer,
                        (address(_lido.voting), _timelock.getAdminExecutor())
                    ),
                    abi.encodeCall(_timelock.setGovernance, (address(_dgDeployedContracts.dualGovernance)))
                ]
            );

            uint256 dualGovernanceLunchProposalId =
                _submitProposal(dualGovernanceLaunchCalls, "Launch the Dual Governance");

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(dualGovernanceLunchProposalId, true);
            _scheduleProposal(dualGovernanceLunchProposalId);
            _assertProposalScheduled(dualGovernanceLunchProposalId);

            _wait(_getAfterScheduleDelay());

            _executeProposal(dualGovernanceLunchProposalId);

            assertEq(_timelock.getGovernance(), address(_dgDeployedContracts.dualGovernance));
        }

        _step("3. DAO operates as usually. Emergency protection is enabled");
        {
            _adoptProposal(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }

        _step(
            string.concat(
                "4. Someone finds a bug in dual governance. Emergency committee decides to activate",
                "emergency mode and DAO decides to downgrade system to single governance"
            )
        );
        {
            _activateEmergencyMode();

            ExternalCall[] memory timelockedGovernanceLaunchCalls = ExternalCallHelpers.create(
                address(_timelock),
                [
                    abi.encodeCall(_timelock.setGovernance, (address(_tgDeployedContracts.timelockedGovernance))),
                    abi.encodeCall(_timelock.deactivateEmergencyMode, ())
                ]
            );

            uint256 timelockedGovernanceLunchProposalId =
                _submitProposalByAdminProposer(timelockedGovernanceLaunchCalls, "Launch the Timelocked Governance");

            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(timelockedGovernanceLunchProposalId, true);
            _scheduleProposal(timelockedGovernanceLunchProposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(timelockedGovernanceLunchProposalId, false);
            _emergencyExecute(timelockedGovernanceLunchProposalId);

            assertEq(_timelock.getGovernance(), address(_tgDeployedContracts.timelockedGovernance));
        }

        _step("5. DAO operates as usually. Emergency protection is enabled");
        {
            _adoptProposal(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }
    }

    function _submitAndAssertMaliciousProposal() internal returns (uint256, ExternalCall[] memory) {
        ExternalCall[] memory maliciousCalls = ExternalCallHelpers.create(
            address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ())
        );

        uint256 proposalId =
            _submitProposal(maliciousCalls, "DAO does malicious staff on potentially dangerous contract");

        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, maliciousCalls);

        return (proposalId, maliciousCalls);
    }
}
