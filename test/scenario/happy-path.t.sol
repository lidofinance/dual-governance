// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Escrow} from "contracts/Escrow.sol";
import {DualGovernance, Proposals, ExecutorCall} from "contracts/DualGovernance.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import "forge-std/Test.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

import {DualGovernanceSetup} from "./setup.sol";

abstract contract DualGovernanceUtils is TestAssertions {
    function updateVetoSupport(DualGovernance dualGov, uint256 supportPercentage) internal {
        Escrow signallingEscrow = Escrow(payable(dualGov.signallingEscrow()));

        uint256 newVetoSupport = (supportPercentage * IERC20(ST_ETH).totalSupply()) / 10 ** 18;
        // uint256 currentVetoSupport = signallingEscrow.totalStEthLocked();

        // if (newVetoSupport > currentVetoSupport) {
        //     signallingEscrow.mock__lockStEth(newVetoSupport - currentVetoSupport);
        // } else if (newVetoSupport < currentVetoSupport) {
        //     signallingEscrow.mock__unlockStEth(currentVetoSupport - newVetoSupport);
        // }

        (uint256 totalSupport, uint256 rageQuitSupport) = signallingEscrow.getSignallingState();
        // solhint-disable-next-line
        console.log("veto totalSupport %d, rageQuitSupport %d", totalSupport, rageQuitSupport);
    }
}

