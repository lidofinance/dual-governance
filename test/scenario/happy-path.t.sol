// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EvmScriptUtils} from "../utils/evm-script-utils.sol";
import {IPotentiallyDangerousContract} from "../utils/interfaces/IPotentiallyDangerousContract.sol";

import {ScenarioTestBlueprint} from "../utils/scenario-test-blueprint.sol";
import {ExternalCall, ExternalCallHelpers} from "../utils/test-utils.sol";

import {ExecutableProposals} from "contracts/libraries/ExecutableProposals.sol";

import {LidoUtils, EvmScriptUtils} from "../utils/lido-utils.sol";

contract HappyPathTest is ScenarioTestBlueprint {
    using LidoUtils for LidoUtils.Context;

    function setUp() external {
        _setUpEnvironment();
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});
    }

    function testFork_HappyPath() external {
        ExternalCall[] memory regularStaffCalls = _getMockTargetRegularStaffCalls();

        uint256 proposalId = _submitProposal(
            _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
        );
        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

        // the min execution delay hasn't elapsed yet
        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposalViaDualGovernance(proposalId);

        // wait till the first phase of timelock passes
        _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanScheduleViaDualGovernance(proposalId, true);
        _scheduleProposalViaDualGovernance(proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStaffCalls);
    }

    function testFork_HappyPathWithMultipleItems() external {
        // additional phase required here, grant rights to call DAO Agent to the admin executor
        _lido.grantPermission(address(_lido.agent), _lido.agent.RUN_SCRIPT_ROLE(), _timelock.getAdminExecutor());

        bytes memory agentDoRegularStaffPayload = abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (42));
        bytes memory targetCallEvmScript =
            EvmScriptUtils.encodeEvmCallScript(address(_targetMock), agentDoRegularStaffPayload);

        ExternalCall[] memory multipleCalls = ExternalCallHelpers.create(
            [address(_lido.agent), address(_targetMock)],
            [
                abi.encodeCall(_lido.agent.forward, (targetCallEvmScript)),
                abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (43))
            ]
        );

        uint256 proposalId = _submitProposal(_dualGovernance, "Multiple items", multipleCalls);

        _wait(_timelock.getAfterSubmitDelay().dividedBy(2));

        // proposal can't be scheduled before the after submit delay has passed
        _assertCanScheduleViaDualGovernance(proposalId, false);

        // the min execution delay hasn't elapsed yet
        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposalViaDualGovernance(proposalId);

        // wait till the DG-enforced timelock elapses
        _wait(_timelock.getAfterSubmitDelay().dividedBy(2).plusSeconds(1));

        _assertCanScheduleViaDualGovernance(proposalId, true);
        _scheduleProposalViaDualGovernance(proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        address[] memory senders = new address[](2);
        senders[0] = address(_lido.agent);
        senders[1] = _timelock.getAdminExecutor();

        ExternalCall[] memory expectedTargetCalls = ExternalCallHelpers.create(
            [address(_lido.agent), address(_targetMock)],
            [agentDoRegularStaffPayload, abi.encodeCall(IPotentiallyDangerousContract.doRegularStaff, (43))]
        );

        _assertTargetMockCalls(senders, expectedTargetCalls);
    }

    // TODO: make this test pass
    // function test_escalation_and_one_sided_de_escalation() external {
    //     Target target = new Target();

    //     ExternalCall[] memory calls = new ExternalCall[](1);
    //     calls[0].value = 0;
    //     calls[0].target = address(target);
    //     calls[0].payload = abi.encodeCall(target.doSmth, (42));

    //     bytes memory script = Utils.encodeEvmCallScript(address(dualGov), abi.encodeCall(dualGov.propose, (calls)));

    //     // create vote
    //     vm.prank(ldoWhale);
    //     IAragonVoting voting = IAragonVoting(DAO_VOTING);
    //     IAragonForwarder(DAO_TOKEN_MANAGER).forward(
    //         Utils.encodeEvmCallScript(
    //             DAO_VOTING,
    //             abi.encodeCall(
    //                 voting.newVote, (script, "Propose to doSmth on target passing dual governance", false, false)
    //             )
    //         )
    //     );

    //     uint256 voteId = voting.votesLength() - 1;

    //     // submit and support a proposal
    //     Utils.supportVote(voteId, ldoWhale);

    //     // wait half vote time
    //     uint256 voteTime = IAragonVoting(DAO_VOTING).voteTime();
    //     vm.warp(block.timestamp + voteTime / 2);

    //     // Aragon voting is still not decided
    //     assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), false);

    //     // initial gov state is Normal
    //     assertEq(dualGov.currentState(), GovernanceState.State.Normal);

    //     // escalate with 3% of stETH total supply
    //     updateVetoSupport(dualGov, 3 * 10 ** 16 + 1);

    //     // gov state is now Veto Signalling
    //     assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

    //     // wait till voting finishes
    //     vm.warp(block.timestamp + voteTime / 2 + 1);

    //     // Aragon voting has passed
    //     assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

    //     // gov state is now Veto Signalling
    //     assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

    //     uint256 proposalsCountBefore = dualGov.getProposalsCount();

    //     // execute the DAO voting
    //     IAragonVoting(DAO_VOTING).executeVote(voteId);

    //     assertEq(dualGov.getProposalsCount(), proposalsCountBefore + 1);

    //     uint256 proposalId = dualGov.getProposalsCount();

    //     // wait till the DG-enforced timelock elapses
    //     vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

    //     // proposal is blocked due to stakers' opposition
    //     vm.expectRevert(DualGovernance.ExecutionForbidden.selector);
    //     dualGov.relay(proposalId);

    //     // de-escalate down to 2% of stETH total supply
    //     updateVetoSupport(dualGov, 2 * 10 ** 16 + 1);

    //     // Gov state is now Veto Signalling Deactivation
    //     assertEq(dualGov.currentState(), GovernanceState.State.VetoSignallingDeactivation);

    //     // proposal is still blocked
    //     vm.expectRevert(DualGovernance.ExecutionForbidden.selector);
    //     dualGov.relay(proposalId);

    //     // wait till the Veto Signalling Deactivation timeout elapses
    //     vm.warp(block.timestamp + dualGov.CONFIG().signallingDeactivationDuration() + 1);

    //     // the activateNextState is required to trigger a state transition resulting from a timeout passing
    //     dualGov.activateNextState();

    //     // gov state is now Veto Cooldown
    //     assertEq(dualGov.currentState(), GovernanceState.State.VetoCooldown);

    //     // proposal is finally executable
    //     vm.expectCall(address(target), calls[0].payload);
    //     target.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));

    //     // the timelock is set to 0, so call will be executed immediately
    //     dualGov.relay(proposalId);

    //     // but new proposals cannot be submitted
    //     vm.prank(ldoWhale);
    //     IAragonForwarder(DAO_TOKEN_MANAGER).forward(
    //         Utils.encodeEvmCallScript(
    //             DAO_VOTING,
    //             abi.encodeCall(
    //                 voting.newVote, (script, "Propose to doSmth on target passing dual governance", false, false)
    //             )
    //         )
    //     );

    //     uint256 newVoteId = voting.votesLength() - 1;
    //     Utils.supportVoteAndWaitTillDecided(newVoteId, ldoWhale);

    //     // from the Aragon's POV, the proposal is executable
    //     assertEq(IAragonVoting(DAO_VOTING).canExecute(newVoteId), true);

    //     // Execute the vote to submit the proposal to dual governance must fail there
    //     vm.expectRevert(DualGovernance.ProposalSubmissionNotAllowed.selector);
    //     IAragonVoting(DAO_VOTING).executeVote(newVoteId);

    //     // wait till the Veto Cooldown timeout elapses
    //     vm.warp(block.timestamp + dualGov.CONFIG().signallingCooldownDuration() + 1);

    //     // the activateNextState is required to trigger a state transition resulting from a timeout passing
    //     dualGov.activateNextState();

    //     // gov state is now Normal
    //     assertEq(dualGov.currentState(), GovernanceState.State.Normal);

    //     // now, new proposals can be submitted again
    //     IAragonVoting(DAO_VOTING).executeVote(newVoteId);
    // }
}
