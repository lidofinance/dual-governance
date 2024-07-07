// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Vm} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {IConfiguration, Configuration} from "contracts/Configuration.sol";
import {ConfigurationProvider} from "contracts/ConfigurationProvider.sol";
import {Executor} from "contracts/Executor.sol";
import {Proposal, Proposals, ExecutorCall, Status} from "contracts/libraries/Proposals.sol";
import {EmergencyProtection, EmergencyState} from "contracts/libraries/EmergencyProtection.sol";

import {UnitTest, Duration, Timestamp, Timestamps, Durations, console} from "test/utils/unit-test.sol";
import {TargetMock} from "test/utils/utils.sol";
import {ExecutorCallHelpers} from "test/utils/executor-calls.sol";
import {IDangerousContract} from "test/utils/interfaces.sol";

contract EmergencyProtectedTimelockUnitTests is UnitTest {
    EmergencyProtectedTimelock private _timelock;
    Configuration private _config;
    TargetMock private _targetMock;
    Executor private _executor;

    address private _emergencyActivator = makeAddr("EMERGENCY_ACTIVATION_COMMITTEE");
    address private _emergencyEnactor = makeAddr("EMERGENCY_EXECUTION_COMMITTEE");
    Duration private _emergencyModeDuration = Durations.from(180 days);
    Duration private _emergencyProtectionDuration = Durations.from(90 days);

    address private _emergencyGovernance = makeAddr("EMERGENCY_GOVERNANCE");
    address private _dualGovernance = makeAddr("DUAL_GOVERNANCE");
    address private _adminExecutor;

    function setUp() external {
        _executor = new Executor(address(this));
        _config = new Configuration(address(_executor), _emergencyGovernance, new address[](0));
        _timelock = new EmergencyProtectedTimelock(address(_config));
        _targetMock = new TargetMock();

        _executor.transferOwnership(address(_timelock));
        _adminExecutor = address(_executor);

        vm.startPrank(_adminExecutor);
        _timelock.setGovernance(_dualGovernance);
        _timelock.setEmergencyProtection(
            _emergencyActivator, _emergencyEnactor, _emergencyProtectionDuration, _emergencyModeDuration
        );
        vm.stopPrank();
    }

    // EmergencyProtectedTimelock.submit()

    function testFuzz_stranger_cannot_submit_proposal(address stranger) external {
        vm.assume(stranger != _dualGovernance);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtectedTimelock.NotGovernance.selector, [stranger, _dualGovernance])
        );
        _timelock.submit(_adminExecutor, new ExecutorCall[](0));
        assertEq(_timelock.getProposalsCount(), 0);
    }

    function test_governance_can_submit_proposal() external {
        vm.prank(_dualGovernance);
        _timelock.submit(_adminExecutor, _getTargetRegularStaffCalls(address(_targetMock)));

        assertEq(_timelock.getProposalsCount(), 1);

        Proposal memory proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Submitted);
    }

    // EmergencyProtectedTimelock.schedule()

    function test_governance_can_schedule_proposal() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_config.AFTER_SUBMIT_DELAY());

        _scheduleProposal(1);

        Proposal memory proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Scheduled);
    }

    function testFuzz_stranger_cannot_schedule_proposal(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        vm.assume(stranger != address(0));

        _submitProposal();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtectedTimelock.NotGovernance.selector, [stranger, _dualGovernance])
        );
        _timelock.schedule(1);

        Proposal memory proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Submitted);
    }

    // EmergencyProtectedTimelock.execute()

    function testFuzz_anyone_can_execute_proposal(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        vm.assume(stranger != address(0));

        _submitProposal();
        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_config.AFTER_SUBMIT_DELAY());

        _scheduleProposal(1);

        _wait(_config.AFTER_SCHEDULE_DELAY());

        vm.prank(stranger);
        _timelock.execute(1);

        Proposal memory proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Executed);
    }

    function test_cannot_execute_proposal_if_emergency_mode_active() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_config.AFTER_SUBMIT_DELAY());
        _scheduleProposal(1);

        _wait(_config.AFTER_SCHEDULE_DELAY());

        _activateEmergencyMode();

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeActiveValue.selector, [true, false])
        );
        _timelock.execute(1);

        Proposal memory proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Scheduled);
    }

    // EmergencyProtectedTimelock.cancelAllNonExecutedProposals()

    function test_governance_can_cancel_all_non_executed_proposals() external {
        _submitProposal();
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 2);

        _wait(_config.AFTER_SUBMIT_DELAY());

        _scheduleProposal(1);

        Proposal memory proposal1 = _timelock.getProposal(1);
        Proposal memory proposal2 = _timelock.getProposal(2);

        assert(proposal1.status == Status.Scheduled);
        assert(proposal2.status == Status.Submitted);

        vm.prank(_dualGovernance);
        _timelock.cancelAllNonExecutedProposals();

        proposal1 = _timelock.getProposal(1);
        proposal2 = _timelock.getProposal(2);

        assertEq(_timelock.getProposalsCount(), 2);
        assert(proposal1.status == Status.Cancelled);
        assert(proposal2.status == Status.Cancelled);
    }

    function testFuzz_stranger_cannot_cancel_all_non_executed_proposals(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        vm.assume(stranger != address(0));

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtectedTimelock.NotGovernance.selector, [stranger, _dualGovernance])
        );
        _timelock.cancelAllNonExecutedProposals();
    }

    // EmergencyProtectedTimelock.transferExecutorOwnership()

    function testFuzz_admin_executor_can_transfer_executor_ownership(address newOwner) external {
        vm.assume(newOwner != _adminExecutor);
        vm.assume(newOwner != address(0));

        Executor executor = new Executor(address(_timelock));

        assertEq(executor.owner(), address(_timelock));

        vm.prank(_adminExecutor);

        vm.expectEmit(address(executor));
        emit Ownable.OwnershipTransferred(address(_timelock), newOwner);

        _timelock.transferExecutorOwnership(address(executor), newOwner);

        assertEq(executor.owner(), newOwner);
    }

    function test_stranger_cannot_transfer_executor_ownership(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ConfigurationProvider.NotAdminExecutor.selector, stranger));
        _timelock.transferExecutorOwnership(_adminExecutor, makeAddr("newOwner"));
    }

    // EmergencyProtectedTimelock.setGovernance()

    function testFuzz_admin_executor_can_set_governance(address newGovernance) external {
        vm.assume(newGovernance != _dualGovernance);
        vm.assume(newGovernance != address(0));

        vm.expectEmit(address(_timelock));
        emit EmergencyProtectedTimelock.GovernanceSet(newGovernance);

        vm.recordLogs();
        vm.prank(_adminExecutor);
        _timelock.setGovernance(newGovernance);

        assertEq(_timelock.getGovernance(), newGovernance);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
    }

    function test_cannot_set_governance_to_zero() external {
        vm.prank(_adminExecutor);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.InvalidGovernance.selector, address(0)));
        _timelock.setGovernance(address(0));
    }

    function test_cannot_set_governance_to_the_same_address() external {
        address currentGovernance = _timelock.getGovernance();
        vm.prank(_adminExecutor);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.InvalidGovernance.selector, _dualGovernance));
        _timelock.setGovernance(currentGovernance);

        assertEq(_timelock.getGovernance(), currentGovernance);
    }

    function testFuzz_stranger_cannot_set_governance(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ConfigurationProvider.NotAdminExecutor.selector, stranger));
        _timelock.setGovernance(makeAddr("newGovernance"));
    }

    // EmergencyProtectedTimelock.activateEmergencyMode()

    function test_emergency_activator_can_activate_emergency_mode() external {
        vm.prank(_emergencyActivator);
        _timelock.activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);
    }

    function testFuzz_stranger_cannot_activate_emergency_mode(address stranger) external {
        vm.assume(stranger != _emergencyActivator);
        vm.assume(stranger != address(0));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyActivator.selector, stranger));
        _timelock.activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), false);
    }

    function test_cannot_activate_emergency_mode_if_already_active() external {
        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(_emergencyActivator);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeActiveValue.selector, [true, false])
        );
        _timelock.activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);
    }

    // EmergencyProtectedTimelock.emergencyExecute()

    function test_emergency_executior_can_execute_proposal() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_config.AFTER_SUBMIT_DELAY());

        _scheduleProposal(1);

        _wait(_config.AFTER_SCHEDULE_DELAY());

        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(_emergencyEnactor);
        _timelock.emergencyExecute(1);

        Proposal memory proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Executed);
    }

    function test_cannot_emergency_execute_proposal_if_mode_not_activated() external {
        vm.startPrank(_dualGovernance);
        _timelock.submit(_adminExecutor, _getTargetRegularStaffCalls(address(_targetMock)));

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_config.AFTER_SUBMIT_DELAY());
        _timelock.schedule(1);

        _wait(_config.AFTER_SCHEDULE_DELAY());
        vm.stopPrank();

        EmergencyState memory state = _timelock.getEmergencyState();
        assertEq(state.isEmergencyModeActivated, false);

        vm.prank(_emergencyActivator);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeActiveValue.selector, [false, true])
        );
        _timelock.emergencyExecute(1);
    }

    function testFuzz_stranger_cannot_emergency_execute_proposal(address stranger) external {
        vm.assume(stranger != _emergencyEnactor);
        vm.assume(stranger != address(0));

        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_config.AFTER_SUBMIT_DELAY());

        _scheduleProposal(1);

        _wait(_config.AFTER_SCHEDULE_DELAY());

        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyEnactor.selector, stranger));
        _timelock.emergencyExecute(1);
    }

    // EmergencyProtectedTimelock.deactivateEmergencyMode()

    function test_admin_executor_can_deactivate_emergency_mode_if_delay_not_passed() external {
        _activateEmergencyMode();

        vm.prank(_adminExecutor);
        _timelock.deactivateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), false);
    }

    function test_after_deactivation_all_proposals_are_cancelled() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        Proposal memory proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Submitted);

        _activateEmergencyMode();

        _deactivateEmergencyMode();

        proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Cancelled);
    }

    function testFuzz_stranger_can_deactivate_emergency_mode_if_passed(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        _activateEmergencyMode();

        EmergencyState memory state = _timelock.getEmergencyState();
        assertEq(_isEmergencyStateActivated(), true);

        _wait(state.emergencyModeDuration.plusSeconds(1));

        vm.prank(stranger);
        _timelock.deactivateEmergencyMode();

        state = _timelock.getEmergencyState();
        assertEq(_isEmergencyStateActivated(), false);
    }

    function testFuzz_cannot_deactivate_emergency_mode_if_not_activated(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeActiveValue.selector, [false, true])
        );
        _timelock.deactivateEmergencyMode();

        vm.prank(_adminExecutor);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeActiveValue.selector, [false, true])
        );
        _timelock.deactivateEmergencyMode();
    }

    function testFuzz_stranger_cannot_deactivate_emergency_mode_if_not_passed(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        _activateEmergencyMode();
        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ConfigurationProvider.NotAdminExecutor.selector, stranger));
        _timelock.deactivateEmergencyMode();
    }

    // EmergencyProtectedTimelock.emergencyReset()

    function test_execution_committee_can_emergency_reset() external {
        _activateEmergencyMode();
        assertEq(_isEmergencyStateActivated(), true);
        assertEq(_timelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyEnactor);
        _timelock.emergencyReset();

        EmergencyState memory newState = _timelock.getEmergencyState();

        assertEq(_isEmergencyStateActivated(), false);
        assertEq(_timelock.getGovernance(), _emergencyGovernance);
        assertEq(_timelock.isEmergencyProtectionEnabled(), false);

        assertEq(newState.activationCommittee, address(0));
        assertEq(newState.executionCommittee, address(0));
        assertEq(newState.protectedTill, Timestamps.ZERO);
        assertEq(newState.emergencyModeDuration, Durations.ZERO);
        assertEq(newState.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_after_emergency_reset_all_proposals_are_cancelled() external {
        _submitProposal();
        _activateEmergencyMode();

        Proposal memory proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Submitted);

        vm.prank(_emergencyEnactor);
        _timelock.emergencyReset();

        proposal = _timelock.getProposal(1);
        assert(proposal.status == Status.Cancelled);
    }

    function testFuzz_stranger_cannot_emergency_reset_governance(address stranger) external {
        vm.assume(stranger != _emergencyEnactor);
        vm.assume(stranger != address(0));

        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.NotEmergencyEnactor.selector, stranger));
        _timelock.emergencyReset();

        assertEq(_isEmergencyStateActivated(), true);
    }

    function test_cannot_emergency_reset_if_emergency_mode_not_activated() external {
        assertEq(_isEmergencyStateActivated(), false);

        EmergencyState memory state = _timelock.getEmergencyState();

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.InvalidEmergencyModeActiveValue.selector, [false, true])
        );
        vm.prank(_emergencyEnactor);
        _timelock.emergencyReset();

        EmergencyState memory newState = _timelock.getEmergencyState();

        assertEq(newState.executionCommittee, state.executionCommittee);
        assertEq(newState.activationCommittee, state.activationCommittee);
        assertEq(newState.protectedTill, state.protectedTill);
        assertEq(newState.emergencyModeEndsAfter, state.emergencyModeEndsAfter);
        assertEq(newState.emergencyModeDuration, state.emergencyModeDuration);
        assertEq(newState.isEmergencyModeActivated, state.isEmergencyModeActivated);
    }

    // EmergencyProtectedTimelock.setEmergencyProtection()

    function test_admin_executor_can_set_emenrgency_protection() external {
        EmergencyProtectedTimelock _localTimelock = new EmergencyProtectedTimelock(address(_config));

        vm.prank(_adminExecutor);
        _localTimelock.setEmergencyProtection(
            _emergencyActivator, _emergencyEnactor, _emergencyProtectionDuration, _emergencyModeDuration
        );

        EmergencyState memory state = _localTimelock.getEmergencyState();

        assertEq(state.activationCommittee, _emergencyActivator);
        assertEq(state.executionCommittee, _emergencyEnactor);
        assertEq(state.protectedTill, _emergencyProtectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeDuration, _emergencyModeDuration);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
        assertEq(state.isEmergencyModeActivated, false);
    }

    function testFuzz_stranger_cannot_set_emergency_protection(address stranger) external {
        vm.assume(stranger != _adminExecutor);
        vm.assume(stranger != address(0));

        EmergencyProtectedTimelock _localTimelock = new EmergencyProtectedTimelock(address(_config));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ConfigurationProvider.NotAdminExecutor.selector, stranger));
        _localTimelock.setEmergencyProtection(
            _emergencyActivator, _emergencyEnactor, _emergencyProtectionDuration, _emergencyModeDuration
        );

        EmergencyState memory state = _localTimelock.getEmergencyState();

        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
        assertEq(state.isEmergencyModeActivated, false);
    }

    // EmergencyProtectedTimelock.isEmergencyProtectionEnabled()

    function test_is_emergency_protection_enabled_deactivate() external {
        EmergencyProtectedTimelock _localTimelock = new EmergencyProtectedTimelock(address(_config));

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), false);

        vm.prank(_adminExecutor);
        _localTimelock.setEmergencyProtection(
            _emergencyActivator, _emergencyEnactor, _emergencyProtectionDuration, _emergencyModeDuration
        );

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_adminExecutor);
        _localTimelock.deactivateEmergencyMode();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), false);
    }

    function test_is_emergency_protection_enabled_reset() external {
        EmergencyProtectedTimelock _localTimelock = new EmergencyProtectedTimelock(address(_config));

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), false);

        vm.prank(_adminExecutor);
        _localTimelock.setEmergencyProtection(
            _emergencyActivator, _emergencyEnactor, _emergencyProtectionDuration, _emergencyModeDuration
        );

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyEnactor);
        _localTimelock.emergencyReset();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), false);
    }

    // EmergencyProtectedTimelock.getEmergencyState()

    function test_get_emergency_state_deactivate() external {
        EmergencyProtectedTimelock _localTimelock = new EmergencyProtectedTimelock(address(_config));

        EmergencyState memory state = _localTimelock.getEmergencyState();

        assertEq(state.isEmergencyModeActivated, false);
        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);

        vm.prank(_adminExecutor);
        _localTimelock.setEmergencyProtection(
            _emergencyActivator, _emergencyEnactor, _emergencyProtectionDuration, _emergencyModeDuration
        );

        state = _localTimelock.getEmergencyState();

        assertEq(_localTimelock.getEmergencyState().isEmergencyModeActivated, false);
        assertEq(state.activationCommittee, _emergencyActivator);
        assertEq(state.executionCommittee, _emergencyEnactor);
        assertEq(state.protectedTill, _emergencyProtectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeDuration, _emergencyModeDuration);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        state = _localTimelock.getEmergencyState();

        assertEq(_localTimelock.getEmergencyState().isEmergencyModeActivated, true);
        assertEq(state.executionCommittee, _emergencyEnactor);
        assertEq(state.activationCommittee, _emergencyActivator);
        assertEq(state.emergencyModeDuration, _emergencyModeDuration);
        assertEq(state.protectedTill, _emergencyProtectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeEndsAfter, _emergencyModeDuration.addTo(Timestamps.now()));

        vm.prank(_adminExecutor);
        _localTimelock.deactivateEmergencyMode();

        state = _localTimelock.getEmergencyState();

        assertEq(state.isEmergencyModeActivated, false);
        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_get_emergency_state_reset() external {
        EmergencyProtectedTimelock _localTimelock = new EmergencyProtectedTimelock(address(_config));

        vm.prank(_adminExecutor);
        _localTimelock.setEmergencyProtection(
            _emergencyActivator, _emergencyEnactor, _emergencyProtectionDuration, _emergencyModeDuration
        );

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        vm.prank(_emergencyEnactor);
        _localTimelock.emergencyReset();

        EmergencyState memory state = _localTimelock.getEmergencyState();

        assertEq(state.isEmergencyModeActivated, false);
        assertEq(state.activationCommittee, address(0));
        assertEq(state.executionCommittee, address(0));
        assertEq(state.protectedTill, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    // EmergencyProtectedTimelock.getGovernance()

    function testFuzz_get_governance(address governance) external {
        vm.assume(governance != address(0) && governance != _timelock.getGovernance());
        vm.prank(_adminExecutor);
        _timelock.setGovernance(governance);
        assertEq(_timelock.getGovernance(), governance);
    }

    // EmergencyProtectedTimelock.getProposal()

    function test_get_proposal() external {
        assertEq(_timelock.getProposalsCount(), 0);

        vm.startPrank(_dualGovernance);
        ExecutorCall[] memory executorCalls = _getTargetRegularStaffCalls(address(_targetMock));
        _timelock.submit(_adminExecutor, executorCalls);
        _timelock.submit(_adminExecutor, executorCalls);

        Proposal memory submittedProposal = _timelock.getProposal(1);

        Timestamp submitTimestamp = Timestamps.now();

        assertEq(submittedProposal.id, 1);
        assertEq(submittedProposal.executor, _adminExecutor);
        assertEq(submittedProposal.submittedAt, submitTimestamp);
        assertEq(submittedProposal.scheduledAt, Timestamps.ZERO);
        assertEq(submittedProposal.executedAt, Timestamps.ZERO);
        // assertEq doesn't support comparing enumerables so far
        assert(submittedProposal.status == Status.Submitted);
        assertEq(submittedProposal.calls.length, 1);
        assertEq(submittedProposal.calls[0].value, executorCalls[0].value);
        assertEq(submittedProposal.calls[0].target, executorCalls[0].target);
        assertEq(submittedProposal.calls[0].payload, executorCalls[0].payload);

        _wait(_config.AFTER_SUBMIT_DELAY());

        _timelock.schedule(1);
        Timestamp scheduleTimestamp = Timestamps.now();

        Proposal memory scheduledProposal = _timelock.getProposal(1);

        assertEq(scheduledProposal.id, 1);
        assertEq(scheduledProposal.executor, _adminExecutor);
        assertEq(scheduledProposal.submittedAt, submitTimestamp);
        assertEq(scheduledProposal.scheduledAt, scheduleTimestamp);
        assertEq(scheduledProposal.executedAt, Timestamps.ZERO);
        // // assertEq doesn't support comparing enumerables so far
        assert(scheduledProposal.status == Status.Scheduled);
        assertEq(scheduledProposal.calls.length, 1);
        assertEq(scheduledProposal.calls[0].value, executorCalls[0].value);
        assertEq(scheduledProposal.calls[0].target, executorCalls[0].target);
        assertEq(scheduledProposal.calls[0].payload, executorCalls[0].payload);

        _wait(_config.AFTER_SCHEDULE_DELAY());

        _timelock.execute(1);

        Proposal memory executedProposal = _timelock.getProposal(1);
        Timestamp executeTimestamp = Timestamps.now();

        assertEq(executedProposal.id, 1);
        assertEq(executedProposal.executor, _adminExecutor);
        assertEq(executedProposal.submittedAt, submitTimestamp);
        assertEq(executedProposal.scheduledAt, scheduleTimestamp);
        assertEq(executedProposal.executedAt, executeTimestamp);
        // assertEq doesn't support comparing enumerables so far
        assert(executedProposal.status == Status.Executed);
        assertEq(executedProposal.calls.length, 1);
        assertEq(executedProposal.calls[0].value, executorCalls[0].value);
        assertEq(executedProposal.calls[0].target, executorCalls[0].target);
        assertEq(executedProposal.calls[0].payload, executorCalls[0].payload);

        _timelock.cancelAllNonExecutedProposals();

        Proposal memory cancelledProposal = _timelock.getProposal(2);

        assertEq(cancelledProposal.id, 2);
        assertEq(cancelledProposal.executor, _adminExecutor);
        assertEq(cancelledProposal.submittedAt, submitTimestamp);
        assertEq(cancelledProposal.scheduledAt, Timestamps.ZERO);
        assertEq(cancelledProposal.executedAt, Timestamps.ZERO);
        // assertEq doesn't support comparing enumerables so far
        assert(cancelledProposal.status == Status.Cancelled);
        assertEq(cancelledProposal.calls.length, 1);
        assertEq(cancelledProposal.calls[0].value, executorCalls[0].value);
        assertEq(cancelledProposal.calls[0].target, executorCalls[0].target);
        assertEq(cancelledProposal.calls[0].payload, executorCalls[0].payload);
    }

    function test_get_not_existing_proposal() external {
        assertEq(_timelock.getProposalsCount(), 0);

        vm.expectRevert();
        _timelock.getProposal(1);
    }

    // EmergencyProtectedTimelock.getProposalsCount()

    function testFuzz_get_proposals_count(uint256 count) external {
        vm.assume(count > 0);
        vm.assume(count <= type(uint8).max);
        assertEq(_timelock.getProposalsCount(), 0);

        for (uint256 i = 1; i <= count; i++) {
            _submitProposal();
            assertEq(_timelock.getProposalsCount(), i);
        }
    }

    // EmergencyProtectedTimelock.canExecute()

    function test_can_execute() external {
        assertEq(_timelock.canExecute(1), false);
        _submitProposal();
        assertEq(_timelock.canExecute(1), false);

        _wait(_config.AFTER_SUBMIT_DELAY());

        _scheduleProposal(1);

        assertEq(_timelock.canExecute(1), false);

        _wait(_config.AFTER_SCHEDULE_DELAY());

        assertEq(_timelock.canExecute(1), true);

        vm.prank(_dualGovernance);
        _timelock.cancelAllNonExecutedProposals();

        assertEq(_timelock.canExecute(1), false);
    }

    // EmergencyProtectedTimelock.canSchedule()

    function test_can_schedule() external {
        assertEq(_timelock.canExecute(1), false);
        _submitProposal();
        assertEq(_timelock.canSchedule(1), false);

        _wait(_config.AFTER_SUBMIT_DELAY());

        assertEq(_timelock.canSchedule(1), true);

        _scheduleProposal(1);

        assertEq(_timelock.canSchedule(1), false);

        vm.prank(_dualGovernance);
        _timelock.cancelAllNonExecutedProposals();

        assertEq(_timelock.canSchedule(1), false);
    }

    // EmergencyProtectedTimelock.getProposalSubmissionTime()

    function test_get_proposal_submission_time() external {
        _submitProposal();
        assertEq(_timelock.getProposalSubmissionTime(1), Timestamps.now());
    }

    // Utils

    function _submitProposal() internal {
        vm.prank(_dualGovernance);
        _timelock.submit(_adminExecutor, _getTargetRegularStaffCalls(address(_targetMock)));
    }

    function _scheduleProposal(uint256 proposalId) internal {
        vm.prank(_dualGovernance);
        _timelock.schedule(proposalId);
    }

    function _isEmergencyStateActivated() internal view returns (bool) {
        EmergencyState memory state = _timelock.getEmergencyState();
        return state.isEmergencyModeActivated;
    }

    function _activateEmergencyMode() internal {
        vm.prank(_emergencyActivator);
        _timelock.activateEmergencyMode();
        assertEq(_isEmergencyStateActivated(), true);
    }

    function _deactivateEmergencyMode() internal {
        vm.prank(_adminExecutor);
        _timelock.deactivateEmergencyMode();
        assertEq(_isEmergencyStateActivated(), false);
    }
}
