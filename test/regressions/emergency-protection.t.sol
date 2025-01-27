// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGRegressionTestSetup, ExternalCall, ExternalCallHelpers} from "../utils/integration-tests.sol";

import {ITiebreaker} from "contracts/interfaces/ITiebreaker.sol";

import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

contract EmergencyProtectionRegressionTest is DGRegressionTestSetup {
    function setUp() external {
        _loadOrDeployDGSetup();
    }

    function testFork_EmergencyReset() external {
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

        _step("3. Emergency mode activated &  governance reset");
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
}
