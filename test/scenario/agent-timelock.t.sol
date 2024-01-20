pragma solidity 0.8.23;

import {Agent, TimelockCallSet} from "contracts/Agent.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

import {DualGovernanceSetup} from "./setup.sol";


contract AgentTimelockTest is DualGovernanceSetup {
    uint256 internal constant AGENT_TIMELOCK_DURATION = 1 days;
    uint256 internal constant EMERGENCY_MULTISIG_ACTIVE_FOR = 90 days;

    Agent internal agent;
    DualGovernance internal dualGov;

    address internal ldoWhale;
    address emergencyMultisig;

    function setUp() external {
        Utils.selectFork();
        Utils.removeLidoStakingLimit();

        ldoWhale = makeAddr("ldo_whale");
        Utils.setupLdoWhale(ldoWhale);

        emergencyMultisig = makeAddr("emergency_multisig");

        DualGovernanceSetup.Deployed memory deployed = deployDG(
            DAO_AGENT,
            ST_ETH,
            WST_ETH,
            WITHDRAWAL_QUEUE,
            AGENT_TIMELOCK_DURATION,
            emergencyMultisig,
            EMERGENCY_MULTISIG_ACTIVE_FOR
        );

        agent = deployed.agent;
        dualGov = deployed.dualGov;
    }

    function test_agent_timelock_happy_path() external {
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

        // no scheduled calls yet
        assertEq(agent.getScheduledCallIds().length, 0);

        // no calls to target yet
        // cannot use forge's expectCall here due to negative assertions' limitations, see issue #5655 in foundry
        target.expectNoCalls();

        // executing the proposal schedules one call from the Agent
        dualGov.executeProposal(proposalId);

        uint256[] memory scheduledCallIds = agent.getScheduledCallIds();
        assertEq(scheduledCallIds.length, 1);

        TimelockCallSet.Call memory call = agent.getScheduledCall(scheduledCallIds[0]);
        assertEq(call.target, address(target));
        assertEq(call.data, payloads[0]);

        // the call isn't executable yet
        assertEq(agent.getExecutableCallIds().length, 0);

        // wait till the Agent-enforced timelock elapses
        vm.warp(block.timestamp + AGENT_TIMELOCK_DURATION + 1);

        // the call became executable
        assertEq(agent.getExecutableCallIds(), scheduledCallIds);

        // executing the call invokes the target
        vm.expectCall(address(target), payloads[0]);
        target.expectCalledBy(address(agent));
        agent.executeScheduledCall(scheduledCallIds[0]);

        // no scheduled calls are left
        assertEq(agent.getScheduledCallIds().length, 0);
        assertEq(agent.getExecutableCallIds().length, 0);
    }

    function test_initial_agent_governance_value() external {
        assertEq(agent.getGovernance(), address(dualGov));
    }

    function test_agent_timelock_emergency_dg_deactivation() external {
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

        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // Execute the vote to submit the proposal to dual governance
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        // target won't be called in this test
        target.expectNoCalls();

        assertEq(dualGov.proposalsCount(), 1);

        uint256 proposalId = 0;
        // executing the proposal schedules one call from the Agent
        dualGov.executeProposal(proposalId);

        uint256[] memory scheduledCallIds = agent.getScheduledCallIds();
        assertEq(scheduledCallIds.length, 1);

        TimelockCallSet.Call memory call = agent.getScheduledCall(scheduledCallIds[0]);
        assertEq(call.target, address(target));
        assertEq(call.data, payloads[0]);

        // some time passes (but less than the Agent-enforced timelock)
        vm.warp(block.timestamp + AGENT_TIMELOCK_DURATION / 2);

        // the call is not executable yet
        assertEq(agent.getExecutableCallIds().length, 0);

        // emergency disabling the dual governance system while the multisig is active
        vm.prank(emergencyMultisig);
        agent.emergencyResetGovernanceToDAO();
        assertEq(agent.getGovernance(), DAO_AGENT);

        // waiting till the initial timelock of the scheduled call passes
        vm.warp(block.timestamp + AGENT_TIMELOCK_DURATION / 2 + 1);

        // the call is still scheduled
        assertEq(agent.getScheduledCallIds(), scheduledCallIds);
        call = agent.getScheduledCall(scheduledCallIds[0]);
        assertLt(call.lockedTill, block.timestamp);

        // but cannot be executed
        assertEq(agent.getExecutableCallIds().length, 0);
        vm.expectRevert(Agent.CallCancelled.selector);
        agent.executeScheduledCall(scheduledCallIds[0]);

        // anyone can unschedule cancelled calls
        agent.unscheduleCancelledCalls(scheduledCallIds);
        assertEq(agent.getScheduledCallIds().length, 0);
    }
}
