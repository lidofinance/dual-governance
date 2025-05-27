// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PercentsD16} from "contracts/types/PercentD16.sol";

import {TimelockState} from "contracts/libraries/TimelockState.sol";
import {ExecutableProposals, Status as ProposalStatus} from "contracts/libraries/ExecutableProposals.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";

import {IRageQuitEscrow, ContractsDeployment, DGRegressionTestSetup} from "../utils/integration-tests.sol";

import {ExternalCallsBuilder, ExternalCall} from "scripts/utils/ExternalCallsBuilder.sol";

contract DualGovernanceUpgradeScenariosRegressionTest is DGRegressionTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    address internal immutable _VETOER = makeAddr("VETOER");

    function setUp() external {
        _loadOrDeployDGSetup();
        _setupStETHBalance(_VETOER, PercentsD16.fromBasisPoints(30_00));
    }

    function testFork_OldEscrowInstanceAllowsUnlockTokens_HappyPath() external {
        DualGovernance newDualGovernanceInstance;
        _step("1. Deploy new Dual Governance implementation");
        {
            newDualGovernanceInstance = ContractsDeployment.deployDualGovernance(
                DualGovernance.DualGovernanceComponents({
                    timelock: _timelock,
                    resealManager: _dgDeployedContracts.resealManager,
                    configProvider: _dgDeployedContracts.dualGovernanceConfigProvider
                }),
                _dgDeployConfig.dualGovernance.signallingTokens,
                _dgDeployConfig.dualGovernance.sanityCheckParams
            );
        }

        uint256 updateDualGovernanceProposalId;
        _step("2. Submit proposal to update the Dual Governance implementation");
        {
            updateDualGovernanceProposalId = _submitProposalByAdminProposer(
                _getActionsToUpdateDualGovernanceImplementation(address(newDualGovernanceInstance)),
                "Update the Dual Governance implementation"
            );
        }

        _step("3. Users accumulate some stETH in the Signalling Escrow");
        {
            _lockStETH(_VETOER, _getSecondSealRageQuitSupport() - PercentsD16.from(1));
            _assertVetoSignalingState();
            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoSignallingDeactivationState();
            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoCooldownState();
        }

        _step("4. When the VetoCooldown is entered proposal to update becomes executable");
        {
            _scheduleProposal(updateDualGovernanceProposalId);
            _assertProposalScheduled(updateDualGovernanceProposalId);

            _wait(_getAfterScheduleDelay());
            _executeProposal(updateDualGovernanceProposalId);

            assertEq(_timelock.getGovernance(), address(newDualGovernanceInstance));
        }

        _step("5. The old instance of the Dual Governance can't submit proposals anymore");
        {
            // wait until the VetoCooldown ends in the old dual governance instance
            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();
            _assertVetoSignalingState();

            // old instance of the Dual Governance can't submit proposals anymore
            vm.expectRevert(
                abi.encodeWithSelector(
                    TimelockState.CallerIsNotGovernance.selector, address(_dgDeployedContracts.dualGovernance)
                )
            );
            vm.prank(address(_lido.voting));
            _dgDeployedContracts.dualGovernance.submitProposal(_getMockTargetRegularStaffCalls(), "Regular actions");
        }

        _step("6. Users can unlock stETH from the old Signalling Escrow");
        {
            _unlockStETH(_VETOER);
        }

        _step("7. Users can withdraw funds even if the Rage Quit is started in the old instance of the Dual Governance");
        {
            // the Rage Quit started on the old DualGovernance instance
            _lockStETH(_VETOER, _getSecondSealRageQuitSupport());
            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));
            _activateNextState();
            _assertRageQuitState();

            // The Rage Quit may be finished in the previous DG instance so vetoers will not lose their funds by mistake
            IRageQuitEscrow rageQuitEscrow = _getRageQuitEscrow();

            while (!rageQuitEscrow.isWithdrawalsBatchesClosed()) {
                rageQuitEscrow.requestNextWithdrawalsBatch(96);
            }

            _finalizeWithdrawalQueue();

            while (rageQuitEscrow.getUnclaimedUnstETHIdsCount() > 0) {
                rageQuitEscrow.claimNextWithdrawalsBatch(32);
            }

            rageQuitEscrow.startRageQuitExtensionPeriod();

            _wait(_getRageQuitExtensionPeriodDuration().plusSeconds(1));
            assertEq(rageQuitEscrow.isRageQuitFinalized(), true);

            // TODO: Add method Escrow.getRageQuitExtensionPeriodDuration()
            _wait(_getRageQuitEthWithdrawalsDelay());

            uint256 vetoerETHBalanceBefore = _VETOER.balance;

            vm.prank(_VETOER);
            rageQuitEscrow.withdrawETH();

            assertTrue(_VETOER.balance > vetoerETHBalanceBefore);
        }
    }

    function testFork_ProposalExecution_RevertOn_SubmittedViaOldGovernance() external {
        // DAO initiates the update of the Dual Governance
        // Malicious actor locks funds in the Signalling Escrow to waste the full duration of VetoSignalling
        // At the end of the VetoSignalling, malicious actor unlocks all funds from VetoSignalling and
        //  submits proposal to steal the control over governance
        //
        DualGovernance newDualGovernanceInstance;
        _step("1. Deploy new Dual Governance implementation");
        {
            newDualGovernanceInstance = ContractsDeployment.deployDualGovernance(
                DualGovernance.DualGovernanceComponents({
                    timelock: _timelock,
                    resealManager: _dgDeployedContracts.resealManager,
                    configProvider: _dgDeployedContracts.dualGovernanceConfigProvider
                }),
                _dgDeployConfig.dualGovernance.signallingTokens,
                _dgDeployConfig.dualGovernance.sanityCheckParams
            );
        }

        uint256 updateDualGovernanceProposalId;
        _step("2. DAO submits proposal to update the Dual Governance implementation");
        {
            updateDualGovernanceProposalId = _submitProposalByAdminProposer(
                _getActionsToUpdateDualGovernanceImplementation(address(newDualGovernanceInstance)),
                "Update the Dual Governance implementation"
            );
        }

        _step("3. Malicious actor accumulate second seal in the Signalling Escrow");
        {
            _lockStETH(_VETOER, _getSecondSealRageQuitSupport());
            _wait(_getVetoSignallingMaxDuration().minusSeconds(_lido.voting.voteTime()));
            _assertVetoSignalingState();
        }

        uint256 maliciousProposalId;
        _step("4. Malicious actor unlock funds from Signalling Escrow");
        {
            ExternalCall[] memory maliciousCalls = new ExternalCall[](1);
            maliciousCalls[0].target = address(_timelock);
            maliciousCalls[0].payload = abi.encodeCall(_timelock.setGovernance, (_VETOER));

            maliciousProposalId = _submitProposalByAdminProposer(maliciousCalls, "Steal control over timelock contract");

            _unlockStETH(_VETOER);
            _assertVetoSignallingDeactivationState();
        }

        _step("5. Regular can't collect second seal in VETO_SIGNALLING_DEACTIVATION_MAX_DURATION");
        {
            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));
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
            _dgDeployedContracts.dualGovernance.scheduleProposal(maliciousProposalId);

            _scheduleProposal(updateDualGovernanceProposalId);
            _assertProposalScheduled(updateDualGovernanceProposalId);

            _wait(_getAfterScheduleDelay());
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
        view
        returns (ExternalCall[] memory)
    {
        ExternalCallsBuilder.Context memory callsBuilder = ExternalCallsBuilder.create({callsCount: 2});

        callsBuilder.addCall(
            address(newDualGovernanceInstance),
            abi.encodeCall(DualGovernance.registerProposer, (address(_lido.voting), _timelock.getAdminExecutor()))
        );

        callsBuilder.addCall(
            address(_timelock), abi.encodeCall(_timelock.setGovernance, (address(newDualGovernanceInstance)))
        );

        return callsBuilder.getResult();
    }

    function external__submitProposalByAdminProposer(ExternalCall[] memory calls)
        external
        returns (uint256 proposalId)
    {
        proposalId = _submitProposalByAdminProposer(calls);
    }
}
