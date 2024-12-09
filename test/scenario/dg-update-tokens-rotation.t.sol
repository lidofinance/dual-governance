// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations} from "contracts/types/Duration.sol";
import {PercentsD16} from "contracts/types/PercentD16.sol";

import {TimelockState} from "contracts/libraries/TimelockState.sol";
import {ExecutableProposals, Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";

import {Escrow} from "contracts/Escrow.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";

import {ScenarioTestBlueprint, ExternalCall, ExternalCallHelpers} from "../utils/scenario-test-blueprint.sol";

contract DualGovernanceUpdateTokensRotation is ScenarioTestBlueprint {
    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});
        _setupStETHBalance(_VETOER, PercentsD16.fromBasisPoints(30_00));
    }

    function testFork_DualGovernanceUpdate_OldEscrowInstanceAllowsUnlockTokens() external {
        DualGovernance newDualGovernanceInstance;
        _step("1. Deploy new Dual Governance implementation");
        {
            newDualGovernanceInstance = _deployDualGovernance({
                timelock: _timelock,
                resealManager: _resealManager,
                configProvider: _dualGovernanceConfigProvider
            });
        }

        uint256 updateDualGovernanceProposalId;
        _step("2. Submit proposal to update the Dual Governance implementation");
        {
            updateDualGovernanceProposalId = _submitProposalViaDualGovernance(
                "Update the Dual Governance implementation",
                _getActionsToUpdateDualGovernanceImplementation(address(newDualGovernanceInstance))
            );
        }

        _step("3. Users accumulate some stETH in the Signalling Escrow");
        {
            _lockStETH(_VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT() - PercentsD16.from(1));
            _assertVetoSignalingState();
            _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));

            _activateNextState();
            _assertVetoSignalingDeactivationState();
            _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));

            _activateNextState();
            _assertVetoCooldownState();
        }

        _step("4. When the VetoCooldown is entered proposal to update becomes executable");
        {
            _scheduleProposalViaDualGovernance(updateDualGovernanceProposalId);
            _assertProposalScheduled(updateDualGovernanceProposalId);

            _waitAfterScheduleDelayPassed();
            _executeProposal(updateDualGovernanceProposalId);

            assertEq(_timelock.getGovernance(), address(newDualGovernanceInstance));
        }

        _step("5. The old instance of the Dual Governance can't submit proposals anymore");
        {
            // wait until the VetoCooldown ends in the old dual governance instance
            _wait(_dualGovernanceConfigProvider.VETO_COOLDOWN_DURATION().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();

            // old instance of the Dual Governance can't submit proposals anymore
            vm.expectRevert(
                abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, address(_dualGovernance))
            );
            vm.prank(address(_lido.voting));
            _dualGovernance.submitProposal(_getMockTargetRegularStaffCalls(), "empty metadata");
        }

        _step("6. Users can unlock stETH from the old Signalling Escrow");
        {
            _unlockStETH(_VETOER);
        }

        _step("7. Users can withdraw funds even if the Rage Quit is started in the old instance of the Dual Governance");
        {
            // the Rage Quit started on the old DualGovernance instance
            _lockStETH(_VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT());
            _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();

            // The Rage Quit may be finished in the previous DG instance so vetoers will not lose their funds by mistake
            Escrow rageQuitEscrow = Escrow(payable(_dualGovernance.getRageQuitEscrow()));

            while (!rageQuitEscrow.isWithdrawalsBatchesClosed()) {
                rageQuitEscrow.requestNextWithdrawalsBatch(96);
            }

            _finalizeWithdrawalQueue();

            while (rageQuitEscrow.getUnclaimedUnstETHIdsCount() > 0) {
                rageQuitEscrow.claimNextWithdrawalsBatch(32);
            }

            rageQuitEscrow.startRageQuitExtensionPeriod();

            _wait(_dualGovernanceConfigProvider.RAGE_QUIT_EXTENSION_PERIOD_DURATION().plusSeconds(1));
            assertEq(rageQuitEscrow.isRageQuitFinalized(), true);

            // TODO: Add method Escrow.getRageQuitExtensionPeriodDuration()
            _wait(_dualGovernanceConfigProvider.RAGE_QUIT_ETH_WITHDRAWALS_MAX_DELAY());

            uint256 vetoerETHBalanceBefore = _VETOER.balance;

            vm.prank(_VETOER);
            rageQuitEscrow.withdrawETH();

            assertTrue(_VETOER.balance > vetoerETHBalanceBefore);
        }
    }

    function testFork_DualGovernanceUpdate_LastMomentProposalAttack() external {
        // DAO initiates the update of the Dual Governance
        // Malicious actor locks funds in the Signalling Escrow to waste the full duration of VetoSignalling
        // At the end of the VetoSignalling, malicious actor unlocks all funds from VetoSignalling and
        //  submits proposal to steal the control over governance
        //
        DualGovernance newDualGovernanceInstance;
        _step("1. Deploy new Dual Governance implementation");
        {
            newDualGovernanceInstance = _deployDualGovernance({
                timelock: _timelock,
                resealManager: _resealManager,
                configProvider: _dualGovernanceConfigProvider
            });
        }

        uint256 updateDualGovernanceProposalId;
        _step("2. DAO submits proposal to update the Dual Governance implementation");
        {
            updateDualGovernanceProposalId = _submitProposalViaDualGovernance(
                "Update the Dual Governance implementation",
                _getActionsToUpdateDualGovernanceImplementation(address(newDualGovernanceInstance))
            );
        }

        _step("3. Malicious actor accumulate second seal in the Signalling Escrow");
        {
            _lockStETH(_VETOER, _dualGovernanceConfigProvider.SECOND_SEAL_RAGE_QUIT_SUPPORT());
            _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_MAX_DURATION().minusSeconds(_lido.voting.voteTime()));
            _assertVetoSignalingState();
        }

        uint256 maliciousProposalId;
        _step("4. Malicious actor unlock funds from Signalling Escrow");
        {
            maliciousProposalId = _submitProposalViaDualGovernance(
                "Steal control over timelock contract",
                ExternalCallHelpers.create({
                    target: address(_timelock),
                    payload: abi.encodeCall(_timelock.setGovernance, (_VETOER))
                })
            );
            _unlockStETH(_VETOER);
            _assertVetoSignalingDeactivationState();
        }

        _step("5. Regular can't collect second seal in VETO_SIGNALLING_DEACTIVATION_MAX_DURATION");
        {
            _wait(_dualGovernanceConfigProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().plusSeconds(1));
            _activateNextState();
            _assertVetoCooldownState();
        }

        _step("6. The Dual Governance implementation is updated on the new version");
        {
            // Malicious proposal can't be executed directly on the old DualGovernance instance, as it was submitted
            // during the VetoSignalling phase
            vm.expectRevert(
                abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, maliciousProposalId)
            );
            _scheduleProposalViaDualGovernance(maliciousProposalId);

            _scheduleProposalViaDualGovernance(updateDualGovernanceProposalId);
            _assertProposalScheduled(updateDualGovernanceProposalId);

            _waitAfterScheduleDelayPassed();
            _executeProposal(updateDualGovernanceProposalId);

            assertEq(_timelock.getGovernance(), address(newDualGovernanceInstance));
        }

        _step("7. After the update malicious proposal is cancelled and can't be executed via new DualGovernance");
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ExecutableProposals.UnexpectedProposalStatus.selector, maliciousProposalId, ProposalStatus.Cancelled
                )
            );
            newDualGovernanceInstance.scheduleProposal(maliciousProposalId);

            assertEq(_timelock.getProposalDetails(maliciousProposalId).status, ProposalStatus.Cancelled);
        }
    }

    // ---
    // Helper methods
    // ---
    function _getActionsToUpdateDualGovernanceImplementation(address newDualGovernanceInstance)
        internal
        returns (ExternalCall[] memory)
    {
        return ExternalCallHelpers.create(
            [
                // register Aragon Voting as proposer
                ExternalCall({
                    value: 0,
                    target: address(newDualGovernanceInstance),
                    payload: abi.encodeCall(
                        DualGovernance.registerProposer, (address(_lido.voting), _timelock.getAdminExecutor())
                    )
                }),
                ExternalCall({
                    value: 0,
                    target: address(_timelock),
                    payload: abi.encodeCall(_timelock.setGovernance, (address(newDualGovernanceInstance)))
                })
                // NOTE: There should be additional calls with the proper setting up of the new DG implementation
            ]
        );
    }
}
