// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import {Proposers} from "contracts/libraries/Proposers.sol";

import {DGScenarioTestSetup, ExternalCallHelpers, ExternalCall, Proposers} from "../utils/integration-tests.sol";
// import {LidoUtils} from "../utils/lido-utils.sol";

interface IRegularContract {
    function regularMethod() external;
}

contract AragonAgentAsExecutorScenarioTest is DGScenarioTestSetup {
    //     using LidoUtils for LidoUtils.Context;

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

        _adoptProposal(agentProposer, regularStaffCalls, "Make regular staff using Agent as executor");

        _step("4. Validate action was executed by the Agent");
        _assertTargetMockCalls({caller: address(_lido.agent), calls: regularStaffCalls});
    }

    function testFork_AragonAgentAsExecutor_RevertOn_FailedCall() external {
        _step("1. Grant EXECUTE_ROLE permission to the timelock on the Agent contract");
        {
            _grantAragonAgentExecuteRole(address(_timelock));
        }

        address agentProposer = makeAddr("AGENT_PROPOSER");
        _step("1. Submit proposal to register Aragon as the executor");
        {
            _addAragonAgentProposer(agentProposer);
        }

        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();
        vm.mockCallRevert(regularStaffCalls[0].target, regularStaffCalls[0].payload, "INVALID TARGET");

        uint256 agentActionsProposalId;
        _step("2. Submit proposal which should revert via the Agent proposer");
        {
            vm.prank(agentProposer);
            agentActionsProposalId =
                _submitProposal(agentProposer, regularStaffCalls, "Make regular staff using Agent as executor");

            _assertSubmittedProposalData(agentActionsProposalId, address(_lido.agent), regularStaffCalls);
        }

        _step("3. The execution of the proposal fails");
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
        ExternalCall[] memory callsToEmptyAccount = ExternalCallHelpers.create(
            [
                ExternalCall({value: 0, target: nonContractAccount, payload: new bytes(0)}),
                ExternalCall({
                    value: 0,
                    target: nonContractAccount,
                    payload: abi.encodeCall(IRegularContract.regularMethod, ())
                }),
                ExternalCall({value: uint96(callValue), target: nonContractAccount, payload: new bytes(0)})
            ]
        );
        uint256 agentBalanceBefore = address(_lido.agent).balance;
        vm.deal(address(_lido.agent), agentBalanceBefore + callValue);

        uint256 agentActionsProposalId;

        _step("2. Adopt proposal via the Agent proposer with calls to EOA account");
        {
            _adoptProposal(agentProposer, callsToEmptyAccount, "Make different calls to EOA account");
        }

        _step("3. When the calls is done by Agent, it's not failed and executed successfully");
        {
            assertEq(nonContractAccount.balance, 1 ether);
            assertEq(address(_lido.agent).balance, agentBalanceBefore);
        }
    }

    //     function testFork_AgentTimelockHappyPath() external {
    //         ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

    //         uint256 proposalId;
    //         _step("1. THE PROPOSAL IS SUBMITTED");
    //         {
    //             proposalId = _submitProposalViaDualGovernance(
    //                 "Propose to doSmth on target passing dual governance", regularStaffCalls
    //             );

    //             _assertSubmittedProposalData(proposalId, _getAdminExecutor(), regularStaffCalls);
    //             _assertCanScheduleViaDualGovernance(proposalId, false);
    //         }

    //         _step("2. THE PROPOSAL IS SCHEDULED");
    //         {
    //             _waitAfterSubmitDelayPassed();
    //             _assertCanScheduleViaDualGovernance(proposalId, true);
    //             _scheduleProposalViaDualGovernance(proposalId);

    //             _assertProposalScheduled(proposalId);
    //             _assertCanExecute(proposalId, false);
    //         }

    //         _step("3. THE PROPOSAL CAN BE EXECUTED");
    //         {
    //             // wait until the second delay has passed
    //             _waitAfterScheduleDelayPassed();

    //             // Now proposal can be executed
    //             _assertCanExecute(proposalId, true);

    //             _assertNoTargetMockCalls();

    //             _executeProposal(proposalId);
    //             _assertProposalExecuted(proposalId);

    //             _assertCanExecute(proposalId, false);
    //             _assertCanScheduleViaDualGovernance(proposalId, false);

    //             _assertTargetMockCalls(_getAdminExecutor(), regularStaffCalls);
    //         }
    //     }

    //     function testFork_TimelockEmergencyReset() external {
    //         ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

    //         // ---
    //         // 1. THE PROPOSAL IS SUBMITTED
    //         // ---
    //         uint256 proposalId;
    //         {
    //             proposalId = _submitProposalViaDualGovernance(
    //                 "Propose to doSmth on target passing dual governance", regularStaffCalls
    //             );
    //             _assertSubmittedProposalData(proposalId, _getAdminExecutor(), regularStaffCalls);

    //             // proposal can't be scheduled until the AFTER_SUBMIT_DELAY has passed
    //             _assertCanScheduleViaDualGovernance(proposalId, false);
    //         }

    //         // ---
    //         // 2. THE PROPOSAL IS SCHEDULED
    //         // ---
    //         {
    //             // wait until the delay has passed
    //             _wait(_timelock.getAfterSubmitDelay().plusSeconds(1));

    //             // when the first delay is passed and the is no opposition from the stETH holders
    //             // the proposal can be scheduled
    //             _assertCanScheduleViaDualGovernance(proposalId, true);

    //             _scheduleProposalViaDualGovernance(proposalId);

    //             // proposal can't be executed until the second delay has ended
    //             _assertProposalScheduled(proposalId);
    //             _assertCanExecute(proposalId, false);
    //         }

    //         // ---
    //         // 3. EMERGENCY MODE ACTIVATED &  GOVERNANCE RESET
    //         // ---
    //         {
    //             // some time passes and emergency committee activates emergency mode
    //             // and resets the controller
    //             _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

    //             // committee resets governance
    //             vm.prank(address(_deployConfig.timelock.emergencyActivationCommittee));
    //             _timelock.activateEmergencyMode();

    //             vm.prank(address(_deployConfig.timelock.emergencyExecutionCommittee));
    //             _timelock.emergencyReset();

    //             // proposal is canceled now
    //             _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

    //             // remove canceled call from the timelock
    //             _assertCanExecute(proposalId, false);
    //             _assertProposalCancelled(proposalId);
    //         }
    //     }

    //     // ---
    //     // Helper Methods
    //     // ---

    // function _grantAgentExecutorRoleToTimelock() internal {
    //     _lido.grantPermission(address(_lido.agent), _lido.agent.EXECUTE_ROLE(), address(_timelock));
    //     assertTrue(_lido.acl.hasPermission(address(_timelock), address(_lido.agent), _lido.agent.EXECUTE_ROLE()));
    // }

    function _addAragonAgentProposer(address agentProposer) internal {
        ExternalCall[] memory externalCalls = ExternalCallHelpers.create(
            [
                ExternalCall({
                    value: 0,
                    target: address(_dgDeployedContracts.dualGovernance),
                    payload: abi.encodeCall(
                        _dgDeployedContracts.dualGovernance.registerProposer, (agentProposer, address(_lido.agent))
                    )
                })
            ]
        );

        uint256 proposersCountBefore = _getProposers().length;

        _adoptProposalByAdminProposer(externalCalls, "Add Aragon Agent as proposer to the Dual Governance");

        Proposers.Proposer[] memory proposers = _getProposers();

        assertEq(proposers.length, proposersCountBefore + 1);
        assertEq(proposers[1].account, agentProposer);
        assertEq(proposers[1].executor, address(_lido.agent));
    }
}
