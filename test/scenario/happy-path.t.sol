// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    Utils,
    ExecutorCall,
    IDangerousContract,
    ExecutorCallHelpers,
    ScenarioTestBlueprint
} from "../utils/scenario-test-blueprint.sol";
import {Proposals} from "contracts/libraries/Proposals.sol";

import {IAragonAgent, IAragonForwarder} from "../utils/interfaces.sol";
import {DAO_AGENT} from "../utils/mainnet-addresses.sol";

contract HappyPathTest is ScenarioTestBlueprint {
    function setUp() external {
        _selectFork();
        _deployTarget();
        _deployDualGovernanceSetup( /* isEmergencyProtectionEnabled */ false);
    }

    function testFork_HappyPath() external {
        ExecutorCall[] memory regularStaffCalls = _getTargetRegularStaffCalls();

        uint256 proposalId = _submitProposal(
            _dualGovernance, "DAO does regular staff on potentially dangerous contract", regularStaffCalls
        );
        _assertProposalSubmitted(proposalId);
        _assertSubmittedProposalData(proposalId, regularStaffCalls);

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2));

        // the min execution delay hasn't elapsed yet
        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        // wait till the first phase of timelock passes
        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
    }

    function testFork_HappyPathWithMultipleItems() external {
        // additional phase required here, grant rights to call DAO Agent to the admin executor
        Utils.grantPermission(DAO_AGENT, IAragonAgent(DAO_AGENT).RUN_SCRIPT_ROLE(), _config.ADMIN_EXECUTOR());

        bytes memory agentDoRegularStaffPayload = abi.encodeCall(IDangerousContract.doRegularStaff, (42));
        bytes memory targetCallEvmScript = Utils.encodeEvmCallScript(address(_target), agentDoRegularStaffPayload);

        ExecutorCall[] memory multipleCalls = ExecutorCallHelpers.create(
            [DAO_AGENT, address(_target)],
            [
                abi.encodeCall(IAragonForwarder.forward, (targetCallEvmScript)),
                abi.encodeCall(IDangerousContract.doRegularStaff, (43))
            ]
        );

        uint256 proposalId = _submitProposal(_dualGovernance, "Multiple items", multipleCalls);

        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2));

        // proposal can't be scheduled before the after submit delay has passed
        _assertCanSchedule(_dualGovernance, proposalId, false);

        // the min execution delay hasn't elapsed yet
        vm.expectRevert(abi.encodeWithSelector(Proposals.AfterSubmitDelayNotPassed.selector, (proposalId)));
        _scheduleProposal(_dualGovernance, proposalId);

        // wait till the DG-enforced timelock elapses
        _wait(_config.AFTER_SUBMIT_DELAY().dividedBy(2).plusSeconds(1));

        _assertCanSchedule(_dualGovernance, proposalId, true);
        _scheduleProposal(_dualGovernance, proposalId);
        _assertProposalScheduled(proposalId);

        _waitAfterScheduleDelayPassed();

        _assertCanExecute(proposalId, true);
        _executeProposal(proposalId);

        address[] memory senders = new address[](2);
        senders[0] = DAO_AGENT;
        senders[1] = _config.ADMIN_EXECUTOR();

        ExecutorCall[] memory expectedTargetCalls = ExecutorCallHelpers.create(
            [DAO_AGENT, address(_target)],
            [agentDoRegularStaffPayload, abi.encodeCall(IDangerousContract.doRegularStaff, (43))]
        );

        _assertTargetMockCalls(senders, expectedTargetCalls);
    }

    // TODO: make this test pass
    // function test_escalation_and_one_sided_de_escalation() external {
    //     Target target = new Target();

    //     ExecutorCall[] memory calls = new ExecutorCall[](1);
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
