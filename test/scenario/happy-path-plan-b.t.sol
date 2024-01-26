// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {EmergencyProtectedTimelock, ExecutorCall, ScheduledExecutorCallsBatch, ScheduledCalls} from "contracts/EmergencyProtectedTimelock.sol";

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
    ) public returns (EmergencyProtectedTimelock timelock) {
        OwnableExecutor adminExecutor = new OwnableExecutor(address(this));

        timelock = new EmergencyProtectedTimelock(address(adminExecutor), daoVoting);

        // configure Timelock
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setGovernance, (daoVoting, timelockDuration))
        );

        // TODO: pass this value via args
        uint256 emergencyModeDuration = 180 days;
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setEmergencyCommittee,
                (vetoMultisig, vetoMultisigActiveFor, emergencyModeDuration)
            )
        );

        adminExecutor.transferOwnership(address(timelock));
    }
}

contract HappyPathPlanBTest is PlanBSetup {
    IAragonVoting internal daoVoting;
    EmergencyProtectedTimelock internal timelock;
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

        ExecutorCall[] memory calls = new ExecutorCall[](1);
        calls[0].value = 0;
        calls[0].target = address(target);
        calls[0].payload = abi.encodeCall(target.doSmth, (42));

        uint256 proposalId = 1;

        bytes memory proposeCalldata = abi.encodeCall(
            timelock.schedule,
            (proposalId, timelock.ADMIN_EXECUTOR(), calls)
        );

        bytes memory script = Utils.encodeEvmCallScript(address(timelock), proposeCalldata);

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

        ScheduledExecutorCallsBatch memory callsBatch = timelock.getScheduledCalls(proposalId);

        assertTrue(callsBatch.executableAfter > 0);

        vm.warp(block.timestamp + timelockDuration + 1);
        assertTrue(callsBatch.executableAfter < block.timestamp);

        vm.expectCall(address(target), targetCalldata);
        target.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));

        timelock.execute(proposalId);

        // malicious vote was proposed and passed
        uint256 maliciousVoteId = daoVoting.votesLength();

        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(newVoteScript);
        Utils.supportVoteAndWaitTillDecided(maliciousVoteId, ldoWhale);

        assertEq(IAragonVoting(DAO_VOTING).canExecute(maliciousVoteId), true);
        daoVoting.executeVote(maliciousVoteId);

        // emergency committee activates emergency mode
        vm.prank(vetoMultisig);
        timelock.enterEmergencyMode();
        (bool isEmergencyModeActive, , ) = timelock.getEmergencyModeState();
        assertTrue(isEmergencyModeActive);

        // now, only emergency committee may execute calls on timelock
        vm.warp(block.timestamp + timelockDuration + 1);
        uint256 maliciousProposalId = 1;
        ScheduledExecutorCallsBatch memory maliciousCallsBatch = timelock.getScheduledCalls(
            maliciousProposalId
        );
        assertTrue(maliciousCallsBatch.executableAfter < block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtectedTimelock.NotEmergencyCommittee.selector,
                address(this)
            )
        );
        timelock.execute(maliciousProposalId);

        // some time later, the ldo holders controlling major part of LDO prepare vote to
        // burn ldo of malicious actor
        Target newTarget = new Target();

        ExecutorCall[] memory newCalls = new ExecutorCall[](1);
        newCalls[0].value = 0;
        newCalls[0].target = address(newTarget);
        newCalls[0].payload = abi.encodeCall(newTarget.doSmth, (42));

        uint256 newProposalId = 3;
        bytes memory newProposeCalldata = abi.encodeCall(
            timelock.schedule,
            (newProposalId, timelock.ADMIN_EXECUTOR(), newCalls)
        );

        bytes memory newScript = Utils.encodeEvmCallScript(address(timelock), newProposeCalldata);

        uint256 newVoteId = daoVoting.votesLength();

        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                address(daoVoting),
                abi.encodeCall(daoVoting.newVote, (newScript, "", false, false))
            )
        );
        Utils.supportVoteAndWaitTillDecided(newVoteId, ldoWhale);

        // execute the vote
        assertEq(IAragonVoting(DAO_VOTING).canExecute(newVoteId), true);
        daoVoting.executeVote(newVoteId);

        // wait timelock duration passes
        vm.warp(block.timestamp + timelockDuration + 1);
        ScheduledExecutorCallsBatch memory newCallsBatch = timelock.getScheduledCalls(
            newProposalId
        );
        assertTrue(newCallsBatch.executableAfter < block.timestamp);

        // execute new proposal by emergency committee

        vm.expectCall(address(newTarget), newCalls[0].payload);
        newTarget.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));

        vm.prank(vetoMultisig);
        timelock.execute(newProposalId);

        // now committee may exit the emergency mode
        vm.prank(vetoMultisig);
        timelock.exitEmergencyMode();

        (isEmergencyModeActive, , ) = timelock.getEmergencyModeState();

        assertFalse(isEmergencyModeActive);
        assertEq(timelock.getEmergencyCommittee(), address(0));

        // malicious proposal was canceled and may be removed
        timelock.removeCanceledCalls(maliciousProposalId);
    }
}
