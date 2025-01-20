// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PercentsD16} from "contracts/types/PercentD16.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";

import {IPotentiallyDangerousContract} from "../utils/interfaces/IPotentiallyDangerousContract.sol";

import {LidoUtils} from "../utils/lido-utils.sol";
import {ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";
import {Escrow, ExternalCall, ExternalCallHelpers} from "../utils/test-utils.sol";

contract VetoCooldownMechanicsTest is ScenarioTestBlueprint {
    using LidoUtils for LidoUtils.Context;

    function setUp() external {
        _setUpEnvironment();
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});
    }

    function testFork_ProposalSubmittedInRageQuitNonExecutableInTheNextVetoCooldown() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. THE PROPOSAL IS SUBMITTED");
        {
            proposalId = _submitProposal(
                _dualGovernance, "Propose to doSmth on target passing dual governance", regularStaffCalls
            );

            _assertSubmittedProposalData(proposalId, _timelock.getAdminExecutor(), regularStaffCalls);
            _assertCanSchedule(_dualGovernance, proposalId, false);
        }

        address vetoer = makeAddr("MALICIOUS_ACTOR");
        _setupStETHBalance(
            vetoer, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1_00)
        );
        _step("2. THE SECOND SEAL RAGE QUIT SUPPORT IS ACQUIRED");
        {
            _lockStETH(
                vetoer, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT() + PercentsD16.fromBasisPoints(1)
            );
            _assertVetoSignalingState();

            _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();
        }

        uint256 anotherProposalId;
        _step("3. ANOTHER PROPOSAL IS SUBMITTED DURING THE RAGE QUIT STATE");
        {
            _activateNextState();
            _assertRageQuitState();
            anotherProposalId = _submitProposal(
                _dualGovernance,
                "Another Proposal",
                ExternalCallHelpers.create(
                    address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRugPool, ())
                )
            );
        }

        _step("4. RAGE QUIT IS FINALIZED");
        {
            // request withdrawals batches
            Escrow rageQuitEscrow = _getRageQuitEscrow();

            while (!rageQuitEscrow.isWithdrawalsBatchesClosed()) {
                rageQuitEscrow.requestNextWithdrawalsBatch(96);
            }

            _lido.finalizeWithdrawalQueue();

            while (rageQuitEscrow.getUnclaimedUnstETHIdsCount() > 0) {
                rageQuitEscrow.claimNextWithdrawalsBatch(128);
            }

            rageQuitEscrow.startRageQuitExtensionPeriod();

            _wait(_dualGovernanceConfigProvider.RAGE_QUIT_EXTENSION_PERIOD_DURATION().plusSeconds(1));
            assertTrue(rageQuitEscrow.isRageQuitFinalized());
        }

        _step("5. PROPOSAL SUBMITTED BEFORE RAGE QUIT IS EXECUTABLE");
        {
            _activateNextState();
            _assertVetoCooldownState();

            this.scheduleProposalExternal(proposalId);
            _assertProposalScheduled(proposalId);
        }

        _step("6. PROPOSAL SUBMITTED DURING RAGE QUIT IS NOT EXECUTABLE");
        {
            _activateNextState();
            _assertVetoCooldownState();

            vm.expectRevert(
                abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, anotherProposalId)
            );
            this.scheduleProposalExternal(anotherProposalId);
        }
    }

    function scheduleProposalExternal(uint256 proposalId) external {
        _scheduleProposal(_dualGovernance, proposalId);
    }
}
