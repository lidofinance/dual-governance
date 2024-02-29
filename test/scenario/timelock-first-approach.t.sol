// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Escrow} from "contracts/Escrow.sol";
import {GateSeal} from "contracts/GateSeal.sol";
import {BurnerVault} from "contracts/BurnerVault.sol";
import {OwnableExecutor} from "contracts/OwnableExecutor.sol";
import {Configuration} from "contracts/DualGovernanceConfiguration.sol";
import {Proposals, Proposal, ProposalStatus} from "contracts/libraries/Proposals.sol";

import {
    Timelock,
    ExecutorCall,
    EmergencyState,
    EmergencyProtection,
    DualGovernanceTimelockController,
    DualGovernanceStatus
} from "contracts/TimelockFirstApproachScratchpad.sol";

import {Utils, TargetMock} from "../utils/utils.sol";
import {ExecutorCallHelpers} from "../utils/executor-calls.sol";
import {IWithdrawalQueue, IERC20} from "../utils/interfaces.sol";
import {DAO_AGENT, DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER} from "../utils/mainnet-addresses.sol";

interface IDangerousContract {
    function doRegularStaff(uint256 magic) external;
    function doRugPool() external;
    function doControversialStaff() external;
}

contract TimelockFirstApproachTest is Test {
    uint256 private immutable _MIN_DELAY_DURATION = 1 days;
    uint256 private immutable _MAX_DELAY_DURATION = 30 days;

    uint256 private immutable _AFTER_PROPOSE_DELAY = 3 days;
    uint256 private immutable _AFTER_SCHEDULE_DELAY = 2 days;

    uint256 private immutable _EMERGENCY_MODE_DURATION = 180 days;
    uint256 private immutable _EMERGENCY_PROTECTION_DURATION = 90 days;
    address private immutable _EMERGENCY_COMMITTEE = makeAddr("EMERGENCY_COMMITTEE");

    uint256 private immutable _SEALING_DURATION = 14 days;
    uint256 private immutable _SEALING_COMMITTEE_LIFETIME = 365 days;
    address private immutable _SEALING_COMMITTEE = makeAddr("SEALING_COMMITTEE");

    address internal immutable _TIEBREAK_COMMITTEE = makeAddr("TIEBREAK_COMMITTEE");

    address[] private _sealableWithdrawalBlockers = [WITHDRAWAL_QUEUE];

    TargetMock private _target;
    GateSeal private _gateSeal;
    Timelock internal _timelock;
    DualGovernanceTimelockController internal _controller;
    Configuration internal _config;

    function setUp() external {
        Utils.selectFork();

        _target = new TargetMock();

        // deploy admin executor
        OwnableExecutor adminExecutor = new OwnableExecutor(address(this));

        // deploy configuration implementation
        Configuration configImpl = new Configuration(address(adminExecutor), DAO_VOTING, _sealableWithdrawalBlockers);
        TransparentUpgradeableProxy configProxy =
            new TransparentUpgradeableProxy(address(configImpl), address(this), new bytes(0));
        _config = Configuration(address(configProxy));

        _timelock = new Timelock(
            address(_config),
            DAO_VOTING,
            _MIN_DELAY_DURATION,
            _MAX_DELAY_DURATION,
            _AFTER_PROPOSE_DELAY,
            _AFTER_SCHEDULE_DELAY
        );

        // setup emergency protection
        adminExecutor.execute(
            address(_timelock),
            0,
            abi.encodeCall(
                _timelock.setEmergencyProtection,
                (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, _EMERGENCY_MODE_DURATION)
            )
        );

        adminExecutor.transferOwnership(address(_timelock));
    }

    function testFork_ProofOfConcept() external {
        bytes memory regularStaffCalldata = abi.encodeCall(IDangerousContract.doRegularStaff, (42));
        ExecutorCall[] memory regularStaffCalls = ExecutorCallHelpers.create(address(_target), regularStaffCalldata);

        // ---
        // ACT 1. 📈 DAO OPERATES AS USUALLY
        // ---
        {
            uint256 proposalId = _submitProposal(
                "DAO does regular staff on potentially dangerous contract", _config.ADMIN_EXECUTOR(), regularStaffCalls
            );

            // wait until scheduled call becomes executable
            _waitFor(proposalId);

            // call successfully executed
            _timelock.executeScheduled(proposalId);
            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);
        }

        // ---
        // ACT 2. 😱 DAO IS UNDER ATTACK
        // ---
        uint256 maliciousProposalId;
        EmergencyState memory emergencyState;
        {
            // Malicious vote was proposed by the attacker with huge LDO wad (but still not the majority)
            ExecutorCall[] memory maliciousCalls =
                ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()));

            maliciousProposalId = _submitProposal("Rug Pool attempt", _config.ADMIN_EXECUTOR(), maliciousCalls);

            // the call isn't executable until the delay has passed
            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));

            // some time required to assemble the emergency committee and activate emergency mode
            vm.warp(block.timestamp + _AFTER_PROPOSE_DELAY / 2);

            // malicious call still not executable
            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));

            vm.expectRevert(Timelock.UnscheduledExecutionForbidden.selector);
            _timelock.executeSubmitted(maliciousProposalId);

            vm.expectRevert(
                abi.encodeWithSelector(
                    Proposals.InvalidProposalStatus.selector, ProposalStatus.Submitted, ProposalStatus.Scheduled
                )
            );
            _timelock.executeScheduled(maliciousProposalId);

            // emergency committee activates emergency mode
            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyActivate();

            // emergency mode was successfully activated
            uint256 expectedEmergencyModeEndTimestamp = block.timestamp + _EMERGENCY_MODE_DURATION;
            emergencyState = _timelock.getEmergencyState();
            assertTrue(emergencyState.isEmergencyModeActivated);
            assertEq(emergencyState.emergencyModeEndsAfter, expectedEmergencyModeEndTimestamp);

            // now only emergency committee may execute scheduled calls
            vm.warp(block.timestamp + _AFTER_PROPOSE_DELAY / 2 + 1);

            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));

            vm.expectRevert(Timelock.UnscheduledExecutionForbidden.selector);
            _timelock.executeSubmitted(maliciousProposalId);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _timelock.executeScheduled(maliciousProposalId);
        }

        // ---
        // ACT 3. 🔫 DAO STRIKES BACK (WITH DUAL GOVERNANCE SHIPMENT)
        // ---
        {
            // Lido contributors work hard to implement and ship the Dual Governance mechanism
            // before the emergency mode is over
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);

            // Time passes but malicious proposal still on hold
            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));

            // Dual Governance timelock is deployed into mainnet
            _controller = _deployDualGovernanceTimelockController();

            ExecutorCall[] memory dualGovernanceLaunchCalls = ExecutorCallHelpers.create(
                address(_timelock),
                [
                    abi.encodeCall(_timelock.setController, (address(_controller))),
                    abi.encodeCall(_timelock.emergencyDeactivate, ()),
                    abi.encodeCall(
                        _timelock.setEmergencyProtection,
                        (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, _EMERGENCY_MODE_DURATION)
                    ),
                    abi.encodeCall(_timelock.setTiebreakCommittee, (_TIEBREAK_COMMITTEE))
                ]
            );

            // The vote to launch Dual Governance is launched and reached the quorum (the major part of LDO holder still have power)
            uint256 dualGovernanceLunchProposalId =
                _submitProposal("Launch the Dual Governance", _config.ADMIN_EXECUTOR(), dualGovernanceLaunchCalls);

            vm.warp(block.timestamp + _AFTER_PROPOSE_DELAY + 1);

            // Emergency Committee executes vote and enables Dual Governance
            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyExecute(dualGovernanceLunchProposalId);

            // Time passes but malicious proposal still on hold
            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));
        }

        // ---
        // ACT 4 - DUAL GOVERNANCE WORKS PROPERLY (VETO SIGNALING CASE)
        // ---
        {
            uint256 snapshotId = vm.snapshot();
            ExecutorCall[] memory controversialCalls = ExecutorCallHelpers.create(
                address(_target), abi.encodeCall(IDangerousContract.doControversialStaff, ())
            );

            uint256 controversialProposalId =
                _submitProposal("Do some controversial staff", _config.ADMIN_EXECUTOR(), controversialCalls);

            vm.warp(block.timestamp + _AFTER_PROPOSE_DELAY / 2);

            assertFalse(_timelock.canSchedule(controversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            // dual governance escrow accumulates
            address stEthWhale = makeAddr("STETH_WHALE");
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(stEthWhale, 5 * 10 ** 16);
            uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

            Escrow escrow = Escrow(payable(_controller.signallingEscrow()));
            vm.startPrank(stEthWhale);
            IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
            escrow.lockStEth(stEthWhaleBalance);
            vm.stopPrank();
            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.VetoSignalling));

            vm.warp(block.timestamp + _AFTER_PROPOSE_DELAY / 2 + 1);

            assertFalse(_timelock.canSchedule(controversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            // wait the dual governance returns to normal state
            vm.warp(block.timestamp + 14 days);
            _controller.activateNextState();
            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.VetoSignallingDeactivation));

            vm.warp(block.timestamp + _config.SIGNALLING_DEACTIVATION_DURATION() + 1);

            _controller.activateNextState();
            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.VetoCooldown));

            assertTrue(_timelock.canSchedule(controversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            _timelock.schedule(controversialProposalId);
            vm.warp(block.timestamp + _AFTER_SCHEDULE_DELAY + 1);

            assertFalse(_timelock.canSchedule(controversialProposalId));
            assertTrue(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            // execute controversial decision
            _timelock.executeScheduled(controversialProposalId);
            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), controversialCalls);
            vm.revertTo(snapshotId);
        }

        // ---
        // ACT 5. RESET TIMELOCK CONTROLLER
        // ---
        {
            uint256 snapshotId = vm.snapshot();
            assertEq(_timelock.getController(), address(_controller));

            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyActivate();

            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyReset();

            assertEq(_timelock.getController(), address(0));
            assertFalse(_timelock.isEmergencyProtectionEnabled());

            vm.revertTo(snapshotId);
        }

        // ---
        // ACT 6. TIEBREAK COMMITTEE FLOW
        // ---
        {
            uint256 snapshotId = vm.snapshot();
            _gateSeal = _deployGateSeal(address(_controller));

            // some regular proposal is launched
            uint256 proposalId = _submitProposal(
                "DAO does regular staff on potentially dangerous contract", _config.ADMIN_EXECUTOR(), regularStaffCalls
            );

            address stEthWhale = makeAddr("STETH_WHALE");
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(stEthWhale, 20 * 10 ** 16);
            uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

            Escrow escrow = Escrow(payable(_controller.signallingEscrow()));
            vm.startPrank(stEthWhale);
            IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
            escrow.lockStEth(stEthWhaleBalance);
            vm.stopPrank();
            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.VetoSignalling));

            // before the RageQuit phase is entered tiebreak committee can't execute decisions
            vm.prank(_TIEBREAK_COMMITTEE);
            vm.expectRevert(Timelock.ControllerNotLocked.selector);
            _timelock.tiebreakExecute(proposalId);

            vm.warp(block.timestamp + _config.SIGNALING_MAX_DURATION() + 1);

            _controller.activateNextState();
            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.RageQuit));

            // activate gate seal to enter deadlock
            vm.prank(_SEALING_COMMITTEE);
            _gateSeal.seal(_sealableWithdrawalBlockers);

            // the dual governance is blocked
            assertTrue(_controller.isBlocked());

            // proposal is not executable
            assertFalse(_timelock.canSchedule(proposalId));
            assertFalse(_timelock.canExecuteSubmitted(proposalId));

            // now tiebreak committee may execute any dao decision
            vm.prank(_TIEBREAK_COMMITTEE);
            _timelock.tiebreakExecute(proposalId);
            _assertTargetMockCalls(_config.ADMIN_EXECUTOR(), regularStaffCalls);

            vm.revertTo(snapshotId);
        }

        // ---
        // ACT 7. CANCEL ALL PROPOSALS
        // ---
        {
            uint256 snapshotId = vm.snapshot();
            ExecutorCall[] memory controversialCalls = ExecutorCallHelpers.create(
                address(_target), abi.encodeCall(IDangerousContract.doControversialStaff, ())
            );

            uint256 controversialProposalId =
                _submitProposal("Do some controversial staff", _config.ADMIN_EXECUTOR(), controversialCalls);

            vm.warp(block.timestamp + _AFTER_PROPOSE_DELAY / 2);

            assertFalse(_timelock.canSchedule(controversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            // dual governance escrow accumulates
            address stEthWhale = makeAddr("STETH_WHALE");
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(stEthWhale, 5 * 10 ** 16);
            uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

            Escrow escrow = Escrow(payable(_controller.signallingEscrow()));
            vm.startPrank(stEthWhale);
            IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
            escrow.lockStEth(stEthWhaleBalance);
            vm.stopPrank();
            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.VetoSignalling));

            vm.warp(block.timestamp + _AFTER_PROPOSE_DELAY / 2 + 1);

            assertFalse(_timelock.canSchedule(controversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            // dao decides to cancel all pending proposals
            uint256 cancelAllVoteId = Utils.adoptVote(
                DAO_VOTING,
                "Cancel all proposals",
                Utils.encodeEvmCallScript(address(_timelock), abi.encodeCall(_timelock.cancelAll, ()))
            );
            Utils.executeVote(DAO_VOTING, cancelAllVoteId);

            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.VetoSignallingHalted));

            // new proposal sent later can't be submitted until the veto signaling is exited

            bytes memory script =
                Utils.encodeEvmCallScript(address(_timelock), abi.encodeCall(_timelock.submit, (controversialCalls)));
            uint256 voteId = Utils.adoptVote(DAO_VOTING, "Another controversial vote", script);

            vm.expectRevert(DualGovernanceTimelockController.ProposalsCreationSuspended.selector);
            Utils.executeVote(DAO_VOTING, voteId);

            // wait the dual governance returns to normal state
            vm.warp(block.timestamp + 14 days);
            _controller.activateNextState();
            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.VetoSignallingDeactivation));
            vm.warp(block.timestamp + _config.SIGNALLING_DEACTIVATION_DURATION() + 1);
            _controller.activateNextState();
            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.VetoCooldown));

            // stETH holders unlock their funds from escrow
            vm.startPrank(stEthWhale);
            escrow.unlockStEth();

            assertFalse(_timelock.canSchedule(controversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            // wait until veto cooldown is passed
            vm.warp(block.timestamp + _config.SIGNALING_COOLDOWN_DURATION() + 1);
            _controller.activateNextState();
            assertEq(uint256(_controller.currentState()), uint256(DualGovernanceStatus.Normal));

            // previous malicious proposal may be submitted now
            Utils.executeVote(DAO_VOTING, voteId);
            uint256 anotherControversialProposalId = _timelock.getProposalsCount();

            assertFalse(_timelock.canSchedule(anotherControversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(anotherControversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(anotherControversialProposalId));

            // and scheduled later
            vm.warp(block.timestamp + _AFTER_PROPOSE_DELAY + 1);

            assertTrue(_timelock.canSchedule(anotherControversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(anotherControversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(anotherControversialProposalId));

            vm.revertTo(snapshotId);
        }
    }

    function _submitProposal(
        string memory description,
        address executor,
        ExecutorCall[] memory calls
    ) internal returns (uint256 proposalId) {
        uint256 proposalsCountBefore = _timelock.getProposalsCount();

        bytes memory script = Utils.encodeEvmCallScript(address(_timelock), abi.encodeCall(_timelock.submit, (calls)));
        uint256 voteId = Utils.adoptVote(DAO_VOTING, description, script);

        // The scheduled calls count is the same until the vote is enacted
        assertEq(_timelock.getProposalsCount(), proposalsCountBefore);

        // executing the vote
        Utils.executeVote(DAO_VOTING, voteId);

        proposalId = _timelock.getProposalsCount();
        // new call is scheduled but has not executable yet
        assertEq(proposalId, proposalsCountBefore + 1);
        _assertSubmittedProposal(proposalId, executor, calls);
    }

    function _assertSubmittedProposal(uint256 proposalId, address executor, ExecutorCall[] memory calls) internal {
        Proposal memory proposal = _timelock.getProposal(proposalId);
        assertEq(proposal.id, proposalId, "unexpected proposal id");
        // assertFalse(proposal.isCanceled, "proposal is canceled");
        assertEq(proposal.executor, executor, "unexpected executor");
        assertEq(proposal.proposedAt, block.timestamp, "unexpected scheduledAt");
        assertEq(proposal.executedAt, 0, "unexpected executedAt");
        assertEq(proposal.calls.length, calls.length, "unexpected calls length");

        for (uint256 i = 0; i < proposal.calls.length; ++i) {
            ExecutorCall memory expected = calls[i];
            ExecutorCall memory actual = proposal.calls[i];

            assertEq(actual.value, expected.value);
            assertEq(actual.target, expected.target);
            assertEq(actual.payload, expected.payload);
        }
    }

    function _assertTargetMockCalls(address executor, ExecutorCall[] memory calls) internal {
        TargetMock.Call[] memory called = _target.getCalls();
        assertEq(called.length, calls.length);

        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(called[i].sender, executor);
            assertEq(called[i].value, calls[i].value);
            assertEq(called[i].data, calls[i].payload);
            assertEq(called[i].blockNumber, block.number);
        }
        _target.reset();
    }

    function _waitFor(uint256 proposalId) internal {
        // the call is not executable until the delay has passed
        assertFalse(_timelock.canSchedule(proposalId), "canSchedule() != false");
        assertFalse(_timelock.canExecuteSubmitted(proposalId), "canExecuteSubmitted() != false");
        assertFalse(_timelock.canExecuteScheduled(proposalId), "canExecuteScheduled() != false");

        // wait until proposed call becomes adoptable
        vm.warp(block.timestamp + _AFTER_PROPOSE_DELAY + 1);

        assertTrue(_timelock.canSchedule(proposalId), "canSchedule() != true");
        assertFalse(_timelock.canExecuteSubmitted(proposalId), "canExecuteSubmitted() != false");
        assertFalse(_timelock.canExecuteScheduled(proposalId), "canExecuteScheduled() != false");

        if (_timelock.getIsSchedulingEnabled()) {
            _timelock.schedule(proposalId);

            // wait until scheduled call become executable
            vm.warp(block.timestamp + _AFTER_SCHEDULE_DELAY + 1);
        }

        assertFalse(_timelock.canSchedule(proposalId), "canSchedule() != false");
        assertFalse(_timelock.canExecuteSubmitted(proposalId), "canExecuteSubmitted() != false");
        assertTrue(_timelock.canExecuteScheduled(proposalId), "canExecuteScheduled() != true");
    }

    function _deployDualGovernanceTimelockController() internal returns (DualGovernanceTimelockController controller) {
        BurnerVault burnerVault = new BurnerVault(BURNER, ST_ETH, WST_ETH);
        Escrow escrowMasterCopy = new Escrow(address(0), ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, address(burnerVault));
        controller =
            new DualGovernanceTimelockController(address(_timelock), address(escrowMasterCopy), address(_config));
    }

    function _deployGateSeal(address dualGovernance) internal returns (GateSeal gateSeal) {
        // deploy new gate seal instance
        gateSeal = new GateSeal(
            dualGovernance,
            _SEALING_COMMITTEE,
            _SEALING_COMMITTEE_LIFETIME,
            _SEALING_DURATION,
            _sealableWithdrawalBlockers
        );

        // grant rights to gate seal to pause/resume the withdrawal queue
        vm.startPrank(DAO_AGENT);
        IWithdrawalQueue(WITHDRAWAL_QUEUE).grantRole(IWithdrawalQueue(WITHDRAWAL_QUEUE).PAUSE_ROLE(), address(gateSeal));
        IWithdrawalQueue(WITHDRAWAL_QUEUE).grantRole(
            IWithdrawalQueue(WITHDRAWAL_QUEUE).RESUME_ROLE(), address(gateSeal)
        );
        vm.stopPrank();
    }
}
