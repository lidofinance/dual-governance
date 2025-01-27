// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EvmScriptUtils} from "../utils/evm-script-utils.sol";
import {IPotentiallyDangerousContract} from "../utils/interfaces/IPotentiallyDangerousContract.sol";

import {ExternalCall, ExternalCallHelpers} from "../utils/executor-calls.sol";
import {DGRegressionTestSetup} from "../utils/integration-tests.sol";

import {ExecutableProposals} from "contracts/libraries/ExecutableProposals.sol";

import {LidoUtils, EvmScriptUtils} from "../utils/lido-utils.sol";

contract DGProposalOperationsTest is DGRegressionTestSetup {
    using LidoUtils for LidoUtils.Context;

    function setUp() external {
        _loadOrDeployDGSetup();
    }

    function testFork_ProposalLifecycle_HappyPathMultipleCalls() external {
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

    function testFork_ProposalLifecycle_ExternalCallsWithValue() external {
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

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);

        assertEq(address(_targetMock).balance, ethValue);
        assertEq(adminExecutorValueBefore - ethValue, address(_getAdminExecutor()).balance);
    }

    function testFork_ProposalLifecycle_AgentForwarding() external {
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
                EvmScriptUtils.encodeEvmCallScript(
                    address(_targetMock), abi.encodeCall(IPotentiallyDangerousContract.doControversialStaff, ())
                )
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

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        ExternalCall[] memory expectedTargetMockCalls = new ExternalCall[](2);

        expectedTargetMockCalls[0].value = uint96(ethPaymentValue);
        expectedTargetMockCalls[0].payload = abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (42));

        expectedTargetMockCalls[1].value = 0;
        expectedTargetMockCalls[1].payload = abi.encodeCall(IPotentiallyDangerousContract.doControversialStaff, ());

        _assertTargetMockCalls(address(_lido.agent), expectedTargetMockCalls);
        assertEq(address(_targetMock).balance, ethPaymentValue);
        assertEq(agentBalanceBefore - ethPaymentValue, address(_lido.agent).balance);
    }

    function testFork_ProposalLifecycle_ProposalCancellation() external {
        vm.skip(true);
    }
}
