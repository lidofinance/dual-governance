// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Escrow} from "contracts/Escrow.sol";
import {ProposalStatus} from "contracts/libraries/Proposals.sol";
import {
    Proposals,
    Proposal,
    EmergencyState,
    ControllerEnhancedTimelock,
    EmergencyProtection
} from "contracts/Timelock.sol";
import {ExecutorCall} from "contracts/interfaces/IExecutor.sol";
import {DualGovernanceStatus} from "contracts/DualGovernanceTimelockController.sol";

import {Test} from "forge-std/Test.sol";
import {
    DualGovernanceConfig, DualGovernanceDeployScript, DualGovernanceTimelockController
} from "script/Deploy2.s.sol";

import {Utils, TargetMock} from "../utils/utils.sol";
import {ExecutorCallHelpers} from "../utils/executor-calls.sol";
import {IERC20} from "../utils/interfaces.sol";
import {DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER} from "../utils/mainnet-addresses.sol";

interface IDangerousContract {
    function doRegularStaff(uint256 magic) external;
    function doRugPool() external;
    function doControversialStaff() external;
}

contract TimelockScenarioTest is Test {
    uint256 private immutable _MIN_DELAY_DURATION = 1 days;
    uint256 private immutable _MAX_DELAY_DURATION = 30 days;
    uint256 private immutable _ADOPTION_DELAY = 3 days;
    uint256 private immutable _EXECUTION_DELAY = 2 days;
    uint256 private immutable _EMERGENCY_MODE_DURATION = 180 days;
    uint256 private immutable _EMERGENCY_PROTECTION_DURATION = 90 days;
    address private immutable _EMERGENCY_COMMITTEE = makeAddr("EMERGENCY_COMMITTEE");

    TargetMock private _target;
    ControllerEnhancedTimelock private _timelock;
    DualGovernanceDeployScript private _deployScript;

    function setUp() external {
        Utils.selectFork();

        _target = new TargetMock();
        _deployScript = new DualGovernanceDeployScript(
            ST_ETH, WST_ETH, BURNER, DAO_VOTING, WITHDRAWAL_QUEUE, _MIN_DELAY_DURATION, _MAX_DELAY_DURATION
        );

        (_timelock,) = _deployScript.deployEmergencyProtectedTimelock(
            _ADOPTION_DELAY,
            _EXECUTION_DELAY,
            _EMERGENCY_COMMITTEE,
            _EMERGENCY_PROTECTION_DURATION,
            _EMERGENCY_MODE_DURATION
        );
    }

    function testFork_happyPath() external {
        bytes memory regularStaffCalldata = abi.encodeCall(IDangerousContract.doRegularStaff, (42));
        ExecutorCall[] memory regularStaffCalls = ExecutorCallHelpers.create(address(_target), regularStaffCalldata);

        // ---
        // ACT 1. WORK WITHOUT DUAL GOVERNANCE TIMELOCK CONTROLLER
        // ---
        {
            uint256 proposalId = _submitProposal(
                "DAO does regular staff on potentially dangerous contract",
                _timelock.getAdminExecutor(),
                regularStaffCalls
            );

            // wait until scheduled call becomes executable
            _waitFor(proposalId);

            // call successfully executed
            _timelock.executeScheduled(1);
            _assertTargetMockCalls(_timelock.getAdminExecutor(), regularStaffCalls);
        }

        // ---
        // ACT 2. DAO IS UNDER ATTACK
        // ---
        uint256 maliciousProposalId;
        EmergencyState memory emergencyState;
        {
            // Malicious vote was proposed by the attacker with huge LDO wad (but still not the majority)
            ExecutorCall[] memory maliciousCalls =
                ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()));

            maliciousProposalId = _submitProposal("Rug Pool attempt", _timelock.getAdminExecutor(), maliciousCalls);

            // the call isn't executable until the delay has passed
            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));

            // some time required to assemble the emergency committee and activate emergency mode
            vm.warp(block.timestamp + _ADOPTION_DELAY / 2);

            // malicious call still not executable
            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));

            vm.expectRevert(ControllerEnhancedTimelock.UnscheduledExecutionForbidden.selector);
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
            vm.warp(block.timestamp + _ADOPTION_DELAY / 2 + 1);

            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));

            vm.expectRevert(ControllerEnhancedTimelock.UnscheduledExecutionForbidden.selector);
            _timelock.executeSubmitted(maliciousProposalId);

            vm.expectRevert(EmergencyProtection.EmergencyModeActive.selector);
            _timelock.executeScheduled(maliciousProposalId);
        }

        // ---
        // ACT 3. DAO STRIKES BACK (WITH DUAL GOVERNANCE TIMELOCK CONTROLLER SHIPMENT)
        // ---
        DualGovernanceTimelockController controller;
        {
            // Lido contributors work hard to implement and ship the Dual Governance mechanism
            // before the emergency mode is over
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);

            // Time passes but malicious proposal still on hold
            assertFalse(_timelock.canSchedule(maliciousProposalId));
            assertFalse(_timelock.canExecuteScheduled(maliciousProposalId));
            assertFalse(_timelock.canExecuteSubmitted(maliciousProposalId));

            controller = _deployDualGovernanceTimelockController();

            ExecutorCall[] memory dualGovernanceLaunchCalls = ExecutorCallHelpers.create(
                address(_timelock),
                [
                    abi.encodeCall(_timelock.setController, (address(controller))),
                    abi.encodeCall(_timelock.emergencyDeactivate, ()),
                    abi.encodeCall(
                        _timelock.setEmergencyProtection,
                        (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, _EMERGENCY_MODE_DURATION)
                    )
                ]
            );

            uint256 dualGovernanceLunchProposalId =
                _submitProposal("Launch the Dual Governance", _timelock.getAdminExecutor(), dualGovernanceLaunchCalls);

            vm.warp(block.timestamp + _ADOPTION_DELAY + 1);

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
                _submitProposal("Do some controversial staff", _timelock.getAdminExecutor(), controversialCalls);

            vm.warp(block.timestamp + _ADOPTION_DELAY / 2);

            assertFalse(_timelock.canSchedule(controversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            // dual governance escrow accumulates
            address stEthWhale = makeAddr("STETH_WHALE");
            Utils.removeLidoStakingLimit();
            Utils.setupStEthWhale(stEthWhale, 5 * 10 ** 16);
            uint256 stEthWhaleBalance = IERC20(ST_ETH).balanceOf(stEthWhale);

            Escrow escrow = Escrow(payable(controller.signalingEscrow()));
            vm.startPrank(stEthWhale);
            IERC20(ST_ETH).approve(address(escrow), stEthWhaleBalance);
            escrow.lockStEth(stEthWhaleBalance);
            vm.stopPrank();
            assertEq(uint256(controller.currentState()), uint256(DualGovernanceStatus.VetoSignalling));

            vm.warp(block.timestamp + _ADOPTION_DELAY / 2 + 1);

            assertFalse(_timelock.canSchedule(controversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            // wait the dual governance returns to normal state
            vm.warp(block.timestamp + 14 days);
            controller.activateNextState();
            assertEq(uint256(controller.currentState()), uint256(DualGovernanceStatus.VetoSignallingDeactivation));

            DualGovernanceConfig memory config = controller.config();
            vm.warp(block.timestamp + config.signalingDeactivationDuration + 1);

            controller.activateNextState();
            assertEq(uint256(controller.currentState()), uint256(DualGovernanceStatus.VetoCooldown));

            assertTrue(_timelock.canSchedule(controversialProposalId));
            assertFalse(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            _timelock.schedule(controversialProposalId);
            vm.warp(block.timestamp + _EXECUTION_DELAY + 1);

            assertFalse(_timelock.canSchedule(controversialProposalId));
            assertTrue(_timelock.canExecuteScheduled(controversialProposalId));
            assertFalse(_timelock.canExecuteSubmitted(controversialProposalId));

            // execute controversial decision
            _timelock.executeScheduled(controversialProposalId);
            _assertTargetMockCalls(_timelock.getAdminExecutor(), controversialCalls);
            vm.revertTo(snapshotId);
        }

        // ---
        // ACT 5. RESET TIMELOCK CONTROLLER
        // ---
        {
            uint256 snapshotId = vm.snapshot();
            assertEq(_timelock.getController(), address(controller));

            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyActivate();

            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyResetController();

            assertEq(_timelock.getController(), address(0));
            assertFalse(_timelock.isEmergencyProtectionEnabled());

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
        vm.warp(block.timestamp + _ADOPTION_DELAY + 1);

        assertTrue(_timelock.canSchedule(proposalId), "canSchedule() != true");
        assertFalse(_timelock.canExecuteSubmitted(proposalId), "canExecuteSubmitted() != false");
        assertFalse(_timelock.canExecuteScheduled(proposalId), "canExecuteScheduled() != false");

        if (_timelock.getIsSchedulingEnabled()) {
            _timelock.schedule(proposalId);

            // wait until scheduled call become executable
            vm.warp(block.timestamp + _EXECUTION_DELAY + 1);
        }

        assertFalse(_timelock.canSchedule(proposalId), "canSchedule() != false");
        assertFalse(_timelock.canExecuteSubmitted(proposalId), "canExecuteSubmitted() != false");
        assertTrue(_timelock.canExecuteScheduled(proposalId), "canExecuteScheduled() != true");
    }

    function _deployDualGovernanceTimelockController() internal returns (DualGovernanceTimelockController controller) {
        DualGovernanceConfig memory config = DualGovernanceConfig({
            firstSealThreshold: 3 * 10 ** 16,
            secondSealThreshold: 15 * 10 ** 16,
            signalingMaxDuration: 30 days,
            signalingMinDuration: 3 days,
            signalingCooldownDuration: 4 days,
            signalingDeactivationDuration: 5 days,
            tiebreakActivationTimeout: 365 days
        });
        controller = _deployScript.deployDualGovernanceTimelockController(address(_timelock), config);
    }
}
