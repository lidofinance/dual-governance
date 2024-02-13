// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {DualGovernance, Proposals} from "contracts/DualGovernance.sol";
import {EmergencyProtectedTimelock, ExecutorCall, ScheduledCallsBatch} from "contracts/EmergencyProtectedTimelock.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

import {DualGovernanceSetup} from "./setup.sol";

contract AgentTimelockTest is DualGovernanceSetup {
    uint256 internal constant AGENT_TIMELOCK_DURATION = 1 days;
    uint256 internal constant EMERGENCY_MULTISIG_ACTIVE_FOR = 90 days;

    DualGovernance internal dualGov;
    EmergencyProtectedTimelock internal timelock;

    address internal ldoWhale;
    address emergencyMultisig;

    function setUp() external {
        Utils.selectFork();
        Utils.removeLidoStakingLimit();

        ldoWhale = makeAddr("ldo_whale");
        Utils.setupLdoWhale(ldoWhale);

        emergencyMultisig = makeAddr("emergency_multisig");

        DualGovernanceSetup.Deployed memory deployed = deployDG(
            ST_ETH,
            WST_ETH,
            BURNER,
            WITHDRAWAL_QUEUE,
            DAO_VOTING,
            AGENT_TIMELOCK_DURATION,
            emergencyMultisig,
            EMERGENCY_MULTISIG_ACTIVE_FOR
        );

        timelock = deployed.timelock;
        dualGov = deployed.dualGov;
    }

    function test_agent_timelock_happy_path() external {
        Target target = new Target();

        ExecutorCall[] memory calls = new ExecutorCall[](1);
        calls[0].value = 0;
        calls[0].target = address(target);
        calls[0].payload = abi.encodeCall(target.doSmth, (42));

        bytes memory script = Utils.encodeEvmCallScript(address(dualGov), abi.encodeCall(dualGov.propose, calls));

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
        dualGov.schedule(newProposalId);

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        // no calls to target yet
        // cannot use forge's expectCall here due to negative assertions' limitations, see issue #5655 in foundry
        target.expectNoCalls();

        // enqueueing the proposal schedules one call from the Timelock
        dualGov.schedule(newProposalId);

        assertEq(timelock.getScheduledCallBatchesCount(), 1);
        ScheduledCallsBatch memory scheduledCallsBatch = timelock.getScheduledCallsBatch(newProposalId);

        assertEq(scheduledCallsBatch.calls[0].target, address(target));
        assertEq(scheduledCallsBatch.calls[0].payload, calls[0].payload);

        // the call isn't executable yet
        assertFalse(timelock.getIsExecutable(newProposalId));

        // wait till the Timelock delay elapses
        vm.warp(block.timestamp + AGENT_TIMELOCK_DURATION + 1);

        // the call became executable
        assertTrue(timelock.getIsExecutable(newProposalId));

        // executing the call invokes the target
        vm.expectCall(address(target), calls[0].payload);
        target.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));
        timelock.execute(newProposalId);

        // scheduled call was removed after execution
        assertEq(timelock.getScheduledCallBatchesCount(), 0);
    }

    function test_initial_agent_governance_value() external {
        assertEq(timelock.getGovernance(), address(dualGov));
    }

    function test_agent_timelock_emergency_dg_deactivation() external {
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

        uint256 proposalsCountBefore = dualGov.getProposalsCount();

        // Execute the vote to submit the proposal to dual governance
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        assertEq(dualGov.getProposalsCount(), proposalsCountBefore + 1);

        uint256 newProposalId = proposalsCountBefore + 1;

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        // target won't be called in this test
        target.expectNoCalls();

        // enqueueing the proposal schedules one call from the Timelock
        dualGov.schedule(newProposalId);

        assertEq(timelock.getScheduledCallBatchesCount(), 1);

        ScheduledCallsBatch memory scheduledCallsBatch = timelock.getScheduledCallsBatch(newProposalId);

        assertEq(scheduledCallsBatch.calls[0].target, address(target));
        assertEq(scheduledCallsBatch.calls[0].payload, calls[0].payload);

        // some time passes (but less than the Timelock-enforced delay)
        vm.warp(block.timestamp + AGENT_TIMELOCK_DURATION / 2);

        // the call is not executable yet
        assertFalse(timelock.getIsExecutable(newProposalId));

        // emergency disabling the dual governance system while the multisig is active
        vm.prank(emergencyMultisig);
        timelock.emergencyModeActivate();
        vm.prank(emergencyMultisig);
        timelock.emergencyResetGovernance();
        assertEq(timelock.getGovernance(), DAO_VOTING);

        // waiting till the initial timelock of the scheduled call passes
        vm.warp(block.timestamp + AGENT_TIMELOCK_DURATION / 2 + 1);

        // remove canceled call from the timelock
        assertTrue(timelock.getIsCanceled(newProposalId));
        timelock.removeCanceledCallsBatch(newProposalId);
        assertEq(timelock.getScheduledCallBatchesCount(), 0);
    }
}
