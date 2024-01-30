// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Configuration} from "contracts/Configuration.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {TransparentUpgradeableProxy} from "contracts/TransparentUpgradeableProxy.sol";

import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {EmergencyProtectedTimelock, ExecutorCall, ScheduledExecutorCallsBatch, ScheduledCalls, EmergencyProtection} from "contracts/EmergencyProtectedTimelock.sol";

import "forge-std/Test.sol";

import "../utils/mainnet-addresses.sol";
import "../utils/interfaces.sol";
import "../utils/utils.sol";

contract DualGovernanceDeployFactory {
    address immutable STETH;
    address immutable WSTETH;
    address immutable WQ;

    constructor(address stETH, address wstETH, address withdrawalQueue) {
        STETH = stETH;
        WSTETH = wstETH;
        WQ = withdrawalQueue;
    }

    function deployDualGovernance(address timelock) external returns (DualGovernance dualGov) {
        // deploy initial config impl
        address configImpl = address(new Configuration(DAO_VOTING));

        // deploy config proxy
        ProxyAdmin configAdmin = new ProxyAdmin(address(this));
        TransparentUpgradeableProxy config = new TransparentUpgradeableProxy(
            configImpl,
            address(configAdmin),
            new bytes(0)
        );

        // deploy DG
        address escrowImpl = address(
            new Escrow(address(config), ST_ETH, WST_ETH, WITHDRAWAL_QUEUE)
        );
        dualGov = new DualGovernance(
            address(config),
            configImpl,
            address(configAdmin),
            escrowImpl,
            timelock
        );

        configAdmin.transferOwnership(address(dualGov));
    }
}

