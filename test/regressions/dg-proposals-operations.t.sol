// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PercentsD16} from "contracts/types/PercentD16.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {IPotentiallyDangerousContract} from "../utils/interfaces/IPotentiallyDangerousContract.sol";

import {DGRegressionTestSetup, Proposers} from "../utils/integration-tests.sol";

import {ExecutableProposals, ExternalCall, Status} from "contracts/libraries/ExecutableProposals.sol";

import {LidoUtils} from "../utils/lido-utils.sol";

import {CallsScriptBuilder} from "scripts/utils/CallsScriptBuilder.sol";

contract DGProposalOperationsRegressionTest is DGRegressionTestSetup {
    using LidoUtils for LidoUtils.Context;
    using CallsScriptBuilder for CallsScriptBuilder.Context;

    function setUp() external {
        _loadOrDeployDGSetup();
    }

    function testFork_ProposalLifecycle_HappyPath_MultipleCalls() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls(3);

        uint256 proposalId = _submitProposalByAdminProposer(
            regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
        );
        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        _wait(_getAfterSubmitDelay().dividedBy(2));

        // the min execution delay hasn't elapsed yet
        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        this.external__scheduleProposal(proposalId);

        // wait till the first phase of timelock passes
        _wait(_getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(proposalId, true);
        _scheduleProposal(proposalId);
        _assertProposalScheduled(proposalId);

        _wait(_getAfterScheduleDelay());

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
    }

    function testFork_ProposalLifecycle_HappyPath_ExternalCallsWithValue() external {
        uint256 ethValue = 3 ether;

        vm.deal(address(_getAdminExecutor()), ethValue);
        uint256 adminExecutorValueBefore = address(_getAdminExecutor()).balance;

        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
        regularStaffCalls[0].value = uint96(ethValue);

        uint256 proposalId = _submitProposalByAdminProposer(
            regularStaffCalls, "DAO does regular staff on potentially dangerous contract"
        );
        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        _wait(_getAfterSubmitDelay().dividedBy(2));

        // the min execution delay hasn't elapsed yet
        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        this.external__scheduleProposal(proposalId);

        // wait till the first phase of timelock passes
        _wait(_getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(proposalId, true);
        _scheduleProposal(proposalId);
        _assertProposalScheduled(proposalId);

        _wait(_getAfterScheduleDelay());

        uint256 targetMockBalanceBefore = address(_targetMock).balance;

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);

        assertEq(address(_targetMock).balance, targetMockBalanceBefore + ethValue);
        assertEq(adminExecutorValueBefore - ethValue, address(_getAdminExecutor()).balance);
    }

    function testFork_ProposalLifecycle_HappyPath_AgentForwarding() external {
        _grantAragonAgentExecuteRole(_timelock.getAdminExecutor());

        uint256 ethPaymentValue = 1 ether;
        vm.deal(address(_lido.agent), ethPaymentValue);
        uint256 agentBalanceBefore = address(_lido.agent).balance;

        ExternalCall[] memory agentForwardingCalls = new ExternalCall[](2);

        agentForwardingCalls[0].target = address(_lido.agent);
        agentForwardingCalls[0].payload = abi.encodeCall(
            _lido.agent.execute,
            (address(_targetMock), ethPaymentValue, abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (42)))
        );

        agentForwardingCalls[1].target = address(_lido.agent);
        agentForwardingCalls[1].payload = abi.encodeCall(
            _lido.agent.forward,
            (
                CallsScriptBuilder.create(
                    address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doControversialStaff, ())
                ).getResult()
            )
        );

        uint256 proposalId = _submitProposalByAdminProposer(agentForwardingCalls, "Make calls via Agent forwarding");
        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, agentForwardingCalls);

        _wait(_getAfterSubmitDelay().dividedBy(2));

        // the min execution delay hasn't elapsed yet
        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        this.external__scheduleProposal(proposalId);

        // wait till the first phase of timelock passes
        _wait(_getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(proposalId, true);
        _scheduleProposal(proposalId);
        _assertProposalScheduled(proposalId);

        _wait(_getAfterScheduleDelay());

        uint256 targetMockBalanceBefore = address(_targetMock).balance;

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        ExternalCall[] memory expectedTargetMockCalls = new ExternalCall[](2);

        expectedTargetMockCalls[0].value = uint96(ethPaymentValue);
        expectedTargetMockCalls[0].payload = abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (42));

        expectedTargetMockCalls[1].value = 0;
        expectedTargetMockCalls[1].payload = abi.encodeCall(IPotentiallyDangerousContract.doControversialStaff, ());

        _assertTargetMockCalls(address(_lido.agent), expectedTargetMockCalls);
        assertEq(address(_targetMock).balance, targetMockBalanceBefore + ethPaymentValue);
        assertEq(agentBalanceBefore - ethPaymentValue, address(_lido.agent).balance);
    }

    function testFork_AragonVotingAdminProposer_HappyPath() external {
        assertTrue(
            _dgDeployedContracts.dualGovernance.isProposer(address(_lido.voting)), "Aragon Voting is not DG proposer"
        );

        Proposers.Proposer memory votingProposer =
            _dgDeployedContracts.dualGovernance.getProposer(address(_lido.voting));

        assertTrue(_dgDeployedContracts.dualGovernance.isExecutor(votingProposer.executor));

        uint256 proposalId;
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
        _step("1. Aragon Vote may be used to submit proposal");
        {
            uint256 dgProposalsCountBefore = _timelock.getProposalsCount();

            CallsScriptBuilder.Context memory voteWithProposalSubmissionBuilder = CallsScriptBuilder.create(
                address(_dgDeployedContracts.dualGovernance),
                abi.encodeCall(
                    _dgDeployedContracts.dualGovernance.submitProposal,
                    (regularStaffCalls, "Proposal submitted by the DAO")
                )
            );

            uint256 voteId = _lido.adoptVote("Submit DG proposal", voteWithProposalSubmissionBuilder.getResult());
            _lido.executeVote(voteId);

            assertEq(_timelock.getProposalsCount(), dgProposalsCountBefore + 1);

            proposalId = _getLastProposalId();

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStaffCalls);
        }

        _step("2. Proposal may be scheduled and executed");
        {
            // wait till the first phase of timelock passes
            _wait(_getAfterSubmitDelay());

            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);

            _wait(_getAfterScheduleDelay());

            _assertCanExecute(proposalId, true);
            _executeProposal(proposalId);

            _assertTargetMockCalls(votingProposer.executor, regularStaffCalls);
        }
    }

    function testFork_ProposalCancellation_HappyPath() external {
        ExternalCall[] memory regularStuffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId;
        _step("1. DAO submits suspicious proposal");
        {
            proposalId = _submitProposalByAdminProposer(
                regularStuffCalls, "DAO does regular stuff on potentially dangerous contract"
            );
            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, regularStuffCalls);
        }

        address stEthHolders = makeAddr("STETH_WHALE");
        _setupStETHBalance(stEthHolders, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1_00));
        _step("2. StETH holders acquiring quorum to veto proposal");
        {
            _lockStETH(stEthHolders, _getFirstSealRageQuitSupport() + PercentsD16.fromBasisPoints(1));
            _assertVetoSignalingState();
        }

        _step("3. Proposal can't be executed in the veto signalling state");
        {
            _wait(_getAfterSubmitDelay().plusSeconds(1));

            _assertVetoSignalingState();
            vm.expectRevert(abi.encodeWithSelector(DualGovernance.ProposalSchedulingBlocked.selector, proposalId));
            this.external__scheduleProposal(proposalId);

            _assertProposalSubmitted(proposalId);
        }

        _step("4. DAO cancels suspicious proposal");
        {
            bool cancelled = _cancelAllPendingProposalsByProposalsCanceller();
            assertTrue(cancelled);
        }

        _step("5. StETH holders withdraw locked funds, DG is back to normal state, proposal is cancelled");
        {
            _assertVetoSignalingState();
            _wait(_getVetoSignallingMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoSignallingDeactivationState();
            _wait(_getVetoSignallingDeactivationMaxDuration().plusSeconds(1));

            _activateNextState();
            _assertVetoCooldownState();

            vm.startPrank(stEthHolders);
            _getVetoSignallingEscrow().unlockStETH();
            vm.stopPrank();

            _wait(_getVetoCooldownDuration().plusSeconds(1));
            _activateNextState();

            _assertNormalState();
            _assertProposalCancelled(proposalId);

            vm.startPrank(_timelock.getGovernance());
            vm.expectRevert(
                abi.encodeWithSelector(
                    ExecutableProposals.UnexpectedProposalStatus.selector, proposalId, Status.Cancelled
                )
            );
            _timelock.schedule(proposalId);
            vm.stopPrank();
        }
    }
}
