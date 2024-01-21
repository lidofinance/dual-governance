pragma solidity 0.8.23;

import {DualGovernance} from "contracts/DualGovernance.sol";
import {Timelock, Proposals, Proposal} from "contracts/timelock/Timelock.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

import {DualGovernanceSetup} from "./setup.sol";

contract AgentTimelockTest is DualGovernanceSetup {
    uint256 internal constant AGENT_TIMELOCK_DURATION = 1 days;
    uint256 internal constant EMERGENCY_MULTISIG_ACTIVE_FOR = 90 days;

    Timelock internal timelock;
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
            ST_ETH,
            WST_ETH,
            WITHDRAWAL_QUEUE,
            AGENT_TIMELOCK_DURATION,
            emergencyMultisig,
            EMERGENCY_MULTISIG_ACTIVE_FOR
        );

        timelock = deployed.timelock;
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
            abi.encodeCall(dualGov.propose, (targets, values, payloads))
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

        uint256 proposalsCountBefore = timelock.getProposalsCount();

        // Execute the vote to submit the proposal to dual governance
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        assertEq(timelock.getProposalsCount(), proposalsCountBefore + 1);

        uint256 newProposalId = timelock.getProposalsCount();

        assertTrue(timelock.isProposed(newProposalId));

        // min execution timelock enforced by DG hasn't elapsed yet
        vm.expectRevert(Proposals.ProposalIsNotReady.selector);
        dualGov.enqueue(newProposalId);

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        // no calls to target yet
        // cannot use forge's expectCall here due to negative assertions' limitations, see issue #5655 in foundry
        target.expectNoCalls();

        // enqueueing the proposal schedules one call from the Timelock
        dualGov.enqueue(newProposalId);

        assertTrue(timelock.isEnqueued(newProposalId));

        Proposal memory newProposal = timelock.getProposal(newProposalId);
        assertEq(newProposal.targets[0], address(target));
        assertEq(newProposal.payloads[0], payloads[0]);

        // the call isn't executable yet
        assertFalse(timelock.isExecutable(newProposalId));

        // wait till the Timelock delay elapses
        vm.warp(block.timestamp + AGENT_TIMELOCK_DURATION + 1);

        // the call became executable
        assertTrue(timelock.isExecutable(newProposalId));

        // executing the call invokes the target
        vm.expectCall(address(target), payloads[0]);
        target.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));
        timelock.execute(newProposalId);

        // no scheduled calls are left
        assertTrue(timelock.isExecuted(newProposalId));
    }

    function test_initial_agent_governance_value() external {
        assertEq(timelock.admin(), address(dualGov));
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
            abi.encodeCall(dualGov.propose, (targets, values, payloads))
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

        uint256 proposalsCountBefore = timelock.getProposalsCount();

        // Execute the vote to submit the proposal to dual governance
        IAragonVoting(DAO_VOTING).executeVote(voteId);

        assertEq(timelock.getProposalsCount(), proposalsCountBefore + 1);

        uint256 newProposalId = proposalsCountBefore + 1;
        assertTrue(timelock.isProposed(newProposalId));

        // wait till the DG-enforced timelock elapses
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock());

        // target won't be called in this test
        target.expectNoCalls();

        // enqueueing the proposal schedules one call from the Timelock
        dualGov.enqueue(newProposalId);
        assertTrue(timelock.isEnqueued(newProposalId));

        Proposal memory newProposal = timelock.getProposal(newProposalId);
        assertEq(newProposal.targets[0], address(target));
        assertEq(newProposal.payloads[0], payloads[0]);

        // some time passes (but less than the Timelock-enforced delay)
        vm.warp(block.timestamp + AGENT_TIMELOCK_DURATION / 2);

        // the call is not executable yet
        assertFalse(timelock.isExecutable(newProposalId));

        // emergency disabling the dual governance system while the multisig is active
        vm.prank(emergencyMultisig);
        timelock.resetToEmergencyAdmin();
        assertEq(timelock.admin(), DAO_AGENT);

        // waiting till the initial timelock of the scheduled call passes
        vm.warp(block.timestamp + AGENT_TIMELOCK_DURATION / 2 + 1);

        assertFalse(timelock.isExecutable(newProposalId));
        assertFalse(timelock.isCanceled(newProposalId));
        assertTrue(timelock.isDequeued(newProposalId));
    }
}
