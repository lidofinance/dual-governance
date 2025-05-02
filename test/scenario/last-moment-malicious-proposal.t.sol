// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";

import {IPotentiallyDangerousContract} from "../utils/interfaces/IPotentiallyDangerousContract.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";

import {DGScenarioTestSetup} from "../utils/integration-tests.sol";

contract LastMomentMaliciousProposalSuccessor is DGScenarioTestSetup {
    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});
    }

    function testFork_LastMomentMaliciousProposal() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. DAO submits proposal with regular staff");
        {
            proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
        }

        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        _setupStETHBalance(maliciousActor, PercentsD16.fromBasisPoints(15_00));
        _step("2. Malicious actor starts acquire veto signalling duration");
        {
            _lockStETH(maliciousActor, PercentsD16.fromBasisPoints(12_00));
            _assertVetoSignalingState();

            // almost all veto signalling period has passed
            _wait(Durations.from(20 days));
            _activateNextState();
            _assertVetoSignalingState();
        }

        uint256 maliciousProposalId;
        _step("3. Malicious actor submits malicious proposal");
        {
            _assertVetoSignalingState();

            ExternalCall[] memory maliciousCalls = new ExternalCall[](1);

            maliciousCalls[0] = ExternalCall({
                target: address(_targetMock),
                value: 0,
                payload: abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ())
            });

            maliciousProposalId = _submitProposalByAdminProposer(maliciousCalls, "Malicious Proposal");

            // the both calls aren't executable until the delay has passed
            _assertProposalSubmitted(proposalId);
            _assertProposalSubmitted(maliciousProposalId);
        }

        _step("4. Malicious actor unlock funds from escrow");
        {
            _wait(Durations.from(12 seconds));
            _unlockStETH(maliciousActor);
            _assertVetoSignallingDeactivationState();
        }

        address stEthHolders = makeAddr("STETH_WHALE");
        _setupStETHBalance(stEthHolders, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
        _step("5. StETH holders acquiring quorum to veto malicious proposal");
        {
            _wait(_getVetoSignallingDeactivationMaxDuration().dividedBy(2));
            _lockStETH(stEthHolders, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1));
            _assertVetoSignallingDeactivationState();

            _wait(_getVetoSignallingDeactivationMaxDuration().dividedBy(2).plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();
        }

        _step("6. Malicious proposal can't be executed in the veto cooldown state");
        {
            // the regular proposal can be executed
            _scheduleProposal(proposalId);
            _wait(_getAfterScheduleDelay());

            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);

            vm.expectRevert(
                abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, maliciousProposalId)
            );
            this.external__scheduleProposal(maliciousProposalId);

            _assertProposalSubmitted(maliciousProposalId);
        }

        _step("7. New veto signalling round for malicious proposal is started");
        {
            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();

            // the second seal rage quit support is reached
            _setupStETHBalance(stEthHolders, _getSecondSealRageQuitSupport());
            _lockStETH(stEthHolders, _getSecondSealRageQuitSupport());
            _assertVetoSignalingState();

            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();

            vm.expectRevert(
                abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, maliciousProposalId)
            );
            this.external__scheduleProposal(maliciousProposalId);
        }
    }

    function testFork_ProposalsSubmittedInVetoSignalling_CanBeExecutedOnlyNextVetoCooldownOrNormal() external {
        address maliciousActor = makeAddr("MALICIOUS_ACTOR");
        _step("2. Malicious actor locks first seal threshold to activate VetoSignalling before proposal submission");
        {
            _setupStETHBalance(maliciousActor, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
            _lockStETH(maliciousActor, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1));
            _assertVetoSignalingState();
        }

        uint256 proposalId;
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
        _step("2. DAO submits proposal with regular staff");
        {
            _wait(_getVetoSignallingDuration().dividedBy(2));
            proposalId = _submitProposalByAdminProposer(
                regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
        }

        _step("3. The VetoSignalling & Deactivation passed but proposal still not executable");
        {
            _wait(_getVetoSignallingDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoSignallingDeactivationState();

            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();

            vm.expectRevert(abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, proposalId));
            this.external__scheduleProposal(proposalId);
        }

        _step("4. After the VetoCooldown new VetoSignalling round started");
        {
            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();

            vm.expectRevert(abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, proposalId));
            this.external__scheduleProposal(proposalId);
        }

        _step("5. Proposal executable in the next VetoCooldown");
        {
            _wait(_getVetoSignallingMinDuration().multipliedBy(2));
            _activateNextState();
            _assertVetoSignallingDeactivationState();

            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();

            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);
            _wait(_getAfterScheduleDelay());
            _executeProposal(proposalId);
            _assertProposalExecuted(proposalId);
        }
    }
}
