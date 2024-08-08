// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {ITimelock, ProposalStatus} from "contracts/interfaces/ITimelock.sol";

import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";

import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock, TimelockState} from "contracts/EmergencyProtectedTimelock.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {TargetMock} from "test/utils/target-mock.sol";
import {ExternalCall} from "test/utils/executor-calls.sol";

contract EmergencyProtectedTimelockUnitTests is UnitTest {
    EmergencyProtectedTimelock private _timelock;
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
        _adminExecutor = address(_executor);

        _timelock = _deployEmergencyProtectedTimelock();

        _targetMock = new TargetMock();

        _executor.transferOwnership(address(_timelock));

        vm.startPrank(_adminExecutor);
        _timelock.setGovernance(_dualGovernance);
        _timelock.setDelays({afterSubmitDelay: Durations.from(3 days), afterScheduleDelay: Durations.from(2 days)});
        _timelock.setupEmergencyProtection(
            _emergencyGovernance,
            _emergencyActivator,
            _emergencyEnactor,
            _emergencyProtectionDuration.addTo(Timestamps.now()),
            _emergencyModeDuration
        );
        vm.stopPrank();
    }

    // EmergencyProtectedTimelock.submit()

    function testFuzz_stranger_cannot_submit_proposal(address stranger) external {
        vm.assume(stranger != _dualGovernance);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, [stranger]));
        _timelock.submit(_adminExecutor, new ExternalCall[](0));
        assertEq(_timelock.getProposalsCount(), 0);
    }

    function test_governance_can_submit_proposal() external {
        vm.prank(_dualGovernance);
        _timelock.submit(_adminExecutor, _getMockTargetRegularStaffCalls(address(_targetMock)));

        assertEq(_timelock.getProposalsCount(), 1);

        ITimelock.Proposal memory proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Submitted);
    }

    // EmergencyProtectedTimelock.schedule()

    function test_governance_can_schedule_proposal() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        ITimelock.Proposal memory proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Scheduled);
    }

    function testFuzz_stranger_cannot_schedule_proposal(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        vm.assume(stranger != address(0));

        _submitProposal();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, [stranger]));

        _timelock.schedule(1);

        ITimelock.Proposal memory proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Submitted);
    }

    // EmergencyProtectedTimelock.execute()

    function testFuzz_anyone_can_execute_proposal(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        vm.assume(stranger != address(0));

        _submitProposal();
        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        _wait(_timelock.getAfterScheduleDelay());

        vm.prank(stranger);
        _timelock.execute(1);

        ITimelock.Proposal memory proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Executed);
    }

    function test_cannot_execute_proposal_if_emergency_mode_active() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());
        _scheduleProposal(1);

        _wait(_timelock.getAfterScheduleDelay());

        _activateEmergencyMode();

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, [false]));
        _timelock.execute(1);

        ITimelock.Proposal memory proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Scheduled);
    }

    // EmergencyProtectedTimelock.cancelAllNonExecutedProposals()

    function test_governance_can_cancel_all_non_executed_proposals() external {
        _submitProposal();
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 2);

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        ITimelock.Proposal memory proposal1 = _timelock.getProposal(1);
        ITimelock.Proposal memory proposal2 = _timelock.getProposal(2);

        assertEq(proposal1.status, ProposalStatus.Scheduled);
        assertEq(proposal2.status, ProposalStatus.Submitted);

        vm.prank(_dualGovernance);
        _timelock.cancelAllNonExecutedProposals();

        proposal1 = _timelock.getProposal(1);
        proposal2 = _timelock.getProposal(2);

        assertEq(_timelock.getProposalsCount(), 2);
        assertEq(proposal1.status, ProposalStatus.Cancelled);
        assertEq(proposal2.status, ProposalStatus.Cancelled);
    }

    function testFuzz_stranger_cannot_cancel_all_non_executed_proposals(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        vm.assume(stranger != address(0));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, [stranger]));

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
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.CallerIsNotAdminExecutor.selector, stranger));
        _timelock.transferExecutorOwnership(_adminExecutor, makeAddr("newOwner"));
    }

    // EmergencyProtectedTimelock.setGovernance()

    function testFuzz_admin_executor_can_set_governance(address newGovernance) external {
        vm.assume(newGovernance != _dualGovernance);
        vm.assume(newGovernance != address(0));

        vm.expectEmit(address(_timelock));
        emit TimelockState.GovernanceSet(newGovernance);

        vm.recordLogs();
        vm.prank(_adminExecutor);
        _timelock.setGovernance(newGovernance);

        assertEq(_timelock.getGovernance(), newGovernance);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
    }

    function test_cannot_set_governance_to_zero() external {
        vm.prank(_adminExecutor);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidGovernance.selector, address(0)));
        _timelock.setGovernance(address(0));
    }

    // TODO: Update test after the convention about return/revert is resolved
    // function test_cannot_set_governance_to_the_same_address() external {
    //     address currentGovernance = _timelock.getGovernance();
    //     vm.prank(_adminExecutor);
    //     vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidGovernance.selector, _dualGovernance));
    //     _timelock.setGovernance(currentGovernance);

    //     assertEq(_timelock.getGovernance(), currentGovernance);
    // }

    function testFuzz_stranger_cannot_set_governance(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.CallerIsNotAdminExecutor.selector, stranger));
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
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyActivationCommittee.selector, stranger)
        );
        _timelock.activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), false);
    }

    function test_cannot_activate_emergency_mode_if_already_active() external {
        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(_emergencyActivator);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, [false]));
        _timelock.activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);
    }

    // EmergencyProtectedTimelock.emergencyExecute()

    function test_emergency_executior_can_execute_proposal() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        _wait(_timelock.getAfterScheduleDelay());

        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(_emergencyEnactor);
        _timelock.emergencyExecute(1);

        ITimelock.Proposal memory proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Executed);
    }

    function test_cannot_emergency_execute_proposal_if_mode_not_activated() external {
        vm.startPrank(_dualGovernance);
        _timelock.submit(_adminExecutor, _getMockTargetRegularStaffCalls(address(_targetMock)));

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());
        _timelock.schedule(1);

        _wait(_timelock.getAfterScheduleDelay());
        vm.stopPrank();

        assertEq(_timelock.isEmergencyModeActive(), false);

        vm.prank(_emergencyActivator);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, [true]));
        _timelock.emergencyExecute(1);
    }

    function testFuzz_stranger_cannot_emergency_execute_proposal(address stranger) external {
        vm.assume(stranger != _emergencyEnactor);
        vm.assume(stranger != address(0));

        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        _wait(_timelock.getAfterScheduleDelay());

        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyExecutionCommittee.selector, stranger)
        );
        _timelock.emergencyExecute(1);
    }

    // EmergencyProtectedTimelock.deactivateEmergencyMode()

    function test_admin_executor_can_deactivate_emergency_mode_if_delay_not_passed() external {
        _submitProposal();
        _activateEmergencyMode();

        vm.prank(_adminExecutor);
        _timelock.deactivateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), false);
    }

    function test_after_deactivation_all_proposals_are_cancelled() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        ITimelock.Proposal memory proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Submitted);

        _activateEmergencyMode();

        _deactivateEmergencyMode();

        proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Cancelled);
    }

    function testFuzz_stranger_can_deactivate_emergency_mode_if_passed(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        _activateEmergencyMode();

        EmergencyProtection.Context memory state = _timelock.getEmergencyProtectionContext();
        assertEq(_isEmergencyStateActivated(), true);

        _wait(state.emergencyModeDuration.plusSeconds(1));

        vm.prank(stranger);
        _timelock.deactivateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), false);
    }

    function testFuzz_cannot_deactivate_emergency_mode_if_not_activated(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, [true]));
        _timelock.deactivateEmergencyMode();

        vm.prank(_adminExecutor);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, [true]));
        _timelock.deactivateEmergencyMode();
    }

    function testFuzz_stranger_cannot_deactivate_emergency_mode_if_not_passed(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        _activateEmergencyMode();
        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.CallerIsNotAdminExecutor.selector, stranger));
        _timelock.deactivateEmergencyMode();
    }

    // EmergencyProtectedTimelock.emergencyReset()

    function test_execution_committee_can_emergency_reset() external {
        _activateEmergencyMode();
        assertEq(_isEmergencyStateActivated(), true);
        assertEq(_timelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyEnactor);
        _timelock.emergencyReset();

        EmergencyProtection.Context memory newState = _timelock.getEmergencyProtectionContext();

        assertEq(_isEmergencyStateActivated(), false);
        assertEq(_timelock.getGovernance(), _emergencyGovernance);
        assertEq(_timelock.isEmergencyProtectionEnabled(), false);

        assertEq(newState.emergencyActivationCommittee, address(0));
        assertEq(newState.emergencyExecutionCommittee, address(0));
        assertEq(newState.emergencyProtectionEndsAfter, Timestamps.ZERO);
        assertEq(newState.emergencyModeDuration, Durations.ZERO);
        assertEq(newState.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_after_emergency_reset_all_proposals_are_cancelled() external {
        _submitProposal();
        _activateEmergencyMode();

        ITimelock.Proposal memory proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Submitted);

        vm.prank(_emergencyEnactor);
        _timelock.emergencyReset();

        proposal = _timelock.getProposal(1);
        assertEq(proposal.status, ProposalStatus.Cancelled);
    }

    function testFuzz_stranger_cannot_emergency_reset_governance(address stranger) external {
        vm.assume(stranger != _emergencyEnactor);
        vm.assume(stranger != address(0));

        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyExecutionCommittee.selector, stranger)
        );
        _timelock.emergencyReset();

        assertEq(_isEmergencyStateActivated(), true);
    }

    function test_cannot_emergency_reset_if_emergency_mode_not_activated() external {
        assertEq(_isEmergencyStateActivated(), false);

        EmergencyProtection.Context memory state = _timelock.getEmergencyProtectionContext();

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, [true]));
        vm.prank(_emergencyEnactor);
        _timelock.emergencyReset();

        EmergencyProtection.Context memory newState = _timelock.getEmergencyProtectionContext();

        assertEq(newState.emergencyExecutionCommittee, state.emergencyExecutionCommittee);
        assertEq(newState.emergencyActivationCommittee, state.emergencyActivationCommittee);
        assertEq(newState.emergencyProtectionEndsAfter, state.emergencyProtectionEndsAfter);
        assertEq(newState.emergencyModeEndsAfter, state.emergencyModeEndsAfter);
        assertEq(newState.emergencyModeDuration, state.emergencyModeDuration);
        assertFalse(_timelock.isEmergencyModeActive());
    }

    // EmergencyProtectedTimelock.setupEmergencyProtection()

    function test_admin_executor_can_set_emenrgency_protection() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.prank(_adminExecutor);
        _localTimelock.setupEmergencyProtection(
            _emergencyGovernance,
            _emergencyActivator,
            _emergencyEnactor,
            _emergencyProtectionDuration.addTo(Timestamps.now()),
            _emergencyModeDuration
        );

        EmergencyProtection.Context memory state = _timelock.getEmergencyProtectionContext();

        assertEq(state.emergencyActivationCommittee, _emergencyActivator);
        assertEq(state.emergencyExecutionCommittee, _emergencyEnactor);
        assertEq(state.emergencyProtectionEndsAfter, _emergencyProtectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeDuration, _emergencyModeDuration);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
        assertFalse(_timelock.isEmergencyModeActive());
    }

    function testFuzz_stranger_cannot_set_emergency_protection(address stranger) external {
        vm.assume(stranger != _adminExecutor);
        vm.assume(stranger != address(0));

        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtectedTimelock.CallerIsNotAdminExecutor.selector, stranger));
        _localTimelock.setupEmergencyProtection(
            _emergencyGovernance,
            _emergencyActivator,
            _emergencyEnactor,
            _emergencyProtectionDuration.addTo(Timestamps.now()),
            _emergencyModeDuration
        );

        EmergencyProtection.Context memory state = _localTimelock.getEmergencyProtectionContext();

        assertEq(state.emergencyActivationCommittee, address(0));
        assertEq(state.emergencyExecutionCommittee, address(0));
        assertEq(state.emergencyProtectionEndsAfter, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
        assertFalse(_localTimelock.isEmergencyModeActive());
    }

    // EmergencyProtectedTimelock.isEmergencyProtectionEnabled()

    function test_is_emergency_protection_enabled_deactivate() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), false);

        vm.prank(_adminExecutor);
        _localTimelock.setupEmergencyProtection(
            _emergencyGovernance,
            _emergencyActivator,
            _emergencyEnactor,
            _emergencyProtectionDuration.addTo(Timestamps.now()),
            _emergencyModeDuration
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
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), false);

        vm.prank(_adminExecutor);
        _localTimelock.setupEmergencyProtection(
            _emergencyGovernance,
            _emergencyActivator,
            _emergencyEnactor,
            _emergencyProtectionDuration.addTo(Timestamps.now()),
            _emergencyModeDuration
        );

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyEnactor);
        _localTimelock.emergencyReset();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), false);
    }

    // EmergencyProtectedTimelock.getEmergencyProtectionContext()

    function test_get_emergency_state_deactivate() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        EmergencyProtection.Context memory state = _localTimelock.getEmergencyProtectionContext();

        assertFalse(_localTimelock.isEmergencyModeActive());
        assertEq(state.emergencyActivationCommittee, address(0));
        assertEq(state.emergencyExecutionCommittee, address(0));
        assertEq(state.emergencyProtectionEndsAfter, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);

        vm.prank(_adminExecutor);
        _localTimelock.setupEmergencyProtection(
            _emergencyGovernance,
            _emergencyActivator,
            _emergencyEnactor,
            _emergencyProtectionDuration.addTo(Timestamps.now()),
            _emergencyModeDuration
        );

        state = _localTimelock.getEmergencyProtectionContext();

        assertEq(_localTimelock.isEmergencyModeActive(), false);
        assertEq(state.emergencyActivationCommittee, _emergencyActivator);
        assertEq(state.emergencyExecutionCommittee, _emergencyEnactor);
        assertEq(state.emergencyProtectionEndsAfter, _emergencyProtectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeDuration, _emergencyModeDuration);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        state = _localTimelock.getEmergencyProtectionContext();

        assertEq(_localTimelock.isEmergencyModeActive(), true);
        assertEq(state.emergencyExecutionCommittee, _emergencyEnactor);
        assertEq(state.emergencyActivationCommittee, _emergencyActivator);
        assertEq(state.emergencyModeDuration, _emergencyModeDuration);
        assertEq(state.emergencyProtectionEndsAfter, _emergencyProtectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeEndsAfter, _emergencyModeDuration.addTo(Timestamps.now()));

        vm.prank(_adminExecutor);
        _localTimelock.deactivateEmergencyMode();

        state = _localTimelock.getEmergencyProtectionContext();

        assertFalse(_timelock.isEmergencyModeActive());
        assertEq(state.emergencyActivationCommittee, address(0));
        assertEq(state.emergencyExecutionCommittee, address(0));
        assertEq(state.emergencyProtectionEndsAfter, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_get_emergency_state_reset() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.prank(_adminExecutor);
        _localTimelock.setupEmergencyProtection(
            _emergencyGovernance,
            _emergencyActivator,
            _emergencyEnactor,
            _emergencyProtectionDuration.addTo(Timestamps.now()),
            _emergencyModeDuration
        );

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        vm.prank(_emergencyEnactor);
        _localTimelock.emergencyReset();

        EmergencyProtection.Context memory state = _localTimelock.getEmergencyProtectionContext();

        assertFalse(_timelock.isEmergencyModeActive());
        assertEq(state.emergencyActivationCommittee, address(0));
        assertEq(state.emergencyExecutionCommittee, address(0));
        assertEq(state.emergencyProtectionEndsAfter, Timestamps.ZERO);
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
        ExternalCall[] memory executorCalls = _getMockTargetRegularStaffCalls(address(_targetMock));
        _timelock.submit(_adminExecutor, executorCalls);
        _timelock.submit(_adminExecutor, executorCalls);

        ITimelock.Proposal memory submittedProposal = _timelock.getProposal(1);

        Timestamp submitTimestamp = Timestamps.now();

        assertEq(submittedProposal.id, 1);
        assertEq(submittedProposal.executor, _adminExecutor);
        assertEq(submittedProposal.submittedAt, submitTimestamp);
        assertEq(submittedProposal.scheduledAt, Timestamps.ZERO);
        assertEq(submittedProposal.status, ProposalStatus.Submitted);
        assertEq(submittedProposal.calls.length, 1);
        assertEq(submittedProposal.calls[0].value, executorCalls[0].value);
        assertEq(submittedProposal.calls[0].target, executorCalls[0].target);
        assertEq(submittedProposal.calls[0].payload, executorCalls[0].payload);

        _wait(_timelock.getAfterSubmitDelay());

        _timelock.schedule(1);
        Timestamp scheduleTimestamp = Timestamps.now();

        ITimelock.Proposal memory scheduledProposal = _timelock.getProposal(1);

        assertEq(scheduledProposal.id, 1);
        assertEq(scheduledProposal.executor, _adminExecutor);
        assertEq(scheduledProposal.submittedAt, submitTimestamp);
        assertEq(scheduledProposal.scheduledAt, scheduleTimestamp);
        assertEq(scheduledProposal.status, ProposalStatus.Scheduled);
        assertEq(scheduledProposal.calls.length, 1);
        assertEq(scheduledProposal.calls[0].value, executorCalls[0].value);
        assertEq(scheduledProposal.calls[0].target, executorCalls[0].target);
        assertEq(scheduledProposal.calls[0].payload, executorCalls[0].payload);

        _wait(_timelock.getAfterScheduleDelay());

        _timelock.execute(1);

        ITimelock.Proposal memory executedProposal = _timelock.getProposal(1);
        Timestamp executeTimestamp = Timestamps.now();

        assertEq(executedProposal.id, 1);
        assertEq(executedProposal.status, ProposalStatus.Executed);
        assertEq(executedProposal.executor, _adminExecutor);
        assertEq(executedProposal.submittedAt, submitTimestamp);
        assertEq(executedProposal.scheduledAt, scheduleTimestamp);
        // assertEq(executedProposal.executedAt, executeTimestamp);
        // assertEq doesn't support comparing enumerables so far
        assertEq(executedProposal.calls.length, 1);
        assertEq(executedProposal.calls[0].value, executorCalls[0].value);
        assertEq(executedProposal.calls[0].target, executorCalls[0].target);
        assertEq(executedProposal.calls[0].payload, executorCalls[0].payload);

        _timelock.cancelAllNonExecutedProposals();

        ITimelock.Proposal memory cancelledProposal = _timelock.getProposal(2);

        assertEq(cancelledProposal.id, 2);
        assertEq(cancelledProposal.status, ProposalStatus.Cancelled);
        assertEq(cancelledProposal.executor, _adminExecutor);
        assertEq(cancelledProposal.submittedAt, submitTimestamp);
        assertEq(cancelledProposal.scheduledAt, Timestamps.ZERO);
        // assertEq(cancelledProposal.executedAt, Timestamps.ZERO);
        // assertEq doesn't support comparing enumerables so far
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

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        assertEq(_timelock.canExecute(1), false);

        _wait(_timelock.getAfterScheduleDelay());

        assertEq(_timelock.canExecute(1), true);

        vm.prank(_dualGovernance);
        _timelock.cancelAllNonExecutedProposals();

        assertEq(_timelock.canExecute(1), false);
    }

    // EmergencyProtectedTimelock.canSchedule()

    function test_can_schedule() external {
        assertEq(_timelock.canExecute(1), false);
        _submitProposal();

        _wait(_timelock.getAfterSubmitDelay());

        assertEq(_timelock.canSchedule(1), true);

        assertEq(_timelock.canSchedule(1), true);

        _scheduleProposal(1);

        assertEq(_timelock.canSchedule(1), false);

        vm.prank(_dualGovernance);
        _timelock.cancelAllNonExecutedProposals();

        assertEq(_timelock.canSchedule(1), false);
    }

    function test_get_proposal_submission_time() external {
        _submitProposal();
        assertEq(_timelock.getProposal(1).submittedAt, Timestamps.now());
    }

    // Utils

    function _submitProposal() internal {
        vm.prank(_dualGovernance);
        _timelock.submit(_adminExecutor, _getMockTargetRegularStaffCalls(address(_targetMock)));
    }

    function _scheduleProposal(uint256 proposalId) internal {
        vm.prank(_dualGovernance);
        _timelock.schedule(proposalId);
    }

    function _isEmergencyStateActivated() internal view returns (bool) {
        return _timelock.isEmergencyModeActive();
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

    function _deployEmergencyProtectedTimelock() internal returns (EmergencyProtectedTimelock) {
        return new EmergencyProtectedTimelock(
            EmergencyProtectedTimelock.SanityCheckParams({
                maxAfterSubmitDelay: Durations.from(45 days),
                maxAfterScheduleDelay: Durations.from(45 days),
                maxEmergencyModeDuration: Durations.from(365 days),
                maxEmergencyProtectionDuration: Durations.from(365 days)
            }),
            _adminExecutor
        );
    }
}
