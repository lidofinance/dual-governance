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

        uint256 newVetoSupport = supportPercentage * IERC20(ST_ETH).totalSupply() / 10**18;
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
            DAO_VOTING,
            LDO_TOKEN,
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

        bytes memory targetCalldata = abi.encodeCall(target.doSmth, (42));
        bytes memory forwardCalldata = abi.encodeCall(dualGov.forwardCall, (address(target), targetCalldata));
        bytes memory script = Utils.encodeEvmCallScript(address(dualGov), forwardCalldata);

        uint256 voteId = dualGov.submitProposal(ARAGON_VOTING_SYSTEM_ID, script);
        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // from the Aragon's POV, the proposal is executable
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

        // however, proposals containing DG-related calls cannot be executed directly
        vm.expectRevert(DualGovernance.CannotCallOutsideExecution.selector);
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        // min execution timelock enforced by DG hasn't elapsed yet
        vm.expectRevert(DualGovernance.ProposalIsNotExecutable.selector);
        dualGov.executeProposal(ARAGON_VOTING_SYSTEM_ID, voteId, new bytes(0));

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        vm.expectCall(address(target), targetCalldata);
        target.expectCalledBy(address(agent));

        dualGov.executeProposal(ARAGON_VOTING_SYSTEM_ID, voteId, new bytes(0));
    }

    function test_happy_path_with_multiple_items() external {
        Target targetAragon = new Target();
        IAragonForwarder aragonAgent = IAragonForwarder(DAO_AGENT);
        bytes memory aragonTargetCalldata = abi.encodeCall(targetAragon.doSmth, (84));
        bytes memory aragonForwardScript = Utils.encodeEvmCallScript(address(targetAragon), aragonTargetCalldata);
        bytes memory aragonForwardCalldata = abi.encodeCall(aragonAgent.forward, aragonForwardScript);

        Target targetDualGov = new Target();
        bytes memory dgTargetCalldata = abi.encodeCall(targetDualGov.doSmth, (42));
        bytes memory dgForwardCalldata = abi.encodeCall(dualGov.forwardCall, (address(targetDualGov), dgTargetCalldata));

        Utils.EvmScriptCall[] memory voteCalls = new Utils.EvmScriptCall[](2);
        voteCalls[0] = Utils.EvmScriptCall(DAO_AGENT, aragonForwardCalldata);
        voteCalls[1] = Utils.EvmScriptCall(address(dualGov), dgForwardCalldata);
        bytes memory voteScript = Utils.encodeEvmCallScript(voteCalls);

        uint256 voteId = dualGov.submitProposal(ARAGON_VOTING_SYSTEM_ID, voteScript);
        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // from the Aragon's POV, the proposal is executable
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

        // however, proposals containing DG-related calls cannot be executed directly
        vm.expectRevert(DualGovernance.CannotCallOutsideExecution.selector);
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        // min execution timelock enforced by DG hasn't elapsed yet
        vm.expectRevert(DualGovernance.ProposalIsNotExecutable.selector);
        dualGov.executeProposal(ARAGON_VOTING_SYSTEM_ID, voteId, new bytes(0));

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        vm.expectCall(address(targetAragon), aragonTargetCalldata);
        vm.expectCall(address(targetDualGov), dgTargetCalldata);
        targetAragon.expectCalledBy(DAO_AGENT);
        targetDualGov.expectCalledBy(address(agent));

        dualGov.executeProposal(ARAGON_VOTING_SYSTEM_ID, voteId, new bytes(0));
    }

    function test_escalation_and_one_sided_de_escalation() external {
        Target target = new Target();

        bytes memory targetCalldata = abi.encodeCall(target.doSmth, (42));
        bytes memory forwardCalldata = abi.encodeCall(dualGov.forwardCall, (address(target), targetCalldata));
        bytes memory script = Utils.encodeEvmCallScript(address(dualGov), forwardCalldata);

        // submit and support a proposal
        uint256 voteId = dualGov.submitProposal(ARAGON_VOTING_SYSTEM_ID, script);
        Utils.supportVote(voteId, ldoWhale);

        // wait half vote time
        uint256 voteTime = IAragonVoting(DAO_VOTING).voteTime();
        vm.warp(block.timestamp + voteTime / 2);

        // Aragon voting is still not decided
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), false);

        // initial gov state is Normal
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        // escalate with 3% of stETH total supply
        updateVetoSupport(dualGov, 3 * 10**16 + 1);

        // gov state is now Veto Signalling
        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignalling);

        // wait till voting finishes
        vm.warp(block.timestamp + voteTime / 2 + 1);

        // Aragon voting has passed
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        // proposal is blocked due to stakers' opposition
        vm.expectRevert(DualGovernance.ProposalIsNotExecutable.selector);
        dualGov.executeProposal(ARAGON_VOTING_SYSTEM_ID, voteId, new bytes(0));

        // de-escalate down to 2% of stETH total supply
        updateVetoSupport(dualGov, 2 * 10**16 + 1);

        // Gov state is now Veto Signalling Deactivation
        assertEq(dualGov.currentState(), GovernanceState.State.VetoSignallingDeactivation);

        // proposal is still blocked
        vm.expectRevert(DualGovernance.ProposalIsNotExecutable.selector);
        dualGov.executeProposal(ARAGON_VOTING_SYSTEM_ID, voteId, new bytes(0));

        // wait till the Veto Signalling Deactivation timeout elapses
        vm.warp(block.timestamp + dualGov.CONFIG().signallingDeactivationDuration() + 1);

        // the activateNextState is required to trigger a state transition resulting from a timeout passing
        dualGov.activateNextState();

        // gov state is now Veto Cooldown
        assertEq(dualGov.currentState(), GovernanceState.State.VetoCooldown);

        // proposal is finally executable
        vm.expectCall(address(target), targetCalldata);
        target.expectCalledBy(address(agent));
        dualGov.executeProposal(ARAGON_VOTING_SYSTEM_ID, voteId, new bytes(0));

        // but new proposals cannot be submitted
        vm.expectRevert(DualGovernance.ProposalSubmissionNotAllowed.selector);
        dualGov.submitProposal(ARAGON_VOTING_SYSTEM_ID, script);

        // wait till the Veto Cooldown timeout elapses
        vm.warp(block.timestamp + dualGov.CONFIG().signallingCooldownDuration() + 1);

        // the activateNextState is required to trigger a state transition resulting from a timeout passing
        dualGov.activateNextState();

        // gov state is now Normal
        assertEq(dualGov.currentState(), GovernanceState.State.Normal);

        // now, new proposals can be submitted again
        dualGov.submitProposal(ARAGON_VOTING_SYSTEM_ID, script);
    }
}
