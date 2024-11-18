// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";

import {Escrow} from "contracts/Escrow.sol";

import {ExternalCallHelpers} from "../utils/executor-calls.sol";
import {ScenarioTestBlueprint, ExternalCall, ExternalCallHelpers} from "../utils/scenario-test-blueprint.sol";

contract SignallingEscrowRotationTest is ScenarioTestBlueprint {
    address private immutable _GHOST_VETOERS = makeAddr("GHOST_VETOERS");
    address private immutable _ALIVE_VETOERS = makeAddr("ALIVE_VETOERS");

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});
        _setupStETHBalance(_GHOST_VETOERS, PercentsD16.fromBasisPoints(15_00));
        _setupStETHBalance(_ALIVE_VETOERS, PercentsD16.fromBasisPoints(15_00));
    }

    function testFork_SignallingEscrowRotation_HappyPath() external {
        _step("1. Some tokens stayed locked in the Signalling Escrow for very long time");
        {
            _lockStETH(_GHOST_VETOERS, PercentsD16.fromBasisPoints(1_75));
            _lockStETH(_ALIVE_VETOERS, PercentsD16.fromBasisPoints(1_75));
            _assertVetoSignalingState();
        }

        uint256 regularProposalId;
        _step(
            "2. DAO operates in a slowdown mode. The DG cycles between VetoSignalling -> VetoSignallingDeactivation -> VetoCooldown states"
        );
        {
            regularProposalId =
                _submitProposalViaDualGovernance("Regular DAO Proposal", _getMockTargetRegularStaffCalls());
            _assertProposalSubmitted(regularProposalId);

            _waitVetoSignallingPassed();
            _waitVetoSignallingDeactivationPassed();
            _assertVetoCooldownState();

            // Proposal can be scheduled only in the next VetoCooldown state
            assertFalse(_dualGovernance.canScheduleProposal(regularProposalId));

            _waitVetoCooldownPassed();

            _waitVetoSignallingPassed();
            _waitVetoSignallingDeactivationPassed();
            _assertVetoCooldownState();

            assertTrue(_dualGovernance.canScheduleProposal(regularProposalId));

            _waitVetoCooldownPassed();
        }

        uint256 rotateSignallingEscrowProposalId;
        _step("3. DAO creates proposal to rotate Signalling Escrow to exclude 'ghost' vetoers from rage quit support");
        {
            _assertVetoSignalingState();
            ExternalCall[] memory rotateSignallingEscrowCalls = ExternalCallHelpers.create(
                address(_dualGovernance), abi.encodeCall(_dualGovernance.rotateSignalingEscrow, ())
            );
            rotateSignallingEscrowProposalId =
                _submitProposalViaDualGovernance("Rotate Signalling Escrow", rotateSignallingEscrowCalls);
            _assertProposalSubmitted(rotateSignallingEscrowProposalId);

            _waitVetoSignallingPassed();
            _waitVetoSignallingDeactivationPassed();
            _assertVetoCooldownState();
            assertFalse(_dualGovernance.canScheduleProposal(rotateSignallingEscrowProposalId));

            _waitVetoCooldownPassed();
        }

        address prevSignallingEscrow;
        _step("4. At the next VetoCooldown state proposal to rotate signalling escrow is executed");
        {
            _waitVetoSignallingPassed();
            _waitVetoSignallingDeactivationPassed();
            _assertVetoCooldownState();

            assertTrue(_dualGovernance.canScheduleProposal(rotateSignallingEscrowProposalId));

            _scheduleProposalViaDualGovernance(rotateSignallingEscrowProposalId);
            _waitAfterScheduleDelayPassed();

            prevSignallingEscrow = _dualGovernance.getVetoSignallingEscrow();
            _executeProposal(rotateSignallingEscrowProposalId);
            address newSignallingEscrow = _dualGovernance.getVetoSignallingEscrow();

            // Escrow was rotated
            assertNotEq(prevSignallingEscrow, newSignallingEscrow);
            assertEq(Escrow(payable(newSignallingEscrow)).getRageQuitSupport(), PercentsD16.from(0));

            // All previous non-executed proposals were cancelled
            assertEq(_timelock.getProposalDetails(regularProposalId).status, ProposalStatus.Cancelled);
        }

        _step("5. Alive vetoers can move their tokens in the new Signalling Escrow");
        {
            vm.startPrank(_ALIVE_VETOERS);
            Escrow(payable(prevSignallingEscrow)).recoverStETH();
            vm.stopPrank();
            _lockStETH(_ALIVE_VETOERS, _lido.stETH.balanceOf(_ALIVE_VETOERS));
            assertTrue(_getVetoSignallingEscrow().getRageQuitSupport() > PercentsD16.from(0));
        }
    }

    function _waitVetoCooldownPassed() internal {
        _assertVetoCooldownState();
        _wait(_dualGovernanceConfigProvider.VETO_COOLDOWN_DURATION().plusSeconds(1));
        _activateNextState();
    }

    function _waitVetoSignallingPassed() internal {
        _assertVetoSignalingState();
        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().dividedBy(2));
        _activateNextState();
    }

    function _waitVetoSignallingDeactivationPassed() internal {
        _assertVetoSignalingDeactivationState();
        _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
        _activateNextState();
    }
}