contract HappyPathTest is DualGovernanceSetup, DualGovernanceUtils {
    EmergencyProtectedTimelock internal timelock;
    DualGovernance internal dualGov;

    address internal ldoWhale;
    address internal stEthWhale;

    function setUp() external {
        Utils.selectFork();

        Utils.removeLidoStakingLimit();

        ldoWhale = makeAddr("ldo_whale");
        Utils.setupLdoWhale(ldoWhale);

        stEthWhale = makeAddr("steth_whale");
        Utils.setupStEthWhale(stEthWhale);

        uint256 timelockDuration = 0;
        address timelockEmergencyMultisig = address(0);
        uint256 timelockEmergencyMultisigActiveFor = 0;

        DualGovernanceSetup.Deployed memory deployed = deployDG(
            ST_ETH,
            WST_ETH,
            WITHDRAWAL_QUEUE,
            BURNER,
            DAO_VOTING,
            timelockDuration,
            timelockEmergencyMultisig,
            timelockEmergencyMultisigActiveFor
        );

        timelock = deployed.timelock;
        dualGov = deployed.dualGov;
    }

    function test_setup() external {
        assertEq(timelock.getGovernance(), address(dualGov));
    }

    function test_happy_path() external {
        Target target = new Target();

        ExecutorCall[] memory calls = new ExecutorCall[](1);
        calls[0].value = 0;
        calls[0].target = address(target);
        calls[0].payload = abi.encodeCall(target.doSmth, (42));

        bytes memory script = Utils.encodeEvmCallScript(address(dualGov), abi.encodeCall(dualGov.propose, (calls)));

        // create vote
        vm.prank(ldoWhale);
        IAragonVoting voting = IAragonVoting(DAO_VOTING);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                DAO_VOTING,
                abi.encodeCall(
                    voting.newVote, (script, "Propose to doSmth on target passing dual governance", false, false)
                )
            )
        );

        uint256 voteId = voting.votesLength() - 1;

        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // from the Aragon's POV, the proposal is executable
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

        uint256 proposalsCountBefore = dualGov.getProposalsCount();

        // Execute the vote to submit the proposal to dual governance
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        assertEq(dualGov.getProposalsCount(), proposalsCountBefore + 1);

        uint256 newProposalId = dualGov.getProposalsCount();

        // min execution timelock enforced by DG hasn't elapsed yet
        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotExecutable.selector, (newProposalId)));
        dualGov.relay(newProposalId);

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        vm.expectCall(address(target), calls[0].payload);
        target.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));

        // the timelock is set to 0, so call will be executed immediately
        dualGov.relay(newProposalId);

        // timelock will not have scheduled calls now
        assertEq(timelock.getScheduledCallBatchesCount(), 0);
    }

    function test_happy_path_with_multiple_items() external {
        // additional phase required here, grant rights to call DAO Agent to the admin executor
        Utils.grantPermission(DAO_AGENT, IAragonAgent(DAO_AGENT).RUN_SCRIPT_ROLE(), address(timelock.ADMIN_EXECUTOR()));

        // prepare target to be called by the DAO agent using DG Executor
        Target targetAragon = new Target();
        IAragonForwarder aragonAgent = IAragonForwarder(DAO_AGENT);
        bytes memory aragonTargetCalldata = abi.encodeCall(targetAragon.doSmth, (84));
        bytes memory aragonForwardScript = Utils.encodeEvmCallScript(address(targetAragon), aragonTargetCalldata);

        // prepare target to be called by the executor
        Target targetDualGov = new Target();

        ExecutorCall[] memory calls = new ExecutorCall[](2);
        calls[0].value = 0;
        calls[0].target = DAO_AGENT;
        calls[0].payload = abi.encodeCall(aragonAgent.forward, aragonForwardScript);

        calls[1].value = 0;
        calls[1].target = address(targetDualGov);
        calls[1].payload = abi.encodeCall(targetDualGov.doSmth, (42));

        bytes memory script = Utils.encodeEvmCallScript(address(dualGov), abi.encodeCall(dualGov.propose, (calls)));

        // create vote
        vm.prank(ldoWhale);
        IAragonVoting voting = IAragonVoting(DAO_VOTING);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                DAO_VOTING, abi.encodeCall(voting.newVote, (script, "Call doSmth from different agents", false, false))
            )
        );

        uint256 voteId = voting.votesLength() - 1;

        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // from the Aragon's POV, the proposal is executable
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

        uint256 proposalsCountBefore = dualGov.getProposalsCount();

        // Execute the vote to submit the proposal to dual governance
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        assertEq(dualGov.getProposalsCount(), proposalsCountBefore + 1);

        uint256 newProposalId = proposalsCountBefore + 1;

        // min execution timelock enforced by DG hasn't elapsed yet
        vm.expectRevert(abi.encodeWithSelector(Proposals.ProposalNotExecutable.selector, (newProposalId)));
        dualGov.relay(newProposalId);

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        // check the calls will be executed
        vm.expectCall(address(targetAragon), aragonTargetCalldata);
        vm.expectCall(address(targetDualGov), calls[1].payload);
        targetAragon.expectCalledBy(DAO_AGENT);
        targetDualGov.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));

        // the timelock is set to 0, so call will be executed immediately
        dualGov.relay(newProposalId);

        // timelock will not have scheduled calls now
        assertEq(timelock.getScheduledCallBatchesCount(), 0);
    }

    function test_escalation_and_one_sided_de_escalation() external {
        Target target = new Target();

        ExecutorCall[] memory calls = new ExecutorCall[](1);
        calls[0].value = 0;
        calls[0].target = address(target);
        calls[0].payload = abi.encodeCall(target.doSmth, (42));

        bytes memory script = Utils.encodeEvmCallScript(address(dualGov), abi.encodeCall(dualGov.propose, (calls)));

        // create vote
        vm.prank(ldoWhale);
        IAragonVoting voting = IAragonVoting(DAO_VOTING);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                DAO_VOTING,
                abi.encodeCall(
                    voting.newVote, (script, "Propose to doSmth on target passing dual governance", false, false)
                )
            )
        );

        uint256 voteId = voting.votesLength() - 1;

        // submit and support a proposal
        Utils.supportVote(voteId, ldoWhale);

        // wait half vote time
        uint256 voteTime = IAragonVoting(DAO_VOTING).voteTime();
        vm.warp(block.timestamp + voteTime / 2);

        // Aragon voting is still not decided
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), false);

        // initial gov state is Normal
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        // escalate with 3% of stETH total supply
        updateVetoSupport(dualGov, 3 * 10 ** 16 + 1);

        // gov state is now Veto Signalling
        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        // wait till voting finishes
        vm.warp(block.timestamp + voteTime / 2 + 1);

        // Aragon voting has passed
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

        // gov state is now Veto Signalling
        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        uint256 proposalsCountBefore = dualGov.getProposalsCount();

        // execute the DAO voting
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        assertEq(dualGov.getProposalsCount(), proposalsCountBefore + 1);

        uint256 proposalId = dualGov.getProposalsCount();

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        // proposal is blocked due to stakers' opposition
        vm.expectRevert(DualGovernance.ExecutionForbidden.selector);
        dualGov.relay(proposalId);

        // de-escalate down to 2% of stETH total supply
        updateVetoSupport(dualGov, 2 * 10 ** 16 + 1);

        // Gov state is now Veto Signalling Deactivation
        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignallingDeactivation);

        // proposal is still blocked
        vm.expectRevert(DualGovernance.ExecutionForbidden.selector);
        dualGov.relay(proposalId);

        // wait till the Veto Signalling Deactivation timeout elapses
        vm.warp(block.timestamp + dualGov.CONFIG().signallingDeactivationDuration() + 1);

        // the activateNextState is required to trigger a state transition resulting from a timeout passing
        dualGov.activateNextState();

        // gov state is now Veto Cooldown
        assertEq(dualGov.currentState(), GovernanceState.State.VetoCooldown);

        // proposal is finally executable
        vm.expectCall(address(target), calls[0].payload);
        target.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));

        // the timelock is set to 0, so call will be executed immediately
        dualGov.relay(proposalId);

        // but new proposals cannot be submitted
        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                DAO_VOTING,
                abi.encodeCall(
                    voting.newVote, (script, "Propose to doSmth on target passing dual governance", false, false)
                )
            )
        );

        uint256 newVoteId = voting.votesLength() - 1;
        Utils.supportVoteAndWaitTillDecided(newVoteId, ldoWhale);

        // from the Aragon's POV, the proposal is executable
        assertEq(IAragonVoting(DAO_VOTING).canExecute(newVoteId), true);

        // Execute the vote to submit the proposal to dual governance must fail there
        vm.expectRevert(DualGovernance.ProposalSubmissionNotAllowed.selector);
        IAragonVoting(DAO_VOTING).executeVote(newVoteId);

        // wait till the Veto Cooldown timeout elapses
        vm.warp(block.timestamp + dualGov.CONFIG().signallingCooldownDuration() + 1);

        // the activateNextState is required to trigger a state transition resulting from a timeout passing
        dualGov.activateNextState();

        // gov state is now Normal
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        // now, new proposals can be submitted again
        IAragonVoting(DAO_VOTING).executeVote(newVoteId);
    }
}