abstract contract PlanBSetup is Test {
    function deployPlanB(
        address daoVoting,
        uint256 timelockDuration,
        address vetoMultisig,
        uint256 vetoMultisigActiveFor,
        uint256 emergencyModeDuration
    ) public returns (EmergencyProtectedTimelock timelock) {
        OwnableExecutor adminExecutor = new OwnableExecutor(address(this));

        timelock = new EmergencyProtectedTimelock(address(adminExecutor), daoVoting);

        // configure Timelock
        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(timelock.setGovernance, (daoVoting, timelockDuration))
        );

        adminExecutor.execute(
            address(timelock),
            0,
            abi.encodeCall(
                timelock.setEmergencyProtection,
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
    uint256 internal _emergencyModeDuration;

    function setUp() external {
        Utils.selectFork();

        ldoWhale = makeAddr("ldo_whale");
        Utils.setupLdoWhale(ldoWhale);

        vetoMultisig = makeAddr("vetoMultisig");

        timelockDuration = 1 days;
        vetoMultisigActiveFor = 90 days;
        _emergencyModeDuration = 180 days;

        timelock = deployPlanB(
            DAO_VOTING,
            timelockDuration,
            vetoMultisig,
            vetoMultisigActiveFor,
            _emergencyModeDuration
        );
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
            timelock.forward,
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

        // no calls to execute before the vote is enacted
        assertEq(timelock.getScheduledCallBatchesCount(), 0);

        // executing the vote
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);
        daoVoting.executeVote(voteId);

        // new call is scheduled but has not executable yet
        assertEq(timelock.getScheduledCallBatchesCount(), 1);
        assertFalse(timelock.getIsExecutable(proposalId));

        // wait until call becomes executable
        vm.warp(block.timestamp + timelockDuration + 1);
        assertTrue(timelock.getIsExecutable(proposalId));

        // call successfully executed
        vm.expectCall(address(target), targetCalldata);
        target.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));
        timelock.execute(proposalId);

        // scheduled call was removed after execution
        assertEq(timelock.getScheduledCallBatchesCount(), 0);

        // malicious vote was proposed and passed
        voteId = daoVoting.votesLength();

        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(newVoteScript);
        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);
        daoVoting.executeVote(voteId);

        // malicious call was scheduled
        assertEq(timelock.getScheduledCallBatchesCount(), 1);

        // emergency committee activates emergency mode during the timelock duration
        vm.prank(vetoMultisig);
        timelock.emergencyModeActivate();

        EmergencyProtectedTimelock.EmergencyState memory emergencyState = timelock
            .getEmergencyState();
        assertTrue(emergencyState.isActive);
        assertEq(
            emergencyState.emergencyModeEndsAfter,
            block.timestamp + emergencyState.emergencyModeDuration
        );
        assertEq(emergencyState.emergencyModeDuration, _emergencyModeDuration);

        // now, only emergency committee may execute calls on timelock
        vm.warp(block.timestamp + timelockDuration + 1);
        uint256 maliciousProposalId = 1;

        // malicious proposal can be executed now, but in emergency mode, only by the committee
        assertTrue(timelock.getIsExecutable(maliciousProposalId));

        // attempt to execute malicious proposal not from committee fails
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyProtection.NotEmergencyCommittee.selector,
                address(this)
            )
        );
        timelock.execute(maliciousProposalId);

        // Some time later, the DG development was finished and may be deployed
        vm.warp(block.timestamp + 30 days);

        DualGovernanceDeployFactory dgFactory = new DualGovernanceDeployFactory(
            ST_ETH,
            WST_ETH,
            WITHDRAWAL_QUEUE
        );

        DualGovernance dualGov = dgFactory.deployDualGovernance(address(timelock));

        // The vote to enable dual governance is prepared and launched

        ExecutorCall[] memory dualGovActivationCalls = new ExecutorCall[](2);
        // call timelock.setGovernance() with deployed instance of DG
        dualGovActivationCalls[0].target = address(timelock);
        dualGovActivationCalls[0].payload = abi.encodeCall(
            timelock.setGovernance,
            (address(dualGov), 1 days)
        );

        // call timelock.setEmergencyProtection() to update the emergency protection settings
        dualGovActivationCalls[1].target = address(timelock);
        dualGovActivationCalls[1].payload = abi.encodeCall(
            timelock.setEmergencyProtection,
            (vetoMultisig, 90 days, 30 days)
        );

        uint256 newProposalId = 3;
        bytes memory newProposeCalldata = abi.encodeCall(
            timelock.forward,
            (newProposalId, timelock.ADMIN_EXECUTOR(), dualGovActivationCalls)
        );

        bytes memory newScript = Utils.encodeEvmCallScript(address(timelock), newProposeCalldata);

        voteId = daoVoting.votesLength();

        // The quorum to activate the DG is reached among the honest LDO holders
        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                address(daoVoting),
                abi.encodeCall(daoVoting.newVote, (newScript, "Activate DG", false, false))
            )
        );
        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // The vote passed and may be enacted
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);
        daoVoting.executeVote(voteId);

        // call was scheduled successfully
        assertEq(timelock.getScheduledCallBatchesCount(), 2);

        // wait timelock duration passes
        vm.warp(block.timestamp + timelockDuration + 1);
        assertTrue(timelock.getIsExecutable(newProposalId));

        // execute new proposal by emergency committee
        vm.prank(vetoMultisig);
        timelock.execute(newProposalId);

        uint256 dgDeployedTimestamp = block.timestamp;

        // validate the governance and emergency protection was set correctly
        assertEq(timelock.getGovernance(), address(dualGov));

        emergencyState = timelock.getEmergencyState();
        assertTrue(emergencyState.isActive);
        assertEq(emergencyState.committee, vetoMultisig);
        assertEq(emergencyState.protectedTill, dgDeployedTimestamp + 90 days);
        assertEq(emergencyState.emergencyModeDuration, 30 days);

        // after execution only malicious proposal has left
        assertEq(timelock.getScheduledCallBatchesCount(), 1);

        // now committee may exit the emergency mode and clear stayed malicious calls
        vm.prank(vetoMultisig);
        timelock.emergencyModeDeactivate();

        emergencyState = timelock.getEmergencyState();
        // after the emergency mode deactivation, all other emergency protection settings
        // stays the same
        assertFalse(emergencyState.isActive);
        assertEq(emergencyState.committee, vetoMultisig);
        assertEq(emergencyState.protectedTill, dgDeployedTimestamp + 90 days);
        assertEq(emergencyState.emergencyModeDuration, 30 days);

        // malicious proposal was canceled and may be removed
        timelock.getIsCanceled(maliciousProposalId);
        timelock.removeCanceledCallsBatch(maliciousProposalId);

        // now, all votings passes via dual governance
        _testDualGovernanceWorks(dualGov);
        _testDualGovernanceRedeploy(dualGov);
    }

    function _testDualGovernanceWorks(DualGovernance dualGov) internal {
        ExecutorCall[] memory calls = new ExecutorCall[](1);
        calls[0].value = 0;
        calls[0].target = address(target);
        calls[0].payload = abi.encodeCall(target.doSmth, (43));

        bytes memory dgProposeCalldata = abi.encodeCall(dualGov.propose, calls);

        bytes memory dgProposeVoteScript = Utils.encodeEvmCallScript(
            address(dualGov),
            dgProposeCalldata
        );

        uint256 voteId = daoVoting.votesLength();

        // The quorum to activate the DG is reached among the honest LDO holders
        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                address(daoVoting),
                abi.encodeCall(
                    daoVoting.newVote,
                    (dgProposeVoteScript, "Propose via DG", false, false)
                )
            )
        );
        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // The vote passed and may be enacted
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);
        daoVoting.executeVote(voteId);

        // The vote was proposed to DG
        assertEq(dualGov.getProposalsCount(), 1);

        uint256 newProposalId = 1;

        // wait till the proposal may be executed
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock() + 1);

        // execute the proposal
        dualGov.execute(newProposalId);

        // the call must be scheduled to the timelock now
        assertEq(timelock.getScheduledCallBatchesCount(), 1);

        // but it's not executable now
        assertFalse(timelock.getIsExecutable(newProposalId));

        // wait the timelock duration
        vm.warp(block.timestamp + timelock.getDelay() + 1);

        // now call must be executable
        assertTrue(timelock.getIsExecutable(newProposalId));

        // executing the call
        vm.expectCall(address(target), calls[0].payload);
        target.expectCalledBy(address(timelock.ADMIN_EXECUTOR()));
        timelock.execute(newProposalId);

        // executed calls were removed from the scheduled
        assertEq(timelock.getScheduledCallBatchesCount(), 0);
    }

    function _testDualGovernanceRedeploy(DualGovernance dualGov) internal {
        // after some significant time dual governance update is prepared
        vm.warp(block.timestamp + 365 days);
        DualGovernanceDeployFactory newDgFactory = new DualGovernanceDeployFactory(
            ST_ETH,
            WST_ETH,
            WITHDRAWAL_QUEUE
        );
        DualGovernance newDg = newDgFactory.deployDualGovernance(address(timelock));

        // prepare vote to update the DG implementation and reset the emergency committee

        ExecutorCall[] memory newDualGovActivationCalls = new ExecutorCall[](2);
        // call timelock.setGovernance() with deployed instance of DG
        newDualGovActivationCalls[0].target = address(timelock);
        newDualGovActivationCalls[0].payload = abi.encodeCall(
            timelock.setGovernance,
            (address(newDg), 1 days)
        );

        // call timelock.setEmergencyProtection() to update the emergency protection settings
        newDualGovActivationCalls[1].target = address(timelock);
        newDualGovActivationCalls[1].payload = abi.encodeCall(
            timelock.setEmergencyProtection,
            (vetoMultisig, 90 days, 30 days)
        );

        uint256 newProposalId = 2;
        bytes memory newProposeCalldata = abi.encodeCall(
            dualGov.propose,
            (newDualGovActivationCalls)
        );

        bytes memory newScript = Utils.encodeEvmCallScript(address(dualGov), newProposeCalldata);

        uint256 voteId = daoVoting.votesLength();

        // The quorum to activate the DG is reached among the honest LDO holders
        vm.prank(ldoWhale);
        IAragonForwarder(DAO_TOKEN_MANAGER).forward(
            Utils.encodeEvmCallScript(
                address(daoVoting),
                abi.encodeCall(daoVoting.newVote, (newScript, "Redeploy DG", false, false))
            )
        );
        Utils.supportVoteAndWaitTillDecided(voteId, ldoWhale);

        // The vote passed and may be enacted
        assertEq(IAragonVoting(DAO_VOTING).canExecute(voteId), true);
        daoVoting.executeVote(voteId);

        // new proposal was successfully created
        assertEq(dualGov.getProposalsCount(), 2);

        // wait till the proposal may be executed
        vm.warp(block.timestamp + dualGov.CONFIG().minProposalExecutionTimelock() + 1);

        // execute the proposal
        dualGov.execute(newProposalId);

        // the call must be scheduled to the timelock now
        assertEq(timelock.getScheduledCallBatchesCount(), 1);

        // but it's not executable now
        assertFalse(timelock.getIsExecutable(newProposalId));

        // wait the timelock duration
        vm.warp(block.timestamp + timelock.getDelay() + 1);

        // now call must be executable
        assertTrue(timelock.getIsExecutable(newProposalId));
        timelock.execute(newProposalId);
        uint256 dgDeployedTimestamp = block.timestamp;

        // new dual gov instance must be attached to timelock now
        assertEq(timelock.getGovernance(), address(newDg));

        EmergencyProtectedTimelock.EmergencyState memory emergencyState = timelock
            .getEmergencyState();
        // after the emergency mode deactivation, all other emergency protection settings
        // stays the same
        assertFalse(emergencyState.isActive);
        assertEq(emergencyState.committee, vetoMultisig);
        assertEq(emergencyState.protectedTill, dgDeployedTimestamp + 90 days);
        assertEq(emergencyState.emergencyModeDuration, 30 days);
    }
}
