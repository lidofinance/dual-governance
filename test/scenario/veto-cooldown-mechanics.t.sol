// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGScenarioTestSetup, IPotentiallyDangerousContract, IRageQuitEscrow} from "../utils/integration-tests.sol";

import {PercentsD16} from "contracts/types/PercentD16.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";

import {ExternalCallsBuilder, ExternalCall} from "scripts/utils/external-calls-builder.sol";

contract VetoCooldownMechanicsTest is DGScenarioTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: false});
    }

    function testFork_ProposalsSubmittedInRageQuit_CanBeExecutedOnlyNextVetoCooldownOrNormal() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. The proposal is submitted");
        {
            proposalId =
                _submitProposalByAdminProposer(regularStaffCalls, "Propose to doSmth on target passing dual governance");

            _assertSubmittedProposalData(proposalId, _timelock.getAdminExecutor(), regularStaffCalls);
            _assertCanSchedule(proposalId, false);
        }

        address vetoer = makeAddr("MALICIOUS_ACTOR");
        _setupStETHBalance(vetoer, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
        _step("2. The second seal rage quit support is acquired");
        {
            _lockStETH(vetoer, _getSecondSealRageQuitSupport() + PercentsD16.fromBasisPoints(1));
            _assertVetoSignalingState();

            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();
        }

        uint256 anotherProposalId;
        _step("3. Another proposal is submitted during the rage quit state");
        {
            _activateNextState();
            _assertRageQuitState();

            ExternalCallsBuilder.Context memory builder = ExternalCallsBuilder.create({callsCount: 1});
            builder.addCall(address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ()));

            anotherProposalId = _submitProposalByAdminProposer(builder.getResult(), "Another Proposal");
        }

        _step("4. Rage quit is finalized");
        {
            // request withdrawals batches
            IRageQuitEscrow rageQuitEscrow = _getRageQuitEscrow();

            while (!rageQuitEscrow.isWithdrawalsBatchesClosed()) {
                rageQuitEscrow.requestNextWithdrawalsBatch(96);
            }

            _finalizeWithdrawalQueue();

            while (rageQuitEscrow.getUnclaimedUnstETHIdsCount() > 0) {
                rageQuitEscrow.claimNextWithdrawalsBatch(128);
            }

            rageQuitEscrow.startRageQuitExtensionPeriod();

            _wait(_getRageQuitExtensionPeriodDuration().plusSeconds(1));
            assertTrue(rageQuitEscrow.isRageQuitFinalized());
        }

        _step("5. Proposal submitted before rage quit is executable");
        {
            _activateNextState();
            _assertVetoCooldownState();

            this.external__scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);
        }

        _step("6. Proposal submitted during rage quit is not executable");
        {
            _activateNextState();
            _assertVetoCooldownState();

            vm.expectRevert(
                abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, anotherProposalId)
            );
            this.external__scheduleProposal(anotherProposalId);
        }
    }
}
