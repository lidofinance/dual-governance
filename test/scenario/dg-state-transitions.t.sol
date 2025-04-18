// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {DGScenarioTestSetup, ExternalCall} from "../utils/integration-tests.sol";

contract DualGovernanceStateTransitions is DGScenarioTestSetup {
    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});
        _setupStETHBalance(_VETOER, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
    }

    function testFork_VetoSignalling_HappyPath_MinDuration() external {
        _assertNormalState();

        _lockStETH(_VETOER, _getFirstSealRageQuitSupport() - PercentsD16.from(1));
        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMinDuration().dividedBy(2));

        _activateNextState();
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMinDuration().dividedBy(2).plusSeconds(1));

        _activateNextState();
        _assertVetoSignallingDeactivationState();
    }

    function testFork_VetoSignalling_HappyPath_MaxDuration() public {
        _assertNormalState();

        _lockStETH(_VETOER, _getSecondSealRageQuitSupport());

        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration().dividedBy(2));
        _activateNextState();

        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration().dividedBy(2));
        _activateNextState();

        _assertVetoSignalingState();

        _lockStETH(_VETOER, 1 gwei);

        _wait(Durations.from(1 seconds));
        _activateNextState();

        _assertRageQuitState();
    }

    function testFork_VetoSignallingDeactivationDefaultDuration() external {
        ExternalCall[] memory regularStuffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        // ---
        // ACT 1. DAO SUBMITS CONTROVERSIAL PROPOSAL
        // ---
        {
            proposalId = _submitProposalByAdminProposer(
                regularStuffCalls, "DAO does regular stuff on potentially dangerous contract"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStuffCalls);
        }

        // ---
        // ACT 2. MALICIOUS ACTOR ACCUMULATES FIRST THRESHOLD OF STETH IN THE ESCROW
        // ---
        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        {
            _wait(_timelock.getAfterSubmitDelay().dividedBy(2));
            _setupStETHBalance(maliciousActor, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
            _lockStETH(maliciousActor, PercentsD16.fromBasisPoints(12_00));
            _assertVetoSignalingState();

            _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

            _assertProposalSubmitted(proposalId);

            _wait(_getVetoSignallingDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoSignallingDeactivationState();
        }

        // ---
        // ACT 3. THE VETO SIGNALLING DEACTIVATION DURATION EQUALS TO "VETO_SIGNALLING_DEACTIVATION_MAX_DURATION" DAYS
        // ---
        {
            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoCooldownState();

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStuffCalls);
        }
    }

    function testFork_VetoSignalling_HappyPath_TransitionToNormal() public {
        _assertNormalState();

        _lockStETH(_VETOER, _getFirstSealRageQuitSupport() - PercentsD16.from(1));

        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoSignallingDeactivationState();

        _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoCooldownState();

        vm.startPrank(_VETOER);
        _getVetoSignallingEscrow().unlockStETH();
        vm.stopPrank();

        _wait(_getVetoCooldownDuration().plusSeconds(1));
        _activateNextState();

        _assertNormalState();
    }

    function testFork_VetoSignalling_HappyPath_VetoCooldownLoop() public {
        _assertNormalState();

        _lockStETH(_VETOER, _getFirstSealRageQuitSupport() - PercentsD16.from(1));
        _assertNormalState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoSignallingDeactivationState();

        _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoCooldownState();

        _wait(_getVetoCooldownDuration().plusSeconds(1));
        _activateNextState();

        _assertVetoSignalingState();
    }

    function testFork_VetoSignalling_HappyPath_ToRageQuit() public {
        _assertNormalState();

        _lockStETH(_VETOER, _getSecondSealRageQuitSupport());
        _assertVetoSignalingState();

        _wait(_getVetoSignallingMaxDuration());
        _activateNextState();

        _assertVetoSignalingState();

        _lockStETH(_VETOER, 1 gwei);
        _assertVetoSignalingState();

        _wait(Durations.from(1 seconds));
        _activateNextState();
        _assertRageQuitState();
    }
}
