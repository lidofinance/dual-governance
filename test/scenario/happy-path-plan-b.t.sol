// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {Utils, TargetMock} from "../utils/utils.sol";
import {ExecutorCallHelpers, ExecutorCall} from "../utils/executor-calls.sol";
import {DAO_VOTING, ST_ETH, WST_ETH, WITHDRAWAL_QUEUE, BURNER} from "../utils/mainnet-addresses.sol";

import {
    EmergencyState,
    EmergencyProtection,
    ScheduledCallsBatch,
    ScheduledCallsBatches,
    EmergencyProtectedTimelock
} from "contracts/EmergencyProtectedTimelock.sol";

import {Proposals, Proposal} from "contracts/libraries/Proposals.sol";

import {DualGovernanceDeployScript, DualGovernance} from "script/Deploy.s.sol";

interface IDangerousContract {
    function doRegularStaff(uint256 magic) external;
    function doRugPool() external;
}

contract PlanBSetup is Test {
    uint256 private immutable _DELAY = 3 days;
    uint256 private immutable _EMERGENCY_MODE_DURATION = 180 days;
    uint256 private immutable _EMERGENCY_PROTECTION_DURATION = 90 days;
    address private immutable _EMERGENCY_COMMITTEE = makeAddr("EMERGENCY_COMMITTEE");

    TargetMock private _target;
    DualGovernance private _dualGovernance;
    EmergencyProtectedTimelock private _timelock;
    DualGovernanceDeployScript private _dualGovernanceDeployScript;

    function setUp() external {
        Utils.selectFork();
        _target = new TargetMock();

        _dualGovernanceDeployScript =
            new DualGovernanceDeployScript(ST_ETH, WST_ETH, BURNER, DAO_VOTING, WITHDRAWAL_QUEUE);

        (_timelock,) = _dualGovernanceDeployScript.deployEmergencyProtectedTimelock(
            _DELAY, _EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, _EMERGENCY_MODE_DURATION
        );
    }

    function testFork_PlanB_Scenario() external {
        bytes memory regularStaffCalldata = abi.encodeCall(IDangerousContract.doRegularStaff, (42));
        ExecutorCall[] memory regularStaffCalls = ExecutorCallHelpers.create(address(_target), regularStaffCalldata);

        // ---
        // ACT 1. 📈 DAO OPERATES AS USUALLY
        // ---
        {
            uint256 proposalId = 1;
            _scheduleViaVoting(
                proposalId,
                "DAO does regular staff on potentially dangerous contract",
                _timelock.ADMIN_EXECUTOR(),
                regularStaffCalls
            );

            // wait until scheduled call becomes executable
            _waitFor(proposalId);

            // call successfully executed
            _execute(proposalId);
            _assertTargetMockCalls(_timelock.ADMIN_EXECUTOR(), regularStaffCalls);
        }

        // ---
        // ACT 2. 😱 DAO IS UNDER ATTACK
        // ---
        uint256 maliciousProposalId = 666;
        EmergencyState memory emergencyState;
        {
            // Malicious vote was proposed by the attacker with huge LDO wad (but still not the majority)
            bytes memory maliciousStaffCalldata = abi.encodeCall(IDangerousContract.doRugPool, ());
            ExecutorCall[] memory maliciousCalls = ExecutorCallHelpers.create(address(_target), maliciousStaffCalldata);

            _scheduleViaVoting(maliciousProposalId, "Rug Pool attempt", _timelock.ADMIN_EXECUTOR(), maliciousCalls);

            // the call isn't executable until the delay has passed
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));

            // some time required to assemble the emergency committee and activate emergency mode
            vm.warp(block.timestamp + _DELAY / 2);

            // malicious call still not executable
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));
            vm.expectRevert(abi.encodeWithSelector(ScheduledCallsBatches.DelayNotExpired.selector, maliciousProposalId));
            _timelock.execute(maliciousProposalId);

            // emergency committee activates emergency mode
            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyModeActivate();

            // emergency mode was successfully activated
            uint256 expectedEmergencyModeEndTimestamp = block.timestamp + _EMERGENCY_MODE_DURATION;
            emergencyState = _timelock.getEmergencyState();
            assertTrue(emergencyState.isEmergencyModeActivated);
            assertEq(emergencyState.emergencyModeEndsAfter, expectedEmergencyModeEndTimestamp);

            // now only emergency committee may execute scheduled calls
            vm.warp(block.timestamp + _DELAY / 2 + 1);
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));
            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyCommittee.selector, address(this)));
            _timelock.execute(maliciousProposalId);
        }

        // ---
        // ACT 3. 🔫 DAO STRIKES BACK (WITH DUAL GOVERNANCE SHIPMENT)
        // ---
        {
            // Lido contributors work hard to implement and ship the Dual Governance mechanism
            // before the emergency mode is over
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);

            // Time passes but malicious proposal still on hold
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));

            // Dual Governance is deployed into mainnet
            _dualGovernance = _dualGovernanceDeployScript.deployDualGovernance(address(_timelock), DAO_VOTING);

            ExecutorCall[] memory dualGovernanceLaunchCalls = ExecutorCallHelpers.create(
                address(_timelock),
                [
                    // Only Dual Governance contract can call the Timelock contract
                    abi.encodeCall(_timelock.setGovernanceAndDelay, (address(_dualGovernance), _DELAY)),
                    // Now the emergency mode may be deactivated (all scheduled calls will be canceled)
                    abi.encodeCall(_timelock.emergencyModeDeactivate, ()),
                    // Setup emergency committee for some period of time until the Dual Governance is battle tested
                    abi.encodeCall(
                        _timelock.setEmergencyProtection, (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, 30 days)
                    )
                ]
            );

            // The vote to launch Dual Governance is launched and reached the quorum (the major part of LDO holder still have power)
            uint256 dualGovernanceLunchProposalId = 777;
            _scheduleViaVoting(
                dualGovernanceLunchProposalId,
                "Launch the Dual Governance",
                _timelock.ADMIN_EXECUTOR(),
                dualGovernanceLaunchCalls
            );

            // Anticipated vote will be executed soon...
            _waitFor(dualGovernanceLunchProposalId);

            // The malicious vote still on hold
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));

            // Emergency Committee executes vote and enables Dual Governance
            _execute(dualGovernanceLunchProposalId, _EMERGENCY_COMMITTEE);

            // the deployed configuration is correct
            assertEq(_timelock.getGovernance(), address(_dualGovernance));
            // and the malicious call was marked as cancelled
            assertTrue(_timelock.getIsCanceled(maliciousProposalId));
            // and can NEVER be executed
            assertFalse(_timelock.getIsExecutable(maliciousProposalId));

            // anyone can remove malicious calls batch now
            _timelock.removeCanceledCallsBatch(maliciousProposalId);
            assertEq(_timelock.getScheduledCallBatchesCount(), 0);
        }

        // ---
        // ACT 4. 🫡 EMERGENCY COMMITTEE DISBANDED
        // ---
        {
            // Time passes and there were no vulnerabilities reported. Emergency Committee may be dissolved now
            // Thank you for your service, sirs!

            ExecutorCall[] memory disbandEmergencyCommitteeCalls = ExecutorCallHelpers.create(
                address(_timelock),
                [
                    // disable emergency protection
                    abi.encodeCall(_timelock.setEmergencyProtection, (address(0), 0, 0)),
                    // turn off the scheduling and allow calls relaying
                    abi.encodeCall(_timelock.setDelay, (0))
                ]
            );

            uint256 disbandEmergencyCommitteeProposalId =
                _propose("Disband Emergency Committee & turn off the calls delaying", disbandEmergencyCommitteeCalls);

            // until the DG timelock has passed the proposal can't be scheduled
            vm.expectRevert(
                abi.encodeWithSelector(Proposals.ProposalNotExecutable.selector, disbandEmergencyCommitteeProposalId)
            );
            _dualGovernance.schedule(disbandEmergencyCommitteeProposalId);

            // wait until the proposal is executable
            vm.warp(block.timestamp + _dualGovernance.CONFIG().minProposalExecutionTimelock() + 1);

            // schedule the proposal
            _scheduleViaDualGovernance(
                disbandEmergencyCommitteeProposalId, _timelock.ADMIN_EXECUTOR(), disbandEmergencyCommitteeCalls
            );

            // wait until the calls batch is executable
            _waitFor(disbandEmergencyCommitteeProposalId);

            // execute the proposal
            _execute(disbandEmergencyCommitteeProposalId);

            // validate the proposal was applied correctly:

            //   - emergency protection disabled
            emergencyState = _timelock.getEmergencyState();
            assertEq(emergencyState.committee, address(0));
            assertFalse(emergencyState.isEmergencyModeActivated);
            assertEq(emergencyState.emergencyModeDuration, 0);
            assertEq(emergencyState.emergencyModeEndsAfter, 0);

            //  - delay was set to 0
            assertEq(_timelock.getDelay(), 0);
        }

        // ---
        // ACT 5. 📆 DAO CONTINUES THEIR REGULAR DUTIES (PROTECTED BY DUAL GOVERNANCE)
        // ---
        {
            uint256 regularStaffProposalId = _propose("Make regular staff with help of DG", regularStaffCalls);

            // wait until the proposal is executable
            vm.warp(block.timestamp + _dualGovernance.CONFIG().minProposalExecutionTimelock() + 1);

            // scheduling is disabled after delay set to 0, so schedule call expectedly fails
            vm.expectRevert(ScheduledCallsBatches.SchedulingDisabled.selector);
            _dualGovernance.schedule(regularStaffProposalId);

            // Use relay method to execute the proposal
            _relayViaDualGovernance(regularStaffProposalId);

            // validate the proposal was executed correctly
            _assertTargetMockCalls(_timelock.ADMIN_EXECUTOR(), regularStaffCalls);
        }

        // ---
        // ACT 6. 🔜 NEW DUAL GOVERNANCE VERSION IS COMING
        // ---
        {
            // some time later, the major Dual Governance update release is ready to be launched
            vm.warp(block.timestamp + 365 days);
            DualGovernance dualGovernanceV2 =
                _dualGovernanceDeployScript.deployDualGovernance(address(_timelock), DAO_VOTING);

            ExecutorCall[] memory dualGovernanceUpdateCalls = ExecutorCallHelpers.create(
                address(_timelock),
                [
                    // Update the governance in the Timelock
                    abi.encodeCall(_timelock.setGovernanceAndDelay, (address(dualGovernanceV2), _DELAY)),
                    // Assembly the emergency committee again, until the new version of Dual Governance is battle tested
                    abi.encodeCall(
                        _timelock.setEmergencyProtection, (_EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, 30 days)
                    )
                ]
            );

            uint256 updateDualGovernanceProposalId = _propose("Update Dual Governance to V2", dualGovernanceUpdateCalls);

            // wait until the proposal is executable
            vm.warp(block.timestamp + _dualGovernance.CONFIG().minProposalExecutionTimelock() + 1);

            // relay the proposal
            _relayViaDualGovernance(updateDualGovernanceProposalId);

            // validate the proposal was applied correctly:

            // new version of dual governance attached to timelock
            assertEq(_timelock.getGovernance(), address(dualGovernanceV2));

            //   - emergency protection disabled
            emergencyState = _timelock.getEmergencyState();
            assertEq(emergencyState.committee, _EMERGENCY_COMMITTEE);
            assertFalse(emergencyState.isEmergencyModeActivated);
            assertEq(emergencyState.emergencyModeDuration, 30 days);
            assertEq(emergencyState.emergencyModeEndsAfter, 0);

            //  - delay was set correctly
            assertEq(_timelock.getDelay(), _DELAY);

            // use the new version of the dual governance in the future calls
            _dualGovernance = dualGovernanceV2;
        }

        // ---
        // ACT 7. 📆 DAO CONTINUES THEIR REGULAR DUTIES (PROTECTED BY DUAL GOVERNANCE V2)
        // ---
        {
            uint256 regularStaffProposalId = _propose("Make regular staff with help of DG V2", regularStaffCalls);

            // wait until the proposal is executable
            vm.warp(block.timestamp + _dualGovernance.CONFIG().minProposalExecutionTimelock() + 1);

            // the timelock emergency protection is enabled, so schedule calls instead of relaying
            _scheduleViaDualGovernance(regularStaffProposalId, _timelock.ADMIN_EXECUTOR(), regularStaffCalls);

            // wait until the proposal is executable
            _waitFor(regularStaffProposalId);

            // execute scheduled calls
            _execute(regularStaffProposalId);

            // validate the proposal was executed correctly
            _assertTargetMockCalls(_timelock.ADMIN_EXECUTOR(), regularStaffCalls);
        }
    }

    function testFork_ScheduledCallsCantBeExecutedAfterEmergencyModeDeactivation() external {
        uint256 maliciousProposalId = 666;
        ExecutorCall[] memory maliciousCalls =
            ExecutorCallHelpers.create(address(_target), abi.encodeCall(IDangerousContract.doRugPool, ()));
        // schedule some malicious call
        {
            _scheduleViaVoting(maliciousProposalId, "Rug Pool attempt", _timelock.ADMIN_EXECUTOR(), maliciousCalls);

            // call can't be executed before the delay is passed
            vm.expectRevert(abi.encodeWithSelector(ScheduledCallsBatches.DelayNotExpired.selector, maliciousProposalId));
            _timelock.execute(maliciousProposalId);
        }

        // activate emergency mode
        EmergencyState memory emergencyState;
        {
            vm.warp(block.timestamp + _DELAY / 2);

            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyModeActivate();

            emergencyState = _timelock.getEmergencyState();
            assertTrue(emergencyState.isEmergencyModeActivated);
        }

        // delay for malicious proposal has passed, but it can't be executed because of emergency mode was activated
        {
            vm.warp(block.timestamp + _DELAY / 2 + 1);
            ScheduledCallsBatch memory batch = _timelock.getScheduledCallsBatch(maliciousProposalId);
            assertTrue(block.timestamp > batch.executableAfter);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyCommittee.selector, address(this)));
            _timelock.execute(maliciousProposalId);
        }

        // another malicious call is scheduled during the emergency mode also can't be executed
        uint256 maliciousProposalId2 = 667;
        {
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);
            // emergency mode still active
            assertTrue(emergencyState.emergencyModeEndsAfter > block.timestamp);

            _scheduleViaVoting(maliciousProposalId2, "Rug Pool attempt 2", _timelock.ADMIN_EXECUTOR(), maliciousCalls);

            vm.warp(block.timestamp + _DELAY + 1);
            ScheduledCallsBatch memory batch = _timelock.getScheduledCallsBatch(maliciousProposalId2);
            assertTrue(block.timestamp > batch.executableAfter);

            // new malicious proposal also can't be executed
            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyCommittee.selector, address(this)));
            _timelock.execute(maliciousProposalId2);
        }

        // emergency mode is over but proposals can't be executed until the emergency mode turned off manually
        {
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);
            assertTrue(emergencyState.emergencyModeEndsAfter < block.timestamp);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyCommittee.selector, address(this)));
            _timelock.execute(maliciousProposalId);

            vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyCommittee.selector, address(this)));
            _timelock.execute(maliciousProposalId2);
        }

        // anyone can deactivate emergency mode when it's over
        {
            _timelock.emergencyModeDeactivate();

            emergencyState = _timelock.getEmergencyState();
            assertFalse(emergencyState.isEmergencyModeActivated);
        }

        // all malicious calls is canceled now and can't be executed
        {
            assertTrue(_timelock.getIsCanceled(maliciousProposalId));
            vm.expectRevert(
                abi.encodeWithSelector(ScheduledCallsBatches.CallsBatchCanceled.selector, (maliciousProposalId))
            );
            _timelock.execute(maliciousProposalId);

            assertTrue(_timelock.getIsCanceled(maliciousProposalId));
            vm.expectRevert(
                abi.encodeWithSelector(ScheduledCallsBatches.CallsBatchCanceled.selector, (maliciousProposalId2))
            );
            _timelock.execute(maliciousProposalId2);
        }

        // but they can be removed now
        {
            _timelock.removeCanceledCallsBatch(maliciousProposalId);
            _timelock.removeCanceledCallsBatch(maliciousProposalId2);

            assertEq(_timelock.getScheduledCallBatchesCount(), 0);

            vm.expectRevert(
                abi.encodeWithSelector(ScheduledCallsBatches.BatchNotScheduled.selector, (maliciousProposalId))
            );
            _timelock.execute(maliciousProposalId);

            vm.expectRevert(
                abi.encodeWithSelector(ScheduledCallsBatches.BatchNotScheduled.selector, (maliciousProposalId2))
            );
            _timelock.execute(maliciousProposalId2);
        }
    }

    function testFork_EmergencyResetGovernance() external {
        // deploy dual governance full setup
        {
            (_dualGovernance, _timelock,) = _dualGovernanceDeployScript.deploy(
                DAO_VOTING, _DELAY, _EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, _EMERGENCY_MODE_DURATION
            );
        }

        // emergency committee activates emergency mode
        EmergencyState memory emergencyState;
        {
            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyModeActivate();

            emergencyState = _timelock.getEmergencyState();
            assertTrue(emergencyState.isEmergencyModeActivated);
        }

        // before the end of the emergency mode emergency committee can reset governance to DAO
        {
            vm.warp(block.timestamp + _EMERGENCY_MODE_DURATION / 2);
            assertTrue(emergencyState.emergencyModeEndsAfter > block.timestamp);

            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyResetGovernance();

            assertEq(_timelock.getGovernance(), DAO_VOTING);

            emergencyState = _timelock.getEmergencyState();
            assertEq(emergencyState.committee, address(0));
            assertEq(emergencyState.emergencyModeDuration, 0);
            assertEq(emergencyState.emergencyModeEndsAfter, 0);
            assertFalse(emergencyState.isEmergencyModeActivated);
        }
    }

    function testFork_ExpiredEmergencyCommitteeHasNoPower() external {
        // deploy dual governance full setup
        {
            (_dualGovernance, _timelock,) = _dualGovernanceDeployScript.deploy(
                DAO_VOTING, _DELAY, _EMERGENCY_COMMITTEE, _EMERGENCY_PROTECTION_DURATION, _EMERGENCY_MODE_DURATION
            );
        }

        // wait till the protection duration passes
        {
            vm.warp(block.timestamp + _EMERGENCY_PROTECTION_DURATION + 1);
        }

        // attempt to activate emergency protection fails
        {
            vm.expectRevert(EmergencyProtection.EmergencyCommitteeExpired.selector);
            vm.prank(_EMERGENCY_COMMITTEE);
            _timelock.emergencyModeActivate();
        }
    }

    function _execute(uint256 proposalId) internal {
        _execute(proposalId, address(this));
    }

    function _execute(uint256 proposalId, address sender) internal {
        uint256 scheduledCallBatchesCountBefore = _timelock.getScheduledCallBatchesCount();
        if (sender != address(this)) {
            vm.prank(sender);
        }
        _timelock.execute(proposalId);

        assertEq(_timelock.getScheduledCallBatchesCount(), scheduledCallBatchesCountBefore - 1);
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

    function _propose(string memory description, ExecutorCall[] memory calls) internal returns (uint256 proposalId) {
        bytes memory script =
            Utils.encodeEvmCallScript(address(_dualGovernance), abi.encodeCall(_dualGovernance.propose, (calls)));

        uint256 proposalsCountBefore = _dualGovernance.getProposalsCount();

        uint256 voteId = Utils.adoptVote(DAO_VOTING, description, script);
        Utils.executeVote(DAO_VOTING, voteId);

        uint256 proposalsCountAfter = _dualGovernance.getProposalsCount();
        // proposal was created
        assertEq(proposalsCountAfter, proposalsCountBefore + 1);
        proposalId = proposalsCountAfter;

        // and with correct data
        Proposal memory proposal = _dualGovernance.getProposal(proposalId);
        assertEq(proposal.id, proposalId);
        assertEq(proposal.proposer, DAO_VOTING);
        assertEq(proposal.executor, _timelock.ADMIN_EXECUTOR());
        assertEq(proposal.proposedAt, block.timestamp);
        assertEq(proposal.adoptedAt, 0);

        assertEq(proposal.calls.length, calls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            assertEq(proposal.calls[i].value, calls[i].value);
            assertEq(proposal.calls[i].target, calls[i].target);
            assertEq(proposal.calls[i].payload, calls[i].payload);
        }
    }

    function _relayViaDualGovernance(uint256 proposalId) internal {
        _dualGovernance.relay(proposalId);
        Proposal memory proposal = _dualGovernance.getProposal(proposalId);
        assertEq(proposal.adoptedAt, block.timestamp);
    }

    function _scheduleViaDualGovernance(uint256 proposalId, address executor, ExecutorCall[] memory calls) internal {
        uint256 scheduledCallsCountBefore = _timelock.getScheduledCallBatchesCount();

        _dualGovernance.schedule(proposalId);
        Proposal memory proposal = _dualGovernance.getProposal(proposalId);
        assertEq(proposal.adoptedAt, block.timestamp);

        // new call is scheduled but has not executable yet
        assertEq(_timelock.getScheduledCallBatchesCount(), scheduledCallsCountBefore + 1);

        // validate the correct batch was created
        _assertScheduledCallsBatch(proposalId, executor, calls);
    }

    function _scheduleViaVoting(
        uint256 proposalId,
        string memory description,
        address executor,
        ExecutorCall[] memory calls
    ) internal {
        uint256 scheduledCallsCountBefore = _timelock.getScheduledCallBatchesCount();

        bytes memory script = Utils.encodeEvmCallScript(
            address(_timelock), abi.encodeCall(_timelock.schedule, (proposalId, executor, calls))
        );
        uint256 voteId = Utils.adoptVote(DAO_VOTING, description, script);

        // The scheduled calls count is the same until the vote is enacted
        assertEq(_timelock.getScheduledCallBatchesCount(), scheduledCallsCountBefore);

        // executing the vote
        Utils.executeVote(DAO_VOTING, voteId);

        // new call is scheduled but has not executable yet
        assertEq(_timelock.getScheduledCallBatchesCount(), scheduledCallsCountBefore + 1);

        // validate the correct batch was created
        _assertScheduledCallsBatch(proposalId, executor, calls);
    }

    function _assertScheduledCallsBatch(uint256 proposalId, address executor, ExecutorCall[] memory calls) internal {
        ScheduledCallsBatch memory batch = _timelock.getScheduledCallsBatch(proposalId);
        assertEq(batch.id, proposalId, "unexpected batch id");
        assertFalse(batch.isCanceled, "batch is canceled");
        assertEq(batch.executor, executor, "unexpected executor");
        assertEq(batch.scheduledAt, block.timestamp, "unexpected scheduledAt");
        assertEq(batch.executableAfter, block.timestamp + _DELAY, "unexpected executableAfter");
        assertEq(batch.calls.length, calls.length, "unexpected calls length");

        for (uint256 i = 0; i < batch.calls.length; ++i) {
            ExecutorCall memory expected = calls[i];
            ExecutorCall memory actual = batch.calls[i];

            assertEq(actual.value, expected.value);
            assertEq(actual.target, expected.target);
            assertEq(actual.payload, expected.payload);
        }
    }

    function _waitFor(uint256 proposalId) internal {
        // the call is not executable until the delay has passed
        assertFalse(
            _timelock.getScheduledCallsBatch(proposalId).executableAfter <= block.timestamp, "proposal is executable"
        );

        // wait until scheduled call becomes executable
        vm.warp(block.timestamp + _DELAY + 1);
        assertFalse(
            _timelock.getScheduledCallsBatch(proposalId).executableAfter > block.timestamp, "proposal is executable"
        );
    }
}
