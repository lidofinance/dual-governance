pragma solidity 0.8.23;

import {Timelock} from "contracts/timelock/Timelock.sol";

import "forge-std/Test.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

abstract contract PlanBSetup is Test {
    function deployPlanB(
        address daoVoting,
        uint256 timelockDuration,
        address vetoMultisig,
        uint256 vetoMultisigActiveFor
    ) public returns (Timelock timelock) {
        timelock = new Timelock(
            daoVoting,
            DAO_AGENT,
            0 days, // MUST NOT be used in production. TODO: create better deployment process
            14 days,
            timelockDuration,
            vetoMultisig,
            block.timestamp + vetoMultisigActiveFor
        );
    }
}

contract HappyPathPlanBTest is PlanBSetup {
    IAragonVoting internal daoVoting;
    Timelock internal timelock;
    address internal vetoMultisig;
    address internal ldoWhale;
    Target internal target;

    uint256 internal timelockDuration;
    uint256 internal vetoMultisigActiveFor;

    function setUp() external {
        Utils.selectFork();

        ldoWhale = makeAddr("ldo_whale");
        Utils.setupLdoWhale(ldoWhale);

        vetoMultisig = makeAddr("vetoMultisig");

        timelockDuration = 1 days;
        vetoMultisigActiveFor = 90 days;

        timelock = deployPlanB(DAO_VOTING, timelockDuration, vetoMultisig, vetoMultisigActiveFor);
        target = new Target();
        daoVoting = IAragonVoting(DAO_VOTING);
    }

    function test_proposal() external {
        bytes memory targetCalldata = abi.encodeCall(target.doSmth, (42));

        address[] memory targets = new address[](1);
        targets[0] = address(target);

        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeCall(target.doSmth, (42));

        uint256 expectedProposalId = timelock.getProposalsCount() + 1;

        bytes memory proposeCalldata = abi.encodeCall(
            timelock.propose,
            (timelock.ADMIN_EXECUTOR(), targets, values, payloads)
        );
        bytes memory enqueueCalldata = abi.encodeCall(timelock.enqueue, (expectedProposalId, 0));

        Utils.EvmScriptCall[] memory evmScriptCalls = new Utils.EvmScriptCall[](2);
        evmScriptCalls[0] = Utils.EvmScriptCall({target: address(timelock), data: proposeCalldata});
        evmScriptCalls[1] = Utils.EvmScriptCall({target: address(timelock), data: enqueueCalldata});

        bytes memory script = Utils.encodeEvmCallScript(evmScriptCalls);

        bytes memory newVoteScript = Utils.encodeEvmCallScript(
            address(daoVoting),
            abi.encodeCall(daoVoting.newVote, (script, "", false, false))
        );

        uint256 voteId = daoVoting.votesLength();

        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(newVoteScript);
        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);
        daoVoting.executeVote(voteId);

        assertEq(timelock.getProposalsCount(), expectedProposalId);
        assertTrue(timelock.isEnqueued(expectedProposalId));
        assertFalse(timelock.isExecutable(expectedProposalId));

        vm.warp(block.timestamp + timelockDuration + 1);
        assertTrue(timelock.isExecutable(expectedProposalId));

        vm.expectCall(address(target), targetCalldata);
        target.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));

        timelock.execute(expectedProposalId);
    }
}
