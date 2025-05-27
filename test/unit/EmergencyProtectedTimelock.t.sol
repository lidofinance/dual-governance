// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Duration, Durations, MAX_DURATION_VALUE} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ITimelock, ProposalStatus} from "contracts/interfaces/ITimelock.sol";

import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";
import {ExecutableProposals} from "contracts/libraries/ExecutableProposals.sol";

import {Executor} from "contracts/Executor.sol";
import {EmergencyProtectedTimelock, TimelockState} from "contracts/EmergencyProtectedTimelock.sol";
import {ExecutableProposals} from "contracts/libraries/ExecutableProposals.sol";

import {UnitTest} from "test/utils/unit-test.sol";
import {TargetMock} from "test/utils/target-mock.sol";
import {ExternalCallsBuilder, ExternalCall} from "scripts/utils/ExternalCallsBuilder.sol";

contract EmergencyProtectedTimelockUnitTests is UnitTest {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    EmergencyProtectedTimelock private _timelock;
    TargetMock private _targetMock;
    TargetMock private _anotherTargetMock;
    Executor private _executor;

    address private _emergencyActivator = makeAddr("EMERGENCY_ACTIVATION_COMMITTEE");
    address private _emergencyEnactor = makeAddr("EMERGENCY_EXECUTION_COMMITTEE");
    Duration private _emergencyModeDuration = Durations.from(180 days);
    Duration private _emergencyProtectionDuration = Durations.from(90 days);

    address private _emergencyGovernance = makeAddr("EMERGENCY_GOVERNANCE");
    address private _dualGovernance = makeAddr("DUAL_GOVERNANCE");
    address private _adminExecutor;

    EmergencyProtectedTimelock.SanityCheckParams private _defaultSanityCheckParams = EmergencyProtectedTimelock
        .SanityCheckParams({
        minExecutionDelay: Durations.from(4 days),
        maxAfterSubmitDelay: Durations.from(14 days),
        maxAfterScheduleDelay: Durations.from(7 days),
        maxEmergencyModeDuration: Durations.from(365 days),
        maxEmergencyProtectionDuration: Durations.from(365 days)
    });
    Duration private _defaultAfterSubmitDelay = Durations.from(3 days);
    Duration private _defaultAfterScheduleDelay = Durations.from(2 days);

    function setUp() external {
        _executor = new Executor(address(this));
        _adminExecutor = address(_executor);

        _timelock = _deployEmergencyProtectedTimelock();

        _targetMock = new TargetMock();
        _anotherTargetMock = new TargetMock();

        _executor.transferOwnership(address(_timelock));

        vm.startPrank(_adminExecutor);
        _timelock.setGovernance(_dualGovernance);
        _timelock.setEmergencyProtectionActivationCommittee(_emergencyActivator);
        _timelock.setEmergencyProtectionExecutionCommittee(_emergencyEnactor);
        _timelock.setEmergencyProtectionEndDate(_emergencyProtectionDuration.addTo(Timestamps.now()));
        _timelock.setEmergencyModeDuration(_emergencyModeDuration);
        _timelock.setEmergencyGovernance(_emergencyGovernance);
        vm.stopPrank();
    }

    // EmergencyProtectedTimelock.constructor()

    function test_constructor_HappyPath_NonZeroDelays() external {
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams = _defaultSanityCheckParams;

        address adminExecutor = makeAddr("ADMIN_EXECUTOR");
        Duration afterSubmitDelay = _defaultAfterSubmitDelay;
        Duration afterScheduleDelay = _defaultAfterScheduleDelay;

        vm.expectEmit();
        emit TimelockState.AdminExecutorSet(adminExecutor);

        vm.expectEmit();
        emit TimelockState.AfterSubmitDelaySet(afterSubmitDelay);

        vm.expectEmit();
        emit TimelockState.AfterScheduleDelaySet(afterScheduleDelay);

        EmergencyProtectedTimelock timelock =
            new EmergencyProtectedTimelock(sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay);

        _assertEmergencyProtectedTimelockConstructorParams(
            timelock, sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay
        );
    }

    function test_constructor_HappyPath_ZeroDelays() external {
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams = _defaultSanityCheckParams;
        sanityCheckParams.minExecutionDelay = Durations.ZERO;

        address adminExecutor = makeAddr("ADMIN_EXECUTOR");
        Duration afterSubmitDelay = Durations.ZERO;
        Duration afterScheduleDelay = Durations.ZERO;

        vm.expectEmit();
        emit TimelockState.AdminExecutorSet(adminExecutor);

        vm.recordLogs();

        EmergencyProtectedTimelock timelock =
            new EmergencyProtectedTimelock(sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay);

        assertEq(vm.getRecordedLogs().length, 1);

        _assertEmergencyProtectedTimelockConstructorParams(
            timelock, sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay
        );
    }

    function test_constructor_RevertOn_AfterSubmitDelayExceeded() external {
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams = _defaultSanityCheckParams;

        address adminExecutor = makeAddr("ADMIN_EXECUTOR");
        Duration afterSubmitDelay = sanityCheckParams.maxAfterSubmitDelay + Durations.from(1 seconds);
        Duration afterScheduleDelay = sanityCheckParams.maxAfterScheduleDelay;

        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidAfterSubmitDelay.selector, afterSubmitDelay));

        EmergencyProtectedTimelock timelock =
            new EmergencyProtectedTimelock(sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay);
    }

    function test_constructor_RevertOn_AfterScheduleDelayExceeded() external {
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams = _defaultSanityCheckParams;

        address adminExecutor = makeAddr("ADMIN_EXECUTOR");
        Duration afterSubmitDelay = sanityCheckParams.maxAfterSubmitDelay;
        Duration afterScheduleDelay = sanityCheckParams.maxAfterScheduleDelay + Durations.from(1 seconds);

        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidAfterScheduleDelay.selector, afterScheduleDelay));

        EmergencyProtectedTimelock timelock =
            new EmergencyProtectedTimelock(sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay);
    }

    function test_constructor_RevertOn_MinExecutionDelayTooLow() external {
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams = _defaultSanityCheckParams;
        sanityCheckParams.minExecutionDelay = Durations.from(MAX_DURATION_VALUE);

        address adminExecutor = makeAddr("ADMIN_EXECUTOR");
        Duration afterSubmitDelay = _defaultAfterSubmitDelay;
        Duration afterScheduleDelay = _defaultAfterScheduleDelay;

        vm.expectRevert(
            abi.encodeWithSelector(TimelockState.InvalidExecutionDelay.selector, afterSubmitDelay + afterScheduleDelay)
        );

        EmergencyProtectedTimelock timelock =
            new EmergencyProtectedTimelock(sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay);
    }

    function testFuzz_constructor_HappyPath(
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams,
        address adminExecutor,
        Duration afterSubmitDelay,
        Duration afterScheduleDelay
    ) external {
        vm.assume(adminExecutor != address(0));
        vm.assume(afterSubmitDelay <= sanityCheckParams.maxAfterSubmitDelay);
        vm.assume(afterScheduleDelay <= sanityCheckParams.maxAfterScheduleDelay);
        vm.assume(afterSubmitDelay.toSeconds() + afterScheduleDelay.toSeconds() <= MAX_DURATION_VALUE);
        vm.assume(afterSubmitDelay + afterScheduleDelay >= sanityCheckParams.minExecutionDelay);

        EmergencyProtectedTimelock timelock =
            new EmergencyProtectedTimelock(sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay);

        _assertEmergencyProtectedTimelockConstructorParams(
            timelock, sanityCheckParams, adminExecutor, afterSubmitDelay, afterScheduleDelay
        );
    }

    // EmergencyProtectedTimelock.submit()

    function testFuzz_submit_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _dualGovernance);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, [stranger]));
        _timelock.submit(_adminExecutor, new ExternalCall[](0));
        assertEq(_timelock.getProposalsCount(), 0);
    }

    function test_submit_HappyPath() external {
        string memory testMetadata = "testMetadata";

        vm.expectEmit();
        emit ExecutableProposals.ProposalSubmitted(
            1, _adminExecutor, _getMockTargetRegularStaffCalls(address(_targetMock))
        );
        vm.prank(_dualGovernance);
        _timelock.submit(_adminExecutor, _getMockTargetRegularStaffCalls(address(_targetMock)));

        assertEq(_timelock.getProposalsCount(), 1);

        ITimelock.ProposalDetails memory proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Submitted);
    }

    // EmergencyProtectedTimelock.schedule()

    function test_schedule_HappyPath() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        ITimelock.ProposalDetails memory proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Scheduled);
    }

    function testFuzz_schedule_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        vm.assume(stranger != address(0));

        _submitProposal();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, [stranger]));

        _timelock.schedule(1);

        ITimelock.ProposalDetails memory proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Submitted);
    }

    // EmergencyProtectedTimelock.execute()

    function testFuzz_execute_HappyPath(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        vm.assume(stranger != address(0));

        _submitProposal();
        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        _wait(_timelock.getAfterScheduleDelay());

        vm.prank(stranger);
        _timelock.execute(1);

        ITimelock.ProposalDetails memory proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Executed);
    }

    function test_execute_RevertOn_EmergencyModeIsActive() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());
        _scheduleProposal(1);

        _wait(_timelock.getAfterScheduleDelay());

        _activateEmergencyMode();

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
        _timelock.execute(1);

        ITimelock.ProposalDetails memory proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Scheduled);
    }

    function test_execute_ProposalExecutionBeforeMinExecutionDelayPassedForbidden() external {
        Duration initialAfterSubmitDelay = Durations.ZERO;
        Duration initialAfterScheduleDelay = _defaultSanityCheckParams.minExecutionDelay;

        Duration newAfterSubmitDelay = _defaultSanityCheckParams.minExecutionDelay;
        Duration newAfterScheduleDelay = Durations.ZERO;

        // prepare timelock instance timings
        vm.startPrank(_adminExecutor);
        _timelock.setAfterScheduleDelay(initialAfterScheduleDelay);
        _timelock.setAfterSubmitDelay(initialAfterSubmitDelay);
        vm.stopPrank();

        assertEq(_timelock.getAfterSubmitDelay(), initialAfterSubmitDelay);
        assertEq(_timelock.getAfterScheduleDelay(), initialAfterScheduleDelay);

        ExternalCallsBuilder.Context memory callsBuilder = ExternalCallsBuilder.create(2);
        callsBuilder.addCall(address(_timelock), abi.encodeCall(_timelock.setAfterSubmitDelay, newAfterSubmitDelay));
        callsBuilder.addCall(address(_timelock), abi.encodeCall(_timelock.setAfterScheduleDelay, newAfterScheduleDelay));

        // submit proposal to update delay durations
        vm.startPrank(_dualGovernance);
        uint256 updateDelaysProposalId = _timelock.submit(_adminExecutor, callsBuilder.getResult());
        vm.stopPrank();

        // as the current after submit delay is 0, proposal may be instantly scheduled
        assertTrue(_timelock.canSchedule(updateDelaysProposalId));

        vm.prank(_dualGovernance);
        _timelock.schedule(updateDelaysProposalId);

        assertFalse(_timelock.canExecute(updateDelaysProposalId));

        _wait(_timelock.getAfterScheduleDelay());

        assertTrue(_timelock.canExecute(updateDelaysProposalId));

        // at the end of the after schedule delay submit another proposal
        vm.startPrank(_dualGovernance);
        uint256 otherProposalId =
            _timelock.submit(_adminExecutor, _getMockTargetRegularStaffCalls(address(_targetMock)));
        vm.stopPrank();

        // as the proposal to update delays hasn't executed yet and after submit delay is 0
        // new proposal may be scheduled just after submit
        assertTrue(_timelock.canSchedule(otherProposalId));

        vm.prank(_dualGovernance);
        _timelock.schedule(otherProposalId);

        assertFalse(_timelock.canExecute(otherProposalId));

        _timelock.execute(updateDelaysProposalId);
        assertEq(_timelock.getAfterSubmitDelay(), newAfterSubmitDelay);
        assertEq(_timelock.getAfterScheduleDelay(), newAfterScheduleDelay);

        // after the execution of the proposal with the delays update, proposal submitted
        // just before execution can't be executed, due to min execution delay constraint
        assertFalse(_timelock.canExecute(otherProposalId));

        vm.expectRevert(
            abi.encodeWithSelector(ExecutableProposals.MinExecutionDelayNotPassed.selector, otherProposalId)
        );
        _timelock.execute(otherProposalId);

        _wait(_timelock.MIN_EXECUTION_DELAY());
        _timelock.execute(otherProposalId);

        // after min execution delay has passed, proposal may be executed
        assertEq(_targetMock.getCallsLength(), 1);
    }

    // EmergencyProtectedTimelock.cancelAllNonExecutedProposals()

    function test_cancelAllNonExecutedProposals_HappyPath() external {
        _submitProposal();
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 2);

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        ITimelock.ProposalDetails memory proposal1 = _timelock.getProposalDetails(1);
        ITimelock.ProposalDetails memory proposal2 = _timelock.getProposalDetails(2);

        assertEq(proposal1.status, ProposalStatus.Scheduled);
        assertEq(proposal2.status, ProposalStatus.Submitted);

        vm.prank(_dualGovernance);
        _timelock.cancelAllNonExecutedProposals();

        proposal1 = _timelock.getProposalDetails(1);
        proposal2 = _timelock.getProposalDetails(2);

        assertEq(_timelock.getProposalsCount(), 2);
        assertEq(proposal1.status, ProposalStatus.Cancelled);
        assertEq(proposal2.status, ProposalStatus.Cancelled);
    }

    function testFuzz_cancelAllNonExecutedProposals_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _dualGovernance);
        vm.assume(stranger != address(0));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, [stranger]));

        _timelock.cancelAllNonExecutedProposals();
    }

    // EmergencyProtectedTimelock.setAfterSubmitDelay()

    function test_setAfterSubmitDelay_HappyPath() external {
        Duration newAfterSubmitDelay = _timelock.getAfterSubmitDelay() + Durations.from(1 seconds);

        vm.expectEmit();
        emit TimelockState.AfterSubmitDelaySet(newAfterSubmitDelay);

        vm.prank(_adminExecutor);
        _timelock.setAfterSubmitDelay(newAfterSubmitDelay);

        assertEq(_timelock.getAfterSubmitDelay(), newAfterSubmitDelay);
    }

    function test_setAfterSubmitDelay_RevertOn_MaxAfterSubmitDelayExceeded() external {
        Duration newAfterSubmitDelay = _defaultSanityCheckParams.maxAfterSubmitDelay + Durations.from(1 seconds);

        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidAfterSubmitDelay.selector, newAfterSubmitDelay));

        vm.prank(_adminExecutor);
        _timelock.setAfterSubmitDelay(newAfterSubmitDelay);
    }

    function test_setAfterSubmitDelay_RevertOn_ExecutionDelayTooLow() external {
        Duration afterScheduleDelay = _timelock.getAfterScheduleDelay();
        Duration newAfterSubmitDelay = (_defaultSanityCheckParams.minExecutionDelay - afterScheduleDelay).dividedBy(2);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockState.InvalidExecutionDelay.selector, newAfterSubmitDelay + afterScheduleDelay
            )
        );

        vm.prank(_adminExecutor);
        _timelock.setAfterSubmitDelay(newAfterSubmitDelay);
    }

    function test_setAfterSubmitDelay_RevertOn_CalledNotByAdminExecutor() external {
        Duration newAfterSubmitDelay = _defaultSanityCheckParams.maxAfterSubmitDelay + Durations.from(1 seconds);

        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, address(this)));
        _timelock.setAfterSubmitDelay(newAfterSubmitDelay);
    }

    function testFuzz_setAfterSubmitDelay_HappyPath(
        Duration newAfterSubmitDelay,
        Duration newAfterScheduleDelay
    ) external {
        Duration prevAfterSubmitDelay = _timelock.getAfterSubmitDelay();
        Duration prevAfterScheduleDelay = _timelock.getAfterScheduleDelay();

        // Update the after schedule delay in the default setup to increase "randomness" of the fuzz test
        vm.assume(prevAfterScheduleDelay != newAfterScheduleDelay);
        vm.assume(newAfterScheduleDelay <= _defaultSanityCheckParams.maxAfterScheduleDelay);
        vm.assume(prevAfterSubmitDelay + newAfterScheduleDelay >= _defaultSanityCheckParams.minExecutionDelay);

        vm.prank(_adminExecutor);
        _timelock.setAfterScheduleDelay(newAfterScheduleDelay);
        assertEq(_timelock.getAfterScheduleDelay(), newAfterScheduleDelay);

        vm.assume(newAfterSubmitDelay != prevAfterSubmitDelay);
        vm.assume(newAfterSubmitDelay <= _defaultSanityCheckParams.maxAfterSubmitDelay);
        vm.assume(newAfterSubmitDelay + newAfterScheduleDelay >= _defaultSanityCheckParams.minExecutionDelay);

        vm.prank(_adminExecutor);
        _timelock.setAfterSubmitDelay(newAfterSubmitDelay);

        assertEq(_timelock.getAfterSubmitDelay(), newAfterSubmitDelay);
    }

    // EmergencyProtectedTimelock.setAfterScheduleDelay()

    function test_setAfterScheduleDelay_HappyPath() external {
        Duration newAfterScheduleDelay = _timelock.getAfterScheduleDelay() + Durations.from(1 seconds);

        vm.expectEmit();
        emit TimelockState.AfterScheduleDelaySet(newAfterScheduleDelay);

        vm.prank(_adminExecutor);
        _timelock.setAfterScheduleDelay(newAfterScheduleDelay);

        assertEq(_timelock.getAfterScheduleDelay(), newAfterScheduleDelay);
    }

    function test_setAfterScheduleDelay_RevertOn_MaxAfterScheduleDelayExceeded() external {
        Duration newAfterScheduleDelay = _defaultSanityCheckParams.maxAfterScheduleDelay + Durations.from(1 seconds);

        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidAfterScheduleDelay.selector, newAfterScheduleDelay));

        vm.prank(_adminExecutor);
        _timelock.setAfterScheduleDelay(newAfterScheduleDelay);
    }

    function test_setAfterScheduleDelay_RevertOn_ExecutionDelayTooLow() external {
        Duration afterSubmitDelay = _timelock.getAfterSubmitDelay();
        Duration newAfterScheduleDelay = (_defaultSanityCheckParams.minExecutionDelay - afterSubmitDelay).dividedBy(2);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockState.InvalidExecutionDelay.selector, newAfterScheduleDelay + afterSubmitDelay
            )
        );

        vm.prank(_adminExecutor);
        _timelock.setAfterScheduleDelay(newAfterScheduleDelay);
    }

    function test_setAfterScheduleDelay_RevertOn_CalledNotByAdminExecutor() external {
        Duration newAfterScheduleDelay = _defaultSanityCheckParams.maxAfterScheduleDelay + Durations.from(1 seconds);

        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, address(this)));
        _timelock.setAfterScheduleDelay(newAfterScheduleDelay);
    }

    function testFuzz_setAfterScheduleDelay_HappyPath(
        Duration newAfterSubmitDelay,
        Duration newAfterScheduleDelay
    ) external {
        Duration prevAfterSubmitDelay = _timelock.getAfterSubmitDelay();
        Duration prevAfterScheduleDelay = _timelock.getAfterScheduleDelay();

        // Update the after submit delay in the default setup to increase "randomness" of the fuzz test
        vm.assume(newAfterSubmitDelay != prevAfterSubmitDelay);
        vm.assume(newAfterSubmitDelay <= _defaultSanityCheckParams.maxAfterSubmitDelay);
        vm.assume(newAfterSubmitDelay + prevAfterScheduleDelay >= _defaultSanityCheckParams.minExecutionDelay);

        vm.prank(_adminExecutor);
        _timelock.setAfterSubmitDelay(newAfterSubmitDelay);

        assertEq(_timelock.getAfterSubmitDelay(), newAfterSubmitDelay);

        vm.assume(prevAfterScheduleDelay != newAfterScheduleDelay);
        vm.assume(newAfterScheduleDelay <= _defaultSanityCheckParams.maxAfterScheduleDelay);
        vm.assume(newAfterSubmitDelay + newAfterScheduleDelay >= _defaultSanityCheckParams.minExecutionDelay);

        vm.prank(_adminExecutor);
        _timelock.setAfterScheduleDelay(newAfterScheduleDelay);

        assertEq(_timelock.getAfterScheduleDelay(), newAfterScheduleDelay);
    }

    // EmergencyProtectedTimelock.transferExecutorOwnership()

    function testFuzz_transferExecutorOwnership_HappyPath(address newOwner) external {
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

    function test_transferExecutorOwnership_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, stranger));
        _timelock.transferExecutorOwnership(_adminExecutor, makeAddr("newOwner"));
    }

    // EmergencyProtectedTimelock.setGovernance()

    function testFuzz_setGovernance_HappyPath(address newGovernance) external {
        vm.assume(newGovernance != _dualGovernance);
        vm.assume(newGovernance != address(0));

        vm.expectEmit(address(_timelock));
        emit TimelockState.GovernanceSet(newGovernance);

        vm.expectEmit(address(_timelock));
        emit ExecutableProposals.ProposalsCancelledTill(0);

        vm.recordLogs();
        vm.prank(_adminExecutor);
        _timelock.setGovernance(newGovernance);

        assertEq(_timelock.getGovernance(), newGovernance);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);
    }

    function test_setGovernance_RevertOn_ZeroAddress() external {
        vm.prank(_adminExecutor);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidGovernance.selector, address(0)));
        _timelock.setGovernance(address(0));
    }

    function test_setGovernance_RevertOn_SameAddress() external {
        address currentGovernance = _timelock.getGovernance();
        vm.prank(_adminExecutor);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.InvalidGovernance.selector, _dualGovernance));
        _timelock.setGovernance(currentGovernance);

        assertEq(_timelock.getGovernance(), currentGovernance);
    }

    function testFuzz_setGovernance_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, stranger));
        _timelock.setGovernance(makeAddr("newGovernance"));
    }

    // EmergencyProtectedTimelock.activateEmergencyMode()

    function test_activateEmergencyMode_HappyPath() external {
        vm.prank(_emergencyActivator);
        _timelock.activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);
    }

    function testFuzz_activateEmergencyMode_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _emergencyActivator);
        vm.assume(stranger != address(0));

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyActivationCommittee.selector, stranger)
        );
        _timelock.activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), false);
    }

    function test_activateEmergencyMode_RevertOn_AlreadyActive() external {
        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(_emergencyActivator);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
        _timelock.activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);
    }

    // EmergencyProtectedTimelock.emergencyExecute()

    function test_emergencyExecute_HappyPath() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());

        _scheduleProposal(1);

        _wait(_timelock.getAfterScheduleDelay());

        _activateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(_emergencyEnactor);
        _timelock.emergencyExecute(1);

        ITimelock.ProposalDetails memory proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Executed);
    }

    function test_emergencyExecute_RevertOn_ModeNotActive() external {
        vm.startPrank(_dualGovernance);
        _timelock.submit(_adminExecutor, _getMockTargetRegularStaffCalls(address(_targetMock)));

        assertEq(_timelock.getProposalsCount(), 1);

        _wait(_timelock.getAfterSubmitDelay());
        _timelock.schedule(1);

        _wait(_timelock.getAfterScheduleDelay());
        vm.stopPrank();

        assertEq(_timelock.isEmergencyModeActive(), false);

        vm.prank(_emergencyActivator);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
        _timelock.emergencyExecute(1);
    }

    function testFuzz_emergencyExecute_RevertOn_ByStranger(address stranger) external {
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

    function test_deactivateEmergencyMode_HappyPath() external {
        _submitProposal();
        _activateEmergencyMode();

        vm.prank(_adminExecutor);
        _timelock.deactivateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), false);
    }

    function test_deactivateEmergencyMode_AllProposalsCancelled() external {
        _submitProposal();

        assertEq(_timelock.getProposalsCount(), 1);

        ITimelock.ProposalDetails memory proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Submitted);

        _activateEmergencyMode();

        _deactivateEmergencyMode();

        proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Cancelled);
    }

    function testFuzz_deactivateEmergencyMode_HappyPath_ByStranger(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        _activateEmergencyMode();

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory state = _timelock.getEmergencyProtectionDetails();
        assertEq(_isEmergencyStateActivated(), true);

        _wait(state.emergencyModeDuration.plusSeconds(1));

        vm.prank(stranger);
        _timelock.deactivateEmergencyMode();

        assertEq(_isEmergencyStateActivated(), false);
    }

    function testFuzz_deactivateEmergencyMode_RevertOn_ModeNotActivated(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
        _timelock.deactivateEmergencyMode();

        vm.prank(_adminExecutor);
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
        _timelock.deactivateEmergencyMode();
    }

    function testFuzz_deactivateEmergencyMode_RevertOn_ByStranger_ModeNotExpired(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        _activateEmergencyMode();
        assertEq(_isEmergencyStateActivated(), true);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, stranger));
        _timelock.deactivateEmergencyMode();
    }

    // EmergencyProtectedTimelock.emergencyReset()

    function test_emergencyReset_HappyPath() external {
        _activateEmergencyMode();
        assertEq(_isEmergencyStateActivated(), true);
        assertEq(_timelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyEnactor);
        _timelock.emergencyReset();

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory newState =
            _timelock.getEmergencyProtectionDetails();

        assertEq(_isEmergencyStateActivated(), false);
        assertEq(_timelock.getGovernance(), _emergencyGovernance);
        assertEq(_timelock.isEmergencyProtectionEnabled(), false);

        assertEq(_timelock.getEmergencyActivationCommittee(), address(0));
        assertEq(_timelock.getEmergencyExecutionCommittee(), address(0));
        assertEq(newState.emergencyProtectionEndsAfter, Timestamps.ZERO);
        assertEq(newState.emergencyModeDuration, Durations.ZERO);
        assertEq(newState.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_emergencyReset_HappyPath_AllProposalsCancelled() external {
        _submitProposal();
        _activateEmergencyMode();

        ITimelock.ProposalDetails memory proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Submitted);

        vm.prank(_emergencyEnactor);
        _timelock.emergencyReset();

        proposal = _timelock.getProposalDetails(1);
        assertEq(proposal.status, ProposalStatus.Cancelled);
    }

    function testFuzz_emergencyReset_RevertOn_ByStranger(address stranger) external {
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

    function test_emergencyReset_RevertOn_ModeNotActivated() external {
        assertEq(_isEmergencyStateActivated(), false);

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory state = _timelock.getEmergencyProtectionDetails();
        address emergencyActivationCommitteeBefore = _timelock.getEmergencyActivationCommittee();
        address emergencyExecutionCommitteeBefore = _timelock.getEmergencyExecutionCommittee();

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
        vm.prank(_emergencyEnactor);
        _timelock.emergencyReset();

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory newState =
            _timelock.getEmergencyProtectionDetails();

        assertEq(_timelock.getEmergencyActivationCommittee(), emergencyActivationCommitteeBefore);
        assertEq(_timelock.getEmergencyExecutionCommittee(), emergencyExecutionCommitteeBefore);
        assertEq(newState.emergencyProtectionEndsAfter, state.emergencyProtectionEndsAfter);
        assertEq(newState.emergencyModeEndsAfter, state.emergencyModeEndsAfter);
        assertEq(newState.emergencyModeDuration, state.emergencyModeDuration);
        assertFalse(_timelock.isEmergencyModeActive());
    }

    // EmergencyProtectedTimelock.setEmergencyProtectionActivationCommittee()

    function test_setActivationCommittee_HappyPath() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.startPrank(_adminExecutor);
        _localTimelock.setEmergencyProtectionActivationCommittee(_emergencyActivator);
        vm.stopPrank();

        assertEq(_timelock.getEmergencyActivationCommittee(), _emergencyActivator);
        assertFalse(_timelock.isEmergencyModeActive());
    }

    function testFuzz_setActivationCommittee_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _adminExecutor);
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, stranger));
        vm.prank(stranger);
        _localTimelock.setEmergencyProtectionActivationCommittee(_emergencyActivator);

        assertEq(_localTimelock.getEmergencyActivationCommittee(), address(0));
        assertFalse(_localTimelock.isEmergencyModeActive());
    }

    // EmergencyProtectedTimelock.setEmergencyProtectionExecutionCommittee()

    function test_setExecutionCommittee_HappyPath() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.startPrank(_adminExecutor);
        _localTimelock.setEmergencyProtectionExecutionCommittee(_emergencyEnactor);
        vm.stopPrank();

        assertEq(_timelock.getEmergencyExecutionCommittee(), _emergencyEnactor);
        assertFalse(_localTimelock.isEmergencyModeActive());
    }

    function testFuzz_setExecutionCommittee_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _adminExecutor && stranger != _emergencyEnactor);
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, stranger));
        vm.prank(stranger);
        _localTimelock.setEmergencyProtectionExecutionCommittee(_emergencyEnactor);

        assertEq(_localTimelock.getEmergencyExecutionCommittee(), address(0));
        assertFalse(_localTimelock.isEmergencyModeActive());
    }

    // EmergencyProtectedTimelock.setEmergencyProtectionEndDate()

    function test_setProtectionEndDate_HappyPath() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.startPrank(_adminExecutor);
        _localTimelock.setEmergencyProtectionEndDate(_emergencyProtectionDuration.addTo(Timestamps.now()));
        vm.stopPrank();

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory state =
            _localTimelock.getEmergencyProtectionDetails();

        assertEq(state.emergencyProtectionEndsAfter, _emergencyProtectionDuration.addTo(Timestamps.now()));
        assertFalse(_localTimelock.isEmergencyModeActive());
    }

    function testFuzz_setProtectionEndDate_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _adminExecutor);
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, stranger));
        vm.prank(stranger);
        _localTimelock.setEmergencyProtectionEndDate(_emergencyProtectionDuration.addTo(Timestamps.now()));

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory state =
            _localTimelock.getEmergencyProtectionDetails();

        assertEq(state.emergencyProtectionEndsAfter, Timestamps.ZERO);
        assertFalse(_localTimelock.isEmergencyModeActive());
    }

    // EmergencyProtectedTimelock.setEmergencyModeDuration()

    function test_setModeDuration_HappyPath() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.startPrank(_adminExecutor);
        _localTimelock.setEmergencyModeDuration(_emergencyModeDuration);
        vm.stopPrank();

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory state =
            _localTimelock.getEmergencyProtectionDetails();

        assertEq(state.emergencyModeDuration, _emergencyModeDuration);
        assertFalse(_localTimelock.isEmergencyModeActive());
    }

    function testFuzz_setModeDuration_RevertOn_ByStranger(address stranger) external {
        vm.assume(stranger != _adminExecutor);
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, stranger));
        vm.prank(stranger);
        _localTimelock.setEmergencyModeDuration(_emergencyModeDuration);

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory state =
            _localTimelock.getEmergencyProtectionDetails();

        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertFalse(_localTimelock.isEmergencyModeActive());
    }

    // EmergencyProtectedTimelock.isEmergencyProtectionEnabled()

    function test_is_emergency_protection_enabled_deactivate() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), false);

        vm.startPrank(_adminExecutor);
        _localTimelock.setEmergencyProtectionActivationCommittee(_emergencyActivator);
        _localTimelock.setEmergencyProtectionExecutionCommittee(_emergencyEnactor);
        _localTimelock.setEmergencyProtectionEndDate(_emergencyProtectionDuration.addTo(Timestamps.now()));
        _localTimelock.setEmergencyModeDuration(_emergencyModeDuration);
        vm.stopPrank();

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

        vm.startPrank(_adminExecutor);
        _localTimelock.setEmergencyProtectionActivationCommittee(_emergencyActivator);
        _localTimelock.setEmergencyProtectionExecutionCommittee(_emergencyEnactor);
        _localTimelock.setEmergencyProtectionEndDate(_emergencyProtectionDuration.addTo(Timestamps.now()));
        _localTimelock.setEmergencyModeDuration(_emergencyModeDuration);
        _localTimelock.setEmergencyGovernance(_emergencyGovernance);
        vm.stopPrank();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), true);

        vm.prank(_emergencyEnactor);
        _localTimelock.emergencyReset();

        assertEq(_localTimelock.isEmergencyProtectionEnabled(), false);
    }

    // EmergencyProtectedTimelock.getEmergencyProtectionDetails()

    function test_get_emergency_state_deactivate() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory state =
            _localTimelock.getEmergencyProtectionDetails();

        assertFalse(_localTimelock.isEmergencyModeActive());
        assertEq(_localTimelock.getEmergencyActivationCommittee(), address(0));
        assertEq(_localTimelock.getEmergencyExecutionCommittee(), address(0));
        assertEq(state.emergencyProtectionEndsAfter, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);

        vm.startPrank(_adminExecutor);
        _localTimelock.setEmergencyProtectionActivationCommittee(_emergencyActivator);
        _localTimelock.setEmergencyProtectionExecutionCommittee(_emergencyEnactor);
        _localTimelock.setEmergencyProtectionEndDate(_emergencyProtectionDuration.addTo(Timestamps.now()));
        _localTimelock.setEmergencyModeDuration(_emergencyModeDuration);
        vm.stopPrank();

        state = _localTimelock.getEmergencyProtectionDetails();

        assertEq(_localTimelock.isEmergencyModeActive(), false);
        assertEq(_localTimelock.getEmergencyActivationCommittee(), _emergencyActivator);
        assertEq(_localTimelock.getEmergencyExecutionCommittee(), _emergencyEnactor);
        assertEq(state.emergencyProtectionEndsAfter, _emergencyProtectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeDuration, _emergencyModeDuration);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        state = _localTimelock.getEmergencyProtectionDetails();

        assertEq(_localTimelock.isEmergencyModeActive(), true);
        assertEq(_localTimelock.getEmergencyExecutionCommittee(), _emergencyEnactor);
        assertEq(_localTimelock.getEmergencyActivationCommittee(), _emergencyActivator);
        assertEq(state.emergencyModeDuration, _emergencyModeDuration);
        assertEq(state.emergencyProtectionEndsAfter, _emergencyProtectionDuration.addTo(Timestamps.now()));
        assertEq(state.emergencyModeEndsAfter, _emergencyModeDuration.addTo(Timestamps.now()));

        vm.prank(_adminExecutor);
        _localTimelock.deactivateEmergencyMode();

        state = _localTimelock.getEmergencyProtectionDetails();

        assertFalse(_timelock.isEmergencyModeActive());
        assertEq(_localTimelock.getEmergencyActivationCommittee(), address(0));
        assertEq(_localTimelock.getEmergencyExecutionCommittee(), address(0));
        assertEq(state.emergencyProtectionEndsAfter, Timestamps.ZERO);
        assertEq(state.emergencyModeDuration, Durations.ZERO);
        assertEq(state.emergencyModeEndsAfter, Timestamps.ZERO);
    }

    function test_get_emergency_state_reset() external {
        EmergencyProtectedTimelock _localTimelock = _deployEmergencyProtectedTimelock();

        vm.startPrank(_adminExecutor);
        _localTimelock.setEmergencyProtectionActivationCommittee(_emergencyActivator);
        _localTimelock.setEmergencyProtectionExecutionCommittee(_emergencyEnactor);
        _localTimelock.setEmergencyProtectionEndDate(_emergencyProtectionDuration.addTo(Timestamps.now()));
        _localTimelock.setEmergencyModeDuration(_emergencyModeDuration);
        _localTimelock.setEmergencyGovernance(_emergencyGovernance);
        vm.stopPrank();

        vm.prank(_emergencyActivator);
        _localTimelock.activateEmergencyMode();

        vm.prank(_emergencyEnactor);
        _localTimelock.emergencyReset();

        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory state =
            _localTimelock.getEmergencyProtectionDetails();

        assertFalse(_localTimelock.isEmergencyModeActive());
        assertEq(_localTimelock.getEmergencyActivationCommittee(), address(0));
        assertEq(_localTimelock.getEmergencyExecutionCommittee(), address(0));
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

    // EmergencyProtectedTimelock.getProposalDetails()

    function test_get_proposal() external {
        assertEq(_timelock.getProposalsCount(), 0);

        vm.startPrank(_dualGovernance);
        ExternalCall[] memory executorCalls = _getMockTargetRegularStaffCalls(address(_targetMock));
        ExternalCall[] memory anotherExecutorCalls = _getMockTargetRegularStaffCalls(address(_anotherTargetMock));
        _timelock.submit(_adminExecutor, executorCalls);
        _timelock.submit(_adminExecutor, anotherExecutorCalls);

        (ITimelock.ProposalDetails memory submittedProposal, ExternalCall[] memory calls) = _timelock.getProposal(1);

        Timestamp submitTimestamp = Timestamps.now();

        assertEq(submittedProposal.id, 1);
        assertEq(submittedProposal.executor, _adminExecutor);
        assertEq(submittedProposal.submittedAt, submitTimestamp);
        assertEq(submittedProposal.scheduledAt, Timestamps.ZERO);
        assertEq(submittedProposal.status, ProposalStatus.Submitted);
        assertEq(calls.length, 1);
        assertEq(calls[0].value, executorCalls[0].value);
        assertEq(calls[0].target, executorCalls[0].target);
        assertEq(calls[0].payload, executorCalls[0].payload);

        _wait(_timelock.getAfterSubmitDelay());

        _timelock.schedule(1);
        Timestamp scheduleTimestamp = Timestamps.now();

        (ITimelock.ProposalDetails memory scheduledProposal, ExternalCall[] memory scheduledCalls) =
            _timelock.getProposal(1);

        assertEq(scheduledProposal.id, 1);
        assertEq(scheduledProposal.executor, _adminExecutor);
        assertEq(scheduledProposal.submittedAt, submitTimestamp);
        assertEq(scheduledProposal.scheduledAt, scheduleTimestamp);
        assertEq(scheduledProposal.status, ProposalStatus.Scheduled);
        assertEq(scheduledCalls.length, 1);
        assertEq(scheduledCalls[0].value, executorCalls[0].value);
        assertEq(scheduledCalls[0].target, executorCalls[0].target);
        assertEq(scheduledCalls[0].payload, executorCalls[0].payload);

        _wait(_timelock.getAfterScheduleDelay());

        _timelock.execute(1);

        (ITimelock.ProposalDetails memory executedProposal, ExternalCall[] memory executedCalls) =
            _timelock.getProposal(1);
        Timestamp executeTimestamp = Timestamps.now();

        assertEq(executedProposal.id, 1);
        assertEq(executedProposal.status, ProposalStatus.Executed);
        assertEq(executedProposal.executor, _adminExecutor);
        assertEq(executedProposal.submittedAt, submitTimestamp);
        assertEq(executedProposal.scheduledAt, scheduleTimestamp);
        // assertEq(executedProposal.executedAt, executeTimestamp);
        // assertEq doesn't support comparing enumerables so far
        assertEq(executedCalls.length, 1);
        assertEq(executedCalls[0].value, executorCalls[0].value);
        assertEq(executedCalls[0].target, executorCalls[0].target);
        assertEq(executedCalls[0].payload, executorCalls[0].payload);

        _timelock.cancelAllNonExecutedProposals();

        (ITimelock.ProposalDetails memory cancelledProposal, ExternalCall[] memory cancelledCalls) =
            _timelock.getProposal(2);

        assertEq(cancelledProposal.id, 2);
        assertEq(cancelledProposal.status, ProposalStatus.Cancelled);
        assertEq(cancelledProposal.executor, _adminExecutor);
        assertEq(cancelledProposal.submittedAt, submitTimestamp);
        assertEq(cancelledProposal.scheduledAt, Timestamps.ZERO);
        // assertEq(cancelledProposal.executedAt, Timestamps.ZERO);
        // assertEq doesn't support comparing enumerables so far
        assertEq(cancelledCalls.length, 1);
        assertEq(cancelledCalls[0].value, anotherExecutorCalls[0].value);
        assertEq(cancelledCalls[0].target, anotherExecutorCalls[0].target);
        assertEq(cancelledCalls[0].payload, anotherExecutorCalls[0].payload);
    }

    function test_get_not_existing_proposal() external {
        assertEq(_timelock.getProposalsCount(), 0);

        vm.expectRevert();
        _timelock.getProposalDetails(1);
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
        assertEq(_timelock.getProposalDetails(1).submittedAt, Timestamps.now());
    }

    function test_getProposalInfo() external {
        _submitProposal();

        ITimelock.ProposalDetails memory proposalDetails = _timelock.getProposalDetails(1);

        assertEq(proposalDetails.id, 1);
        assert(proposalDetails.status == ProposalStatus.Submitted);
        assertEq(proposalDetails.executor, _adminExecutor);
        assertEq(proposalDetails.submittedAt, Timestamps.from(block.timestamp));
        assertEq(proposalDetails.scheduledAt, Timestamps.from(0));
    }

    function test_getProposalCalls() external {
        ExternalCall[] memory executorCalls = _getMockTargetRegularStaffCalls(address(_targetMock));
        vm.prank(_dualGovernance);
        _timelock.submit(_adminExecutor, executorCalls);

        ExternalCall[] memory calls = _timelock.getProposalCalls(1);

        assertEq(calls.length, executorCalls.length);
        assertEq(calls[0].target, executorCalls[0].target);
        assertEq(calls[0].value, executorCalls[0].value);
        assertEq(calls[0].payload, executorCalls[0].payload);
    }

    function testFuzz_getAdminExecutor(address executor) external {
        vm.assume(executor != address(0));
        Duration afterSubmitDelay = Durations.from(3 days);
        Duration afterScheduleDelay = Durations.from(1 days);

        EmergencyProtectedTimelock timelock = new EmergencyProtectedTimelock(
            EmergencyProtectedTimelock.SanityCheckParams({
                minExecutionDelay: Durations.from(0 seconds),
                maxAfterSubmitDelay: Durations.from(45 days),
                maxAfterScheduleDelay: Durations.from(45 days),
                maxEmergencyModeDuration: Durations.from(365 days),
                maxEmergencyProtectionDuration: Durations.from(365 days)
            }),
            executor,
            afterSubmitDelay,
            afterScheduleDelay
        );

        assertEq(timelock.getAdminExecutor(), executor);
    }

    function testFuzz_setAdminExecutor_HappyPath(address adminExecutor) external {
        vm.assume(adminExecutor != _adminExecutor && adminExecutor != address(0));
        vm.prank(_adminExecutor);
        _timelock.setAdminExecutor(adminExecutor);

        assertEq(_timelock.getAdminExecutor(), adminExecutor);
    }

    function test_setAdminExecutor_RevertOn_NotAdminExecutor(address stranger) external {
        vm.assume(stranger != _adminExecutor);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, stranger));
        _timelock.setAdminExecutor(address(0x123));
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
            _defaultSanityCheckParams, _adminExecutor, _defaultAfterSubmitDelay, _defaultAfterScheduleDelay
        );
    }

    function _assertEmergencyProtectedTimelockConstructorParams(
        EmergencyProtectedTimelock timelock,
        EmergencyProtectedTimelock.SanityCheckParams memory sanityCheckParams,
        address adminExecutor,
        Duration afterSubmitDelay,
        Duration afterScheduleDelay
    ) internal {
        assertEq(timelock.getAdminExecutor(), adminExecutor, "Unexpected 'adminExecutor' value");
        assertEq(timelock.getAfterSubmitDelay(), afterSubmitDelay, "Unexpected 'afterSubmitDelay' value");
        assertEq(timelock.getAfterScheduleDelay(), afterScheduleDelay, "Unexpected 'afterScheduleDelay' value");

        assertEq(
            timelock.MIN_EXECUTION_DELAY(),
            sanityCheckParams.minExecutionDelay,
            "Unexpected 'MIN_EXECUTION_DELAY' value"
        );
        assertEq(
            timelock.MAX_AFTER_SUBMIT_DELAY(),
            sanityCheckParams.maxAfterSubmitDelay,
            "Unexpected 'MAX_AFTER_SUBMIT_DELAY' value"
        );
        assertEq(
            timelock.MAX_AFTER_SCHEDULE_DELAY(),
            sanityCheckParams.maxAfterScheduleDelay,
            "Unexpected 'MAX_AFTER_SCHEDULE_DELAY' value"
        );
        assertEq(
            timelock.MAX_EMERGENCY_MODE_DURATION(),
            sanityCheckParams.maxEmergencyModeDuration,
            "Unexpected 'MAX_EMERGENCY_MODE_DURATION' value"
        );
        assertEq(
            timelock.MAX_EMERGENCY_PROTECTION_DURATION(),
            sanityCheckParams.maxEmergencyProtectionDuration,
            "Unexpected 'MAX_EMERGENCY_PROTECTION_DURATION' value"
        );
    }
}
