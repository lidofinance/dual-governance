// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";

import {DGRegressionTestSetup} from "../utils/integration-tests.sol";

contract EmergencyProtectionRegressionTest is DGRegressionTestSetup {
    function setUp() external {
        _loadOrDeployDGSetup();
    }

    function testFork_EmergencyReset_HappyPath() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. The proposal is submitted");
        {
            proposalId =
                _submitProposalByAdminProposer(regularStaffCalls, "Propose to doSmth on target passing dual governance");
            _assertSubmittedProposalData(proposalId, regularStaffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(proposalId, false);
        }

        _step("2. The proposal is scheduled");
        {
            // wait until the delay has passed
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(proposalId, true);

            _scheduleProposal(proposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(proposalId);
            _assertCanExecute(proposalId, false);
        }

        _step("3. Emergency mode activated & governance reset");
        {
            // some time passes and emergency committee activates emergency mode
            // and resets the controller
            _wait(_getAfterScheduleDelay().dividedBy(2));

            // committee resets governance
            _activateEmergencyMode();
            _emergencyReset();

            // proposal is canceled now
            _wait(_getAfterScheduleDelay().dividedBy(2).plusSeconds(1));

            // remove canceled call from the timelock
            _assertCanExecute(proposalId, false);
            _assertProposalCancelled(proposalId);
        }
    }

    function testFork_EmergencyProtectionExpiration_HappyPath() external {
        _step("1. DAO operates regularly");
        {
            _adoptProposalByAdminProposer(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }

        _step("2. Emergency protection expires");
        {
            if (_isEmergencyProtectionEnabled()) {
                _wait(_getEmergencyProtectionDuration().plusSeconds(1));
            }
            assertFalse(_isEmergencyProtectionEnabled());
        }

        _step("3. Emergency activation committee has not power");
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    EmergencyProtection.EmergencyProtectionExpired.selector,
                    _getEmergencyProtectionEndsAfter().toSeconds()
                )
            );
            this.external__activateEmergencyMode();
        }

        _step("4. DAO operated as usually when emergency protection expired");
        {
            _adoptProposalByAdminProposer(_getMockTargetRegularStaffCalls({callsCount: 5}), "Regular staff calls");
        }
    }

    function testFork_EmergencyExecution_HappyPath() external {
        ExternalCall[] memory regularStuffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. The proposal is submitted");
        {
            proposalId =
                _submitProposalByAdminProposer(regularStuffCalls, "Propose to doSmth on target passing dual governance");
            _assertSubmittedProposalData(proposalId, regularStuffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(proposalId, false);
        }

        _step("2. The proposal is scheduled");
        {
            // wait until the delay has passed
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(proposalId, true);

            _scheduleProposal(proposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(proposalId);
            _assertCanExecute(proposalId, false);
        }

        _step("3. Emergency mode activated & emergency execution committee executed the proposal");
        {
            // some time passes and emergency committee activates emergency mode
            // and committee executes the proposal
            _wait(_getAfterScheduleDelay().dividedBy(2));

            // committee activates emergency mode
            _activateEmergencyMode();

            _assertCanExecute(proposalId, false);

            _wait(_getAfterScheduleDelay().dividedBy(2).plusSeconds(100));

            // no one can execute the proposal now, except the emergency execution committee
            _assertCanExecute(proposalId, false);
            _assertProposalScheduled(proposalId);

            // emergency execution committee executes the proposal
            _emergencyExecute(proposalId);
            _assertProposalExecuted(proposalId);
            _assertTargetMockCalls(_getAdminExecutor(), regularStuffCalls);
        }
    }

    function testFork_EmergencyModeExpiration_HappyPath() external {
        ExternalCall[] memory regularStuffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. The proposal is submitted");
        {
            proposalId =
                _submitProposalByAdminProposer(regularStuffCalls, "Propose to doSmth on target passing dual governance");
            _assertSubmittedProposalData(proposalId, regularStuffCalls);

            // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
            _assertCanSchedule(proposalId, false);
        }

        _step("2. The proposal is scheduled");
        {
            // wait until the delay has passed
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            // when the first delay is passed and the is no opposition from the stETH holders
            // the proposal can be scheduled
            _assertCanSchedule(proposalId, true);

            _scheduleProposal(proposalId);

            // proposal can't be executed until the second delay has ended
            _assertProposalScheduled(proposalId);
            _assertCanExecute(proposalId, false);
        }

        _step("3. Emergency mode activated");
        {
            // some time passes and emergency committee activates emergency mode
            _wait(_getAfterScheduleDelay().dividedBy(2));

            // committee activates emergency mode
            _activateEmergencyMode();

            _assertCanExecute(proposalId, false);

            // no one can execute the proposal now, except the emergency execution committee
            _assertCanExecute(proposalId, false);
            _assertProposalScheduled(proposalId);
        }

        _step("4. Emergency mode expired and all proposals are cancelled");
        {
            _wait(_getEmergencyModeDuration().plusSeconds(1));
            _deactivateEmergencyMode();
            assertFalse(_isEmergencyModeActive());

            vm.expectRevert("assertion failed");
            this.external__emergencyExecute(proposalId);

            _assertProposalCancelled(proposalId);
        }

        _step("5. Emergency committees have no power anymore");
        {
            vm.expectRevert("Emergency activation committee not set");
            this.external__activateEmergencyMode();
            assertFalse(_isEmergencyModeActive());
        }
    }
}
