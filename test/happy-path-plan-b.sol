pragma solidity 0.8.23;

import {Agent} from "contracts/Agent.sol";

import "forge-std/Test.sol";

import "./utils/mainnet-addresses.sol";
import "./utils/interfaces.sol";
import "./utils/utils.sol";


abstract contract PlanBSetup is Test {
    function deployPlanB(
        address daoVoting,
        uint256 agentTimelock,
        address vetoMultisig,
        uint256 vetoMultisigActiveFor
    ) public returns (
        Agent agent
    ) {
        agent = new Agent(daoVoting, address(this));
        agent.forwardCall(address(agent), abi.encodeCall(
            agent.setEmergencyMultisig, (
                vetoMultisig,
                vetoMultisigActiveFor
            )
        ));
        agent.forwardCall(address(agent), abi.encodeCall(
            agent.setGovernance, (
                daoVoting,
                agentTimelock
            )
        ));
    }
}


contract HappyPathPlanBTest is PlanBSetup {
    IAragonVoting internal daoVoting;
    Agent internal agent;
    address internal vetoMultisig;
    address internal ldoWhale;
    Target internal target;

    uint256 internal agentTimelock;
    uint256 internal vetoMultisigActiveFor;

    function setUp() external {
        Utils.selectFork();

        ldoWhale = makeAddr("ldo_whale");
        Utils.setupLdoWhale(ldoWhale);

        vetoMultisig = makeAddr("vetoMultisig");

        agentTimelock = 1 days;
        vetoMultisigActiveFor = 90 days;

        agent = deployPlanB(DAO_VOTING, agentTimelock, vetoMultisig, vetoMultisigActiveFor);
        target = new Target();
        daoVoting = IAragonVoting(DAO_VOTING);
    }

    function test_proposal() external {
        bytes memory targetCalldata = abi.encodeCall(target.doSmth, (42));
        bytes memory forwardCalldata = abi.encodeCall(agent.forwardCall, (address(target), targetCalldata));
        bytes memory script = Utils.encodeEvmCallScript(address(agent), forwardCalldata);

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

        uint256[] memory callIds = agent.getScheduledCallIds();
        assertEq(callIds.length, 1);
        assertEq(agent.getExecutableCallIds().length, 0);

        vm.warp(block.timestamp + agentTimelock + 1);
        uint256[] memory execCallIds = agent.getExecutableCallIds();
        assertEq(execCallIds.length, 1);
        assertEq(execCallIds, callIds);

        vm.expectCall(address(target), targetCalldata);
        target.expectCalledBy(address(agent));

        agent.executeScheduledCall(execCallIds[0]);
    }
}
