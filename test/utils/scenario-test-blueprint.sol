// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// ---
// Types
// ---

import {PercentD16} from "contracts/types/PercentD16.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {Escrow, VetoerState, LockedAssetsTotals} from "contracts/Escrow.sol";

// ---
// Interfaces
// ---

import {IDualGovernance} from "contracts/interfaces/IDualGovernance.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {WithdrawalRequestStatus} from "contracts/interfaces/IWithdrawalQueue.sol";
import {IPotentiallyDangerousContract} from "./interfaces/IPotentiallyDangerousContract.sol";

// ---
// Main Contracts
// ---

import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {ProposalStatus, EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {IGovernance} from "contracts/TimelockedGovernance.sol";
import {State as DGState, DualGovernanceStateMachine} from "contracts/DualGovernance.sol";

// ---
// Test Utils
// ---

import {TargetMock} from "../utils/target-mock.sol";

import {Random} from "../utils/random.sol";
import {ExternalCallHelpers} from "../utils/executor-calls.sol";

import {LidoUtils, EvmScriptUtils} from "./lido-utils.sol";

import {EvmScriptUtils} from "../utils/evm-script-utils.sol";

import {SetupDeployment} from "./SetupDeployment.sol";
import {TestingAssertEqExtender} from "./testing-assert-eq-extender.sol";

uint256 constant FORK_BLOCK_NUMBER = 20218312;

contract ScenarioTestBlueprint is TestingAssertEqExtender, SetupDeployment {
    using LidoUtils for LidoUtils.Context;

    constructor() SetupDeployment(LidoUtils.mainnet(), Random.create(block.timestamp)) {
        /// Maybe not the best idea to do it in the constructor, consider move it into setUp method
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(FORK_BLOCK_NUMBER);
        _lido.removeStakingLimit();
    }

    // ---
    // Helper Getters
    // ---

    function _getAdminExecutor() internal view returns (address) {
        return _timelock.getAdminExecutor();
    }

    function _getVetoSignallingEscrow() internal view returns (Escrow) {
        return Escrow(payable(_dualGovernance.getVetoSignallingEscrow()));
    }

    function _getRageQuitEscrow() internal view returns (Escrow) {
        address rageQuitEscrow = _dualGovernance.getRageQuitEscrow();
        return Escrow(payable(rageQuitEscrow));
    }

    function _getMockTargetRegularStaffCalls() internal view returns (ExternalCall[] memory) {
        return ExternalCallHelpers.create(
            address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (42))
        );
    }

    function _getVetoSignallingState()
        internal
        view
        returns (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt)
    {
        IDualGovernance.StateDetails memory stateContext = _dualGovernance.getStateDetails();
        isActive = stateContext.state == DGState.VetoSignalling;
        duration = _dualGovernance.getStateDetails().dynamicDelay.toSeconds();
        enteredAt = stateContext.enteredAt.toSeconds();
        activatedAt = stateContext.vetoSignallingActivatedAt.toSeconds();
    }

    function _getVetoSignallingDeactivationState()
        internal
        view
        returns (bool isActive, uint256 duration, uint256 enteredAt)
    {
        IDualGovernance.StateDetails memory stateContext = _dualGovernance.getStateDetails();
        isActive = stateContext.state == DGState.VetoSignallingDeactivation;
        duration = _dualGovernanceConfigProvider.VETO_SIGNALLING_DEACTIVATION_MAX_DURATION().toSeconds();
        enteredAt = stateContext.enteredAt.toSeconds();
    }

    // ---
    // Balances Manipulation
    // ---

    function _setupStETHBalance(address account, uint256 amount) internal {
        _lido.submitStETH(account, amount);
    }

    function _setupStETHBalance(address account, PercentD16 tvlPercentage) internal {
        _lido.submitStETH(account, _lido.calcAmountToDepositFromPercentageOfTVL(tvlPercentage));
    }

    function _setupWstETHBalance(address account, uint256 amount) internal {
        _lido.submitWstETH(account, amount);
    }

    function _setupWstETHBalance(address account, PercentD16 tvlPercentage) internal {
        _lido.submitWstETH(account, _lido.calcSharesToDepositFromPercentageOfTVL(tvlPercentage));
    }

    function _getBalances(address vetoer) internal view returns (Balances memory balances) {
        uint256 stETHAmount = _lido.stETH.balanceOf(vetoer);
        uint256 wstETHShares = _lido.wstETH.balanceOf(vetoer);
        balances = Balances({
            stETHAmount: stETHAmount,
            stETHShares: _lido.stETH.getSharesByPooledEth(stETHAmount),
            wstETHAmount: _lido.stETH.getPooledEthByShares(wstETHShares),
            wstETHShares: wstETHShares
        });
    }

    // ---
    // Withdrawal Queue Operations
    // ---
    function _finalizeWithdrawalQueue() internal {
        _lido.finalizeWithdrawalQueue();
    }

    function _finalizeWithdrawalQueue(uint256 id) internal {
        _lido.finalizeWithdrawalQueue(id);
    }

    function _simulateRebase(PercentD16 rebaseFactor) internal {
        _lido.simulateRebase(rebaseFactor);
    }

    // ---
    // Escrow Manipulation
    // ---
    function _lockStETH(address vetoer, PercentD16 tvlPercentage) internal {
        _lockStETH(vetoer, _lido.calcAmountFromPercentageOfTVL(tvlPercentage));
    }

    function _lockStETH(address vetoer, uint256 amount) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        vm.startPrank(vetoer);
        if (_lido.stETH.allowance(vetoer, address(escrow)) < amount) {
            _lido.stETH.approve(address(escrow), amount);
        }
        escrow.lockStETH(amount);
        vm.stopPrank();
    }

    function _unlockStETH(address vetoer) internal {
        vm.startPrank(vetoer);
        _getVetoSignallingEscrow().unlockStETH();
        vm.stopPrank();
    }

    function _lockWstETH(address vetoer, PercentD16 tvlPercentage) internal {
        _lockStETH(vetoer, _lido.calcSharesFromPercentageOfTVL(tvlPercentage));
    }

    function _lockWstETH(address vetoer, uint256 amount) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        vm.startPrank(vetoer);
        if (_lido.wstETH.allowance(vetoer, address(escrow)) < amount) {
            _lido.wstETH.approve(address(escrow), amount);
        }
        escrow.lockWstETH(amount);
        vm.stopPrank();
    }

    function _unlockWstETH(address vetoer) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        uint256 wstETHBalanceBefore = _lido.wstETH.balanceOf(vetoer);
        VetoerState memory vetoerStateBefore = escrow.getVetoerState(vetoer);

        vm.startPrank(vetoer);
        uint256 wstETHUnlocked = escrow.unlockWstETH();
        vm.stopPrank();

        // 1 wei rounding issue may arise because of the wrapping stETH into wstETH before
        // sending funds to the user
        assertApproxEqAbs(wstETHUnlocked, vetoerStateBefore.stETHLockedShares, 1);
        assertApproxEqAbs(_lido.wstETH.balanceOf(vetoer), wstETHBalanceBefore + vetoerStateBefore.stETHLockedShares, 1);
    }

    function _lockUnstETH(address vetoer, uint256[] memory unstETHIds) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        VetoerState memory vetoerStateBefore = escrow.getVetoerState(vetoer);
        LockedAssetsTotals memory lockedAssetsTotalsBefore = escrow.getLockedAssetsTotals();

        uint256 unstETHTotalSharesLocked = 0;
        WithdrawalRequestStatus[] memory statuses = _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            unstETHTotalSharesLocked += statuses[i].amountOfShares;
        }

        vm.startPrank(vetoer);
        _lido.withdrawalQueue.setApprovalForAll(address(escrow), true);
        escrow.lockUnstETH(unstETHIds);
        _lido.withdrawalQueue.setApprovalForAll(address(escrow), false);
        vm.stopPrank();

        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(_lido.withdrawalQueue.ownerOf(unstETHIds[i]), address(escrow));
        }

        VetoerState memory vetoerStateAfter = escrow.getVetoerState(vetoer);
        assertEq(vetoerStateAfter.unstETHIdsCount, vetoerStateBefore.unstETHIdsCount + unstETHIds.length);

        LockedAssetsTotals memory lockedAssetsTotalsAfter = escrow.getLockedAssetsTotals();
        assertEq(
            lockedAssetsTotalsAfter.unstETHUnfinalizedShares,
            lockedAssetsTotalsBefore.unstETHUnfinalizedShares + unstETHTotalSharesLocked
        );
    }

    function _unlockUnstETH(address vetoer, uint256[] memory unstETHIds) internal {
        Escrow escrow = _getVetoSignallingEscrow();
        VetoerState memory vetoerStateBefore = escrow.getVetoerState(vetoer);
        LockedAssetsTotals memory lockedAssetsTotalsBefore = escrow.getLockedAssetsTotals();

        uint256 unstETHTotalSharesUnlocked = 0;
        WithdrawalRequestStatus[] memory statuses = _lido.withdrawalQueue.getWithdrawalStatus(unstETHIds);
        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            unstETHTotalSharesUnlocked += statuses[i].amountOfShares;
        }

        vm.startPrank(vetoer);
        escrow.unlockUnstETH(unstETHIds);
        vm.stopPrank();

        for (uint256 i = 0; i < unstETHIds.length; ++i) {
            assertEq(_lido.withdrawalQueue.ownerOf(unstETHIds[i]), vetoer);
        }

        VetoerState memory vetoerStateAfter = escrow.getVetoerState(vetoer);
        assertEq(vetoerStateAfter.unstETHIdsCount, vetoerStateBefore.unstETHIdsCount - unstETHIds.length);

        // TODO: implement correct assert. It must consider was unstETH finalized or not
        LockedAssetsTotals memory lockedAssetsTotalsAfter = escrow.getLockedAssetsTotals();
        assertEq(
            lockedAssetsTotalsAfter.unstETHUnfinalizedShares,
            lockedAssetsTotalsBefore.unstETHUnfinalizedShares - unstETHTotalSharesUnlocked
        );
    }

    // ---
    // Dual Governance State Manipulation
    // ---
    function _activateNextState() internal {
        _dualGovernance.activateNextState();
    }

    // ---
    // Proposals Submission
    // ---
    function _submitProposalViaDualGovernance(
        string memory description,
        ExternalCall[] memory calls
    ) internal returns (uint256 proposalId) {
        proposalId = _submitProposal(_dualGovernance, description, calls);
    }

    function _submitProposalViaTimelockedGovernance(
        string memory description,
        ExternalCall[] memory calls
    ) internal returns (uint256 proposalId) {
        proposalId = _submitProposal(_timelockedGovernance, description, calls);
    }

    function _submitProposal(
        IGovernance governance,
        string memory description,
        ExternalCall[] memory calls
    ) internal returns (uint256 proposalId) {
        uint256 proposalsCountBefore = _timelock.getProposalsCount();

        bytes memory script =
            EvmScriptUtils.encodeEvmCallScript(address(governance), abi.encodeCall(IGovernance.submitProposal, (calls)));
        uint256 voteId = _lido.adoptVote(description, script);

        // The scheduled calls count is the same until the vote is enacted
        assertEq(_timelock.getProposalsCount(), proposalsCountBefore);

        // executing the vote
        _lido.executeVote(voteId);

        proposalId = _timelock.getProposalsCount();
        // new call is scheduled but has not executable yet
        assertEq(proposalId, proposalsCountBefore + 1);
    }

    function _scheduleProposalViaDualGovernance(uint256 proposalId) internal {
        _scheduleProposal(_dualGovernance, proposalId);
    }

    function _scheduleProposalViaTimelockedGovernance(uint256 proposalId) internal {
        _scheduleProposal(_timelockedGovernance, proposalId);
    }

    function _scheduleProposal(IGovernance governance, uint256 proposalId) internal {
        governance.scheduleProposal(proposalId);
    }

    function _executeProposal(uint256 proposalId) internal {
        _timelock.execute(proposalId);
    }

    function _scheduleAndExecuteProposal(IGovernance governance, uint256 proposalId) internal {
        _scheduleProposal(governance, proposalId);
        _executeProposal(proposalId);
    }

    // ---
    // Assertions
    // ---

    function _assertSubmittedProposalData(uint256 proposalId, ExternalCall[] memory calls) internal {
        _assertSubmittedProposalData(proposalId, _timelock.getAdminExecutor(), calls);
    }

    function _assertSubmittedProposalData(uint256 proposalId, address executor, ExternalCall[] memory calls) internal {
        (ITimelock.ProposalDetails memory proposal, ExternalCall[] memory calls) = _timelock.getProposal(proposalId);
        assertEq(proposal.id, proposalId, "unexpected proposal id");
        assertEq(proposal.status, ProposalStatus.Submitted, "unexpected status value");
        assertEq(proposal.executor, executor, "unexpected executor");
        assertEq(Timestamp.unwrap(proposal.submittedAt), block.timestamp, "unexpected scheduledAt");
        assertEq(calls.length, calls.length, "unexpected calls length");

        for (uint256 i = 0; i < calls.length; ++i) {
            ExternalCall memory expected = calls[i];
            ExternalCall memory actual = calls[i];

            assertEq(actual.value, expected.value);
            assertEq(actual.target, expected.target);
            assertEq(actual.payload, expected.payload);
        }
    }

    function _assertTargetMockCalls(address sender, ExternalCall[] memory calls) internal {
        TargetMock.Call[] memory called = _targetMock.getCalls();
        assertEq(called.length, calls.length);

        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(called[i].sender, sender);
            assertEq(called[i].value, calls[i].value);
            assertEq(called[i].data, calls[i].payload);
            assertEq(called[i].blockNumber, block.number);
        }
        _targetMock.reset();
    }

    function _assertTargetMockCalls(address[] memory senders, ExternalCall[] memory calls) internal {
        TargetMock.Call[] memory called = _targetMock.getCalls();
        assertEq(called.length, calls.length);
        assertEq(called.length, senders.length);

        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(called[i].sender, senders[i], "Unexpected sender");
            assertEq(called[i].value, calls[i].value, "Unexpected value");
            assertEq(called[i].data, calls[i].payload, "Unexpected payload");
            assertEq(called[i].blockNumber, block.number);
        }
        _targetMock.reset();
    }

    function _assertCanExecute(uint256 proposalId, bool canExecute) internal {
        assertEq(_timelock.canExecute(proposalId), canExecute, "unexpected canExecute() value");
    }

    function _assertCanScheduleViaDualGovernance(uint256 proposalId, bool canSchedule) internal {
        _assertCanSchedule(_dualGovernance, proposalId, canSchedule);
    }

    function _assertCanScheduleViaTimelockedGovernance(uint256 proposalId, bool canSchedule) internal {
        _assertCanSchedule(_timelockedGovernance, proposalId, canSchedule);
    }

    function _assertCanSchedule(IGovernance governance, uint256 proposalId, bool canSchedule) internal {
        assertEq(governance.canScheduleProposal(proposalId), canSchedule, "unexpected canSchedule() value");
    }

    function _assertCanScheduleAndExecute(IGovernance governance, uint256 proposalId) internal {
        _assertCanSchedule(governance, proposalId, true);
        assertFalse(
            _timelock.isEmergencyProtectionEnabled(),
            "Execution in the same block with scheduling allowed only when emergency protection is disabled"
        );
    }

    function _assertProposalSubmitted(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Submitted,
            "TimelockProposal not in 'Submitted' state"
        );
    }

    function _assertProposalScheduled(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Scheduled,
            "TimelockProposal not in 'Scheduled' state"
        );
    }

    function _assertProposalExecuted(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Executed,
            "TimelockProposal not in 'Executed' state"
        );
    }

    function _assertProposalCancelled(uint256 proposalId) internal {
        assertEq(
            _timelock.getProposalDetails(proposalId).status,
            ProposalStatus.Cancelled,
            "Proposal not in 'Canceled' state"
        );
    }

    function _assertNormalState() internal {
        assertEq(_dualGovernance.getState(), DGState.Normal);
    }

    function _assertVetoSignalingState() internal {
        assertEq(_dualGovernance.getState(), DGState.VetoSignalling);
    }

    function _assertVetoSignalingDeactivationState() internal {
        assertEq(_dualGovernance.getState(), DGState.VetoSignallingDeactivation);
    }

    function _assertRageQuitState() internal {
        assertEq(_dualGovernance.getState(), DGState.RageQuit);
    }

    function _assertVetoCooldownState() internal {
        assertEq(_dualGovernance.getState(), DGState.VetoCooldown);
    }

    function _assertNoTargetMockCalls() internal {
        assertEq(_targetMock.getCalls().length, 0, "Unexpected target calls count");
    }

    // ---
    // Logging and Debugging
    // ---
    function _logVetoSignallingState() internal view {
        /* solhint-disable no-console */
        (bool isActive, uint256 duration, uint256 activatedAt, uint256 enteredAt) = _getVetoSignallingState();

        if (!isActive) {
            console.log("VetoSignalling state is not active\n");
            return;
        }

        console.log("Veto signalling duration is %d seconds (%s)", duration, _formatDuration(_toDuration(duration)));
        console.log("Veto signalling entered at %d (activated at %d)", enteredAt, activatedAt);
        if (block.timestamp > activatedAt + duration) {
            console.log(
                "Veto signalling has ended %s ago\n",
                _formatDuration(_toDuration(block.timestamp - activatedAt - duration))
            );
        } else {
            console.log(
                "Veto signalling will end after %s\n",
                _formatDuration(_toDuration(activatedAt + duration - block.timestamp))
            );
        }
        /* solhint-enable no-console */
    }

    function _logVetoSignallingDeactivationState() internal view {
        /* solhint-disable no-console */
        (bool isActive, uint256 duration, uint256 enteredAt) = _getVetoSignallingDeactivationState();

        if (!isActive) {
            console.log("VetoSignallingDeactivation state is not active\n");
            return;
        }

        console.log(
            "VetoSignallingDeactivation duration is %d seconds (%s)", duration, _formatDuration(_toDuration(duration))
        );
        console.log("VetoSignallingDeactivation entered at %d", enteredAt);
        if (block.timestamp > enteredAt + duration) {
            console.log(
                "VetoSignallingDeactivation has ended %s ago\n",
                _formatDuration(_toDuration(block.timestamp - enteredAt - duration))
            );
        } else {
            console.log(
                "VetoSignallingDeactivation will end after %s\n",
                _formatDuration(_toDuration(enteredAt + duration - block.timestamp))
            );
        }
        /* solhint-enable no-console */
    }

    // ---
    // Utils Methods
    // ---

    function _step(string memory text) internal view {
        // solhint-disable-next-line
        console.log(string.concat(">>> ", text, " <<<"));
    }

    function _wait(Duration duration) internal {
        vm.warp(duration.addTo(Timestamps.now()).toSeconds());
    }

    function _waitAfterSubmitDelayPassed() internal {
        _wait(_timelock.getAfterSubmitDelay() + Durations.from(1 seconds));
    }

    function _waitAfterScheduleDelayPassed() internal {
        _wait(_timelock.getAfterScheduleDelay() + Durations.from(1 seconds));
    }

    function _executeActivateEmergencyMode() internal {
        address[] memory members = _emergencyActivationCommittee.getMembers();
        for (uint256 i = 0; i < _emergencyActivationCommittee.quorum(); ++i) {
            vm.prank(members[i]);
            _emergencyActivationCommittee.approveActivateEmergencyMode();
        }
        _emergencyActivationCommittee.executeActivateEmergencyMode();
    }

    function _executeEmergencyExecute(uint256 proposalId) internal {
        address[] memory members = _emergencyExecutionCommittee.getMembers();
        for (uint256 i = 0; i < _emergencyExecutionCommittee.quorum(); ++i) {
            vm.prank(members[i]);
            _emergencyExecutionCommittee.voteEmergencyExecute(proposalId, true);
        }
        _emergencyExecutionCommittee.executeEmergencyExecute(proposalId);
    }

    function _executeEmergencyReset() internal {
        address[] memory members = _emergencyExecutionCommittee.getMembers();
        for (uint256 i = 0; i < _emergencyExecutionCommittee.quorum(); ++i) {
            vm.prank(members[i]);
            _emergencyExecutionCommittee.approveEmergencyReset();
        }
        _emergencyExecutionCommittee.executeEmergencyReset();
    }

    struct DurationStruct {
        uint256 _days;
        uint256 _hours;
        uint256 _minutes;
        uint256 _seconds;
    }

    function _toDuration(uint256 timestamp) internal pure returns (DurationStruct memory duration) {
        duration._days = timestamp / 1 days;
        duration._hours = (timestamp - 1 days * duration._days) / 1 hours;
        duration._minutes = (timestamp - 1 days * duration._days - 1 hours * duration._hours) / 1 minutes;
        duration._seconds = timestamp % 1 minutes;
    }

    function _formatDuration(DurationStruct memory duration) internal pure returns (string memory) {
        // format example: 1d:22h:33m:12s
        return string(
            abi.encodePacked(
                Strings.toString(duration._days),
                "d:",
                Strings.toString(duration._hours),
                "h:",
                Strings.toString(duration._minutes),
                "m:",
                Strings.toString(duration._seconds),
                "s"
            )
        );
    }
}
