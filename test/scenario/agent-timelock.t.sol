// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ExternalCall, ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";

import {DGScenarioTestSetup, Proposers} from "../utils/integration-tests.sol";

interface IRegularContract {
    function regularMethod() external;
}

contract AragonAgentAsExecutorScenarioTest is DGScenarioTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    function setUp() external {
        _deployDGSetup({isEmergencyProtectionEnabled: true});
    }

    function testFork_AragonAgentAsExecutor_HappyPath() external {
        _step("1. Grant EXECUTE_ROLE permission to the timelock on the Agent contract");
        {
            _grantAragonAgentExecuteRole(address(_timelock));
        }

        address agentProposer = makeAddr("AGENT_PROPOSER");
        _step("2. Submit proposal to register Aragon Agent as the executor");
        {
            _addAragonAgentProposer(agentProposer);
        }

        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
        _step("3. Adopt the proposal with the actions executed by the Aragon Agent executor");
        {
            _adoptProposal(agentProposer, regularStaffCalls, "Make regular staff using Agent as executor");
        }

        _step("4. Validate action was executed by the Agent");
        {
            _assertTargetMockCalls({caller: address(_lido.agent), calls: regularStaffCalls});
        }
    }

    function testFork_AragonAgentAsExecutor_RevertOn_FailedCall() external {
        _step("1. Grant EXECUTE_ROLE permission to the timelock on the Agent contract");
        {
            _grantAragonAgentExecuteRole(address(_timelock));
        }

        address agentProposer = makeAddr("AGENT_PROPOSER");
        _step("2. Submit proposal to register Aragon as the executor");
        {
            _addAragonAgentProposer(agentProposer);
        }

        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
        vm.mockCallRevert(regularStaffCalls[0].target, regularStaffCalls[0].payload, "INVALID TARGET");

        uint256 agentActionsProposalId;
        _step("3. Submit proposal which should revert via the Agent proposer");
        {
            vm.prank(agentProposer);
            agentActionsProposalId =
                _submitProposal(agentProposer, regularStaffCalls, "Make regular staff using Agent as executor");

            _assertSubmittedProposalData(agentActionsProposalId, address(_lido.agent), regularStaffCalls);
        }

        _step("4. The execution of the proposal fails");
        {
            _assertProposalSubmitted(agentActionsProposalId);
            _wait(_getAfterSubmitDelay());

            _scheduleProposal(agentActionsProposalId);
            _assertProposalScheduled(agentActionsProposalId);

            _wait(_getAfterScheduleDelay());

            vm.expectRevert("INVALID TARGET");
            _executeProposal(agentActionsProposalId);

            _assertNoTargetMockCalls();
        }
    }

    function testFork_AgentAsExecutor_SucceedOnEmptyAccountCalls() external {
        _step("1. Grant EXECUTE_ROLE permission to the timelock on the Agent contract");
        {
            _grantAragonAgentExecuteRole(address(_timelock));
        }

        address agentProposer = makeAddr("AGENT_PROPOSER");
        _step("2. Submit proposal to register Aragon as the executor");
        {
            _addAragonAgentProposer(agentProposer);
        }

        uint256 callValue = 1 ether;
        address nonContractAccount = makeAddr("NOT_CONTRACT");
        ExternalCallsBuilder.Context memory callsToEmptyAccountBuilder = ExternalCallsBuilder.create({callsCount: 3});

        callsToEmptyAccountBuilder.addCall(nonContractAccount, new bytes(0));
        callsToEmptyAccountBuilder.addCall(nonContractAccount, abi.encodeCall(IRegularContract.regularMethod, ()));
        callsToEmptyAccountBuilder.addCallWithValue({
            value: uint96(callValue),
            target: nonContractAccount,
            payload: new bytes(0)
        });

        uint256 agentBalanceBefore = address(_lido.agent).balance;
        vm.deal(address(_lido.agent), agentBalanceBefore + callValue);

        _step("3. Adopt proposal via the Agent proposer with calls to EOA account");
        {
            _adoptProposal(agentProposer, callsToEmptyAccountBuilder.getResult(), "Make different calls to EOA account");
        }

        _step("4. When the calls is done by Agent, it's not failed and executed successfully");
        {
            assertEq(nonContractAccount.balance, 1 ether);
            assertEq(address(_lido.agent).balance, agentBalanceBefore);
        }
    }

    // ---
    // Helper Methods
    // ---

    function _addAragonAgentProposer(address agentProposer) internal {
        ExternalCallsBuilder.Context memory callsBuilder = ExternalCallsBuilder.create({callsCount: 1});

        callsBuilder.addCall(
            address(_dgDeployedContracts.dualGovernance),
            abi.encodeCall(_dgDeployedContracts.dualGovernance.registerProposer, (agentProposer, address(_lido.agent)))
        );

        uint256 proposersCountBefore = _getProposers().length;

        _adoptProposalByAdminProposer(callsBuilder.getResult(), "Add Aragon Agent as proposer to the Dual Governance");

        Proposers.Proposer[] memory proposers = _getProposers();

        assertEq(proposers.length, proposersCountBefore + 1);
        assertEq(proposers[1].account, agentProposer);
        assertEq(proposers[1].executor, address(_lido.agent));
    }
}
