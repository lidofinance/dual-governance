pragma solidity 0.8.23;

import {Agent} from "contracts/Agent.sol";
import {Escrow} from "contracts/Escrow.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";

import "forge-std/Test.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

import {DualGovernanceSetup} from "./setup.sol";

abstract contract DualGovernanceUtils is TestAssertions {
    function updateVetoSupport(DualGovernance dualGov, uint256 supportPercentage) internal {
        Escrow signallingEscrow = Escrow(dualGov.signallingEscrow());

        uint256 newVetoSupport = (supportPercentage * IERC20(ST_ETH).totalSupply()) / 10 ** 18;
        uint256 currentVetoSupport = signallingEscrow.totalStEthLocked();

        if (newVetoSupport > currentVetoSupport) {
            signallingEscrow.mock__lockStEth(newVetoSupport - currentVetoSupport);
        } else if (newVetoSupport < currentVetoSupport) {
            signallingEscrow.mock__unlockStEth(currentVetoSupport - newVetoSupport);
        }

        (uint256 totalSupport, uint256 rageQuitSupport) = signallingEscrow.getSignallingState();
        console.log("veto totalSupport %d, rageQuitSupport %d", totalSupport, rageQuitSupport);
    }
}

contract HappyPathTest is DualGovernanceSetup, DualGovernanceUtils {
    Agent internal agent;
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

        uint256 agentTimelock = 0;
        address emergencyMultisig = address(0);
        uint256 agentEmergencyMultisigActiveFor = 0;

        DualGovernanceSetup.Deployed memory deployed = deployDG(
            DAO_AGENT,
            ST_ETH,
            WST_ETH,
            WITHDRAWAL_QUEUE,
            agentTimelock,
            emergencyMultisig,
            agentEmergencyMultisigActiveFor
        );

        agent = deployed.agent;
        dualGov = deployed.dualGov;
    }

    function test_setup() external {
        assertEq(agent.getGovernance(), address(dualGov));
    }

    function test_happy_path() external {
        Target target = new Target();

        address[] memory targets = new address[](1);
        targets[0] = address(target);

        uint256[] memory values = new uint256[](1);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeCall(target.doSmth, (42));

        bytes memory script = Utils.encodeEvmCallScript(
            address(dualGov),
            abi.encodeCall(dualGov.submitProposal, (targets, values, payloads))
        );

        // create vote
        vm.prank(ldoWhale);
        IAragonVoting voting = IAragonVoting(DAO_VOTING);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                DAO_VOTING,
                abi.encodeCall(
                    voting.newVote,
                    (script, "Propose to doSmth on target passing dual governance", false, false)
                )
            )
        );

        uint256 voteId = voting.votesLength() - 1;

        // uint256 voteId = dualGov.submitProposal(ARAGON_VOTING_SYSTEM_ID, script);
        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // from the Aragon's POV, the proposal is executable
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

        // Execute the vote to submit the proposal to dual governance
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        assertEq(dualGov.proposalsCount(), 1);

        uint256 proposalId = 0;

        // min execution timelock enforced by DG hasn't elapsed yet
        vm.expectRevert(DualGovernance.ProposalIsNotExecutable.selector);
        dualGov.executeProposal(proposalId);

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        vm.expectCall(address(target), payloads[0]);
        target.expectCalledBy(address(agent));

        dualGov.executeProposal(proposalId);
    }

    function test_happy_path_with_multiple_items() external {
        // additional phase required here, grant rights to call DAO Agent to the DualGovernance Agent
        Utils.grantPermission(DAO_AGENT, IAragonAgent(DAO_AGENT).RUN_SCRIPT_ROLE(), address(agent));

        // prepare target to be called by the DAO agent using DG Agent
        Target targetAragon = new Target();
        IAragonForwarder aragonAgent = IAragonForwarder(DAO_AGENT);
        bytes memory aragonTargetCalldata = abi.encodeCall(targetAragon.doSmth, (84));
        bytes memory aragonForwardScript = Utils.encodeEvmCallScript(
            address(targetAragon),
            aragonTargetCalldata
        );

        // prepare target to be called by the DG Agent
        Target targetDualGov = new Target();

        address[] memory targets = new address[](2);
        targets[0] = DAO_AGENT;
        targets[1] = address(targetDualGov);

        uint256[] memory values = new uint256[](2);

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(aragonAgent.forward, aragonForwardScript);
        payloads[1] = abi.encodeCall(targetDualGov.doSmth, (42));

        bytes memory script = Utils.encodeEvmCallScript(
            address(dualGov),
            abi.encodeCall(dualGov.submitProposal, (targets, values, payloads))
        );

        // create vote
        vm.prank(ldoWhale);
        IAragonVoting voting = IAragonVoting(DAO_VOTING);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                DAO_VOTING,
                abi.encodeCall(
                    voting.newVote,
                    (script, "Call doSmth from different agents", false, false)
                )
            )
        );

        uint256 voteId = voting.votesLength() - 1;

        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // from the Aragon's POV, the proposal is executable
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

        // Execute the vote to submit the proposal to dual governance
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        assertEq(dualGov.proposalsCount(), 1);
        uint256 proposalId = 0;

        // min execution timelock enforced by DG hasn't elapsed yet
        vm.expectRevert(DualGovernance.ProposalIsNotExecutable.selector);
        dualGov.executeProposal(proposalId);

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        vm.expectCall(address(targetAragon), aragonTargetCalldata);
        vm.expectCall(address(targetDualGov), payloads[1]);
        targetAragon.expectCalledBy(DAO_AGENT);
        targetDualGov.expectCalledBy(address(agent));

        dualGov.executeProposal(proposalId);
    }

    function test_escalation_and_one_sided_de_escalation() external {
        Target target = new Target();

        address[] memory targets = new address[](1);
        targets[0] = address(target);

        uint256[] memory values = new uint256[](1);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeCall(target.doSmth, (42));

        bytes memory script = Utils.encodeEvmCallScript(
            address(dualGov),
            abi.encodeCall(dualGov.submitProposal, (targets, values, payloads))
        );

        // create vote
        vm.prank(ldoWhale);
        IAragonVoting voting = IAragonVoting(DAO_VOTING);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                DAO_VOTING,
                abi.encodeCall(
                    voting.newVote,
                    (script, "Propose to doSmth on target passing dual governance", false, false)
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

        // execute the DAO voting
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        assertEq(dualGov.proposalsCount(), 1);

        uint256 proposalId = 0;

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        // proposal is blocked due to stakers' opposition
        vm.expectRevert(DualGovernance.ProposalIsNotExecutable.selector);
        dualGov.executeProposal(proposalId);

        // de-escalate down to 2% of stETH total supply
        updateVetoSupport(dualGov, 2 * 10 ** 16 + 1);

        // Gov state is now Veto Signalling Deactivation
        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignallingDeactivation);

        // proposal is still blocked
        vm.expectRevert(DualGovernance.ProposalIsNotExecutable.selector);
        dualGov.executeProposal(proposalId);

        // wait till the Veto Signalling Deactivation timeout elapses
        vm.warp(block.timestamp + dualGov.CONFIG().signallingDeactivationDuration() + 1);

        // the activateNextState is required to trigger a state transition resulting from a timeout passing
        dualGov.activateNextState();

        // gov state is now Veto Cooldown
        assertEq(dualGov.currentState(), GovernanceState.State.VetoCooldown);

        // proposal is finally executable
        vm.expectCall(address(target), payloads[0]);
        target.expectCalledBy(address(agent));
        dualGov.executeProposal(proposalId);

        // but new proposals cannot be submitted
        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                DAO_VOTING,
                abi.encodeCall(
                    voting.newVote,
                    (script, "Propose to doSmth on target passing dual governance", false, false)
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
