pragma solidity 0.8.26;

import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {Executor} from "contracts/Executor.sol";
import {IEmergencyProtectedTimelock} from "contracts/interfaces/IEmergencyProtectedTimelock.sol";
import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {EmergencyProtection} from "contracts/libraries/EmergencyProtection.sol";
import {ExecutableProposals, Status} from "contracts/libraries/ExecutableProposals.sol";
import {ExternalCall} from "contracts/libraries/ExternalCalls.sol";
import {TimelockState} from "contracts/libraries/TimelockState.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {DualGovernanceSetUp} from "test/kontrol/DualGovernanceSetUp.sol";

/**
 * Simple example contract to use for the proposal execution tests.
 */
contract FlagSetter {
    bool public flag;

    function setFlag(bool value) external {
        flag = value;
    }
}

/**
 * Test postconditions for all EmergencyProtectedTimelock functions, including
 * that they don't modify storage variables that they shouldn't.
 */
contract TimelockInvariantsTest is DualGovernanceSetUp {
    function _saveTimelockState(EmergencyProtectedTimelock timelock)
        internal
        returns (TimelockState.Context memory state)
    {
        state.governance = timelock.getGovernance();
        state.afterSubmitDelay = timelock.getAfterSubmitDelay();
        state.afterScheduleDelay = timelock.getAfterScheduleDelay();
        state.adminExecutor = timelock.getAdminExecutor();
    }

    function _saveEmergencyProtection(EmergencyProtectedTimelock timelock)
        internal
        returns (EmergencyProtection.Context memory state)
    {
        IEmergencyProtectedTimelock.EmergencyProtectionDetails memory details = timelock.getEmergencyProtectionDetails();
        state.emergencyModeEndsAfter = details.emergencyModeEndsAfter;
        state.emergencyActivationCommittee = timelock.getEmergencyActivationCommittee();
        state.emergencyProtectionEndsAfter = details.emergencyProtectionEndsAfter;
        state.emergencyExecutionCommittee = timelock.getEmergencyExecutionCommittee();
        state.emergencyModeDuration = details.emergencyModeDuration;
        state.emergencyGovernance = timelock.getEmergencyGovernance();
    }

    /**
     * This modifier is added to the tests for each EmergencyProtectedTimelock
     * function to check that any variables that the function shouldn't modify
     * remain unchanged.
     */
    modifier _checkStateRemainsUnchanged(bytes4 selector) {
        TimelockState.Context memory preTS = _saveTimelockState(timelock);
        EmergencyProtection.Context memory preEP = _saveEmergencyProtection(timelock);

        _;

        TimelockState.Context memory postTS = _saveTimelockState(timelock);
        EmergencyProtection.Context memory postEP = _saveEmergencyProtection(timelock);

        if (selector != EmergencyProtectedTimelock.setAdminExecutor.selector) {
            assert(preTS.adminExecutor == postTS.adminExecutor);
        }

        if (
            (selector != EmergencyProtectedTimelock.setGovernance.selector)
                && (selector != EmergencyProtectedTimelock.emergencyReset.selector)
        ) {
            assert(preTS.governance == postTS.governance);
        }

        if (selector != EmergencyProtectedTimelock.setAfterSubmitDelay.selector) {
            assert(preTS.afterSubmitDelay == postTS.afterSubmitDelay);
        }

        if (selector != EmergencyProtectedTimelock.setAfterScheduleDelay.selector) {
            assert(preTS.afterScheduleDelay == postTS.afterScheduleDelay);
        }

        if (
            (selector != EmergencyProtectedTimelock.activateEmergencyMode.selector)
                && (selector != EmergencyProtectedTimelock.deactivateEmergencyMode.selector)
                && (selector != EmergencyProtectedTimelock.emergencyReset.selector)
        ) {
            assert(preEP.emergencyModeEndsAfter == postEP.emergencyModeEndsAfter);
        }

        if (
            (selector != EmergencyProtectedTimelock.setEmergencyProtectionActivationCommittee.selector)
                && (selector != EmergencyProtectedTimelock.deactivateEmergencyMode.selector)
                && (selector != EmergencyProtectedTimelock.emergencyReset.selector)
        ) {
            assert(preEP.emergencyActivationCommittee == postEP.emergencyActivationCommittee);
        }

        if (
            (selector != EmergencyProtectedTimelock.setEmergencyProtectionEndDate.selector)
                && (selector != EmergencyProtectedTimelock.deactivateEmergencyMode.selector)
                && (selector != EmergencyProtectedTimelock.emergencyReset.selector)
        ) {
            assert(preEP.emergencyProtectionEndsAfter == postEP.emergencyProtectionEndsAfter);
        }

        if (
            (selector != EmergencyProtectedTimelock.setEmergencyProtectionExecutionCommittee.selector)
                && (selector != EmergencyProtectedTimelock.deactivateEmergencyMode.selector)
                && (selector != EmergencyProtectedTimelock.emergencyReset.selector)
        ) {
            assert(preEP.emergencyExecutionCommittee == postEP.emergencyExecutionCommittee);
        }

        if (
            (selector != EmergencyProtectedTimelock.setEmergencyModeDuration.selector)
                && (selector != EmergencyProtectedTimelock.deactivateEmergencyMode.selector)
                && (selector != EmergencyProtectedTimelock.emergencyReset.selector)
        ) {
            assert(preEP.emergencyModeDuration == postEP.emergencyModeDuration);
        }

        if (selector != EmergencyProtectedTimelock.setEmergencyGovernance.selector) {
            assert(preEP.emergencyGovernance == postEP.emergencyGovernance);
        }
    }

    function testSubmit(
        address executor,
        address target,
        uint96 value,
        bytes4 selector,
        bytes32 argument
    ) external _checkStateRemainsUnchanged(EmergencyProtectedTimelock.submit.selector) {
        bytes memory payload = abi.encodeWithSelector(selector, argument);

        ExternalCall[] memory calls = new ExternalCall[](1);
        calls[0].target = target;
        calls[0].value = value;
        calls[0].payload = payload;

        // Since the storage is fully symbolic we need to reset some storage slots of the new proposal that
        // will be created:
        // - The lenght of `calls` needs to be 0 otherwise the function might revert when pushing another call
        // - The payload slot needs to be set to 0, otherwise the function reverts if the previous (symbolic)
        //   payload is less than 32 bytes and the new one is greater or equal than 32 bytes
        uint256 newProposalId = timelock.getProposalsCount() + 1;
        _setCallsCount(timelock, newProposalId, 0);
        _storeData(address(timelock), _getCallsSlot(newProposalId) + PAYLOAD_SLOT, PAYLOAD_OFFSET, PAYLOAD_SIZE, 0);

        vm.prank(timelock.getGovernance());
        uint256 proposalId = timelock.submit(executor, calls);

        assert(timelock.getProposalDetails(proposalId).status == Status.Submitted);
    }

    // Caller is not governance
    function testSubmitRevert(
        address caller,
        address executor,
        address target,
        uint96 value,
        bytes4 selector,
        bytes32 argument
    ) external _checkStateRemainsUnchanged(EmergencyProtectedTimelock.submit.selector) {
        bytes memory payload = abi.encodeWithSelector(selector, argument);

        ExternalCall[] memory calls = new ExternalCall[](1);
        calls[0].target = target;
        calls[0].value = value;
        calls[0].payload = payload;

        vm.assume(caller != timelock.getGovernance());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, caller));
        uint256 proposalId = timelock.submit(executor, calls);
        vm.stopPrank();
    }

    function testSchedule(uint256 proposalId)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.schedule.selector)
    {
        vm.assume(_getLastCancelledProposalId(timelock) < proposalId);
        _proposalStorageSetup(timelock, proposalId, Status.Submitted);

        uint256 afterSubmitDelay = Duration.unwrap(timelock.getAfterSubmitDelay());
        uint256 submittedAt = uint256(_getSubmittedAt(timelock, _getProposalsSlot(proposalId)));
        vm.assume(afterSubmitDelay + submittedAt <= block.timestamp);

        vm.prank(timelock.getGovernance());
        timelock.schedule(proposalId);

        assert(timelock.getProposalDetails(proposalId).status == Status.Scheduled);
    }

    // Caller is not Governance
    function testScheduleRevert(address caller, uint256 proposalId) external {
        vm.assume(caller != timelock.getGovernance());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotGovernance.selector, caller));
        timelock.schedule(proposalId);
        vm.stopPrank();
    }

    function testScheduleDelayHasNotPassedRevert(uint256 proposalId) external {
        vm.assume(_getLastCancelledProposalId(timelock) < proposalId);
        _proposalStorageSetup(timelock, proposalId, Status.Submitted);

        uint256 afterSubmitDelay = Duration.unwrap(timelock.getAfterSubmitDelay());
        uint256 submittedAt = uint256(_getSubmittedAt(timelock, _getProposalsSlot(proposalId)));
        vm.assume(block.timestamp < afterSubmitDelay + submittedAt);

        vm.startPrank(timelock.getGovernance());
        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterSubmitDelayNotPassed.selector, proposalId));
        timelock.schedule(proposalId);
        vm.stopPrank();
    }

    /**
     * When execute is called for a proposalId,
     * 1) the proposal is marked as executed, and
     * 2) the calls are made to the target contract.
     * The test uses a simplified example proposal that sets a flag in the
     * target contract.
     */
    function testExecute(uint256 proposalId)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.execute.selector)
    {
        FlagSetter target = new FlagSetter();
        assert(target.flag() == false);

        // The executor owner must be the timelock contract
        Executor executor = new Executor(address(timelock));

        _proposalStorageSetup(timelock, proposalId, address(executor), Status.Scheduled);
        _createDummyProposal(timelock, proposalId, target);

        vm.assume(_getLastCancelledProposalId(timelock) < proposalId);

        Duration afterScheduleDelay = timelock.getAfterScheduleDelay();
        Timestamp scheduledAt = Timestamp.wrap(_getScheduledAt(timelock, _getProposalsSlot(proposalId)));
        Duration minExecutionDelay = timelock.MIN_EXECUTION_DELAY();
        Timestamp submittedAt = Timestamp.wrap(_getSubmittedAt(timelock, _getProposalsSlot(proposalId)));

        vm.assume(afterScheduleDelay.addTo(scheduledAt) <= Timestamps.now());
        vm.assume(minExecutionDelay.addTo(submittedAt) <= Timestamps.now());
        vm.assume(!timelock.isEmergencyModeActive());

        // Ensure that no external calls are performed besides
        // - timelock.execute(proposalId)
        // - executor.execute(target, value, payload)
        // - target.call(payload)
        // where (target, value, payload) is the call submitted for proposalId
        _whitelistOnlyProposalCalls(address(executor), proposalId);

        timelock.execute(proposalId);

        assert(timelock.getProposalDetails(proposalId).status == Status.Executed);
        assert(target.flag() == true);
    }

    function _whitelistOnlyProposalCalls(address executor, uint256 proposalId) internal {
        bytes memory timelockCallData = abi.encodeWithSelector(EmergencyProtectedTimelock.execute.selector, proposalId);

        // Whitelist timelock.execute(proposalId)
        kevm.allowCalls(address(timelock), timelockCallData);

        ExternalCall[] memory calls = timelock.getProposalCalls(proposalId);

        for (uint256 i = 0; i < calls.length; ++i) {
            bytes memory executorCalldata =
                abi.encodeWithSelector(Executor.execute.selector, calls[i].target, calls[i].value, calls[i].payload);

            // Whitelist executor.execute(target, value, payload)
            kevm.allowCalls(address(executor), executorCalldata);

            // Whitelist target.call(payload)
            kevm.allowCalls(calls[i].target, calls[i].payload);
        }
    }

    function testExecuteNonScheduledRevert(uint256 proposalId) external {
        _proposalStorageSetup(timelock, proposalId);

        // ExecutableProposals.execute loads proposal into memory, which causes
        // Kontrol to branch on ExternalCalls length if it's symbolic.
        // So we create a dummy proposal just so ExternalCalls is concrete
        // (doesn't matter since execute should revert before call is made)
        FlagSetter target = new FlagSetter();
        _createDummyProposal(timelock, proposalId, target);

        Status status = _getProposalStatus(timelock, proposalId);

        vm.assume(status != Status.Scheduled);
        vm.assume(!timelock.isEmergencyModeActive());

        //vm.expectPartialRevert(ExecutableProposals.UnexpectedProposalStatus.selector);
        vm.expectRevert();
        timelock.execute(proposalId);
    }

    function testExecuteExecutedRevert(uint256 proposalId) external {
        _proposalStorageSetup(timelock, proposalId, Status.Executed);

        // ExecutableProposals.execute loads proposal into memory, which causes
        // Kontrol to branch on ExternalCalls length if it's symbolic.
        // So we create a dummy proposal just so ExternalCalls is concrete
        // (doesn't matter since execute should revert before call is made)
        FlagSetter target = new FlagSetter();
        _createDummyProposal(timelock, proposalId, target);

        vm.assume(!timelock.isEmergencyModeActive());

        vm.expectRevert(
            abi.encodeWithSelector(ExecutableProposals.UnexpectedProposalStatus.selector, proposalId, Status.Executed)
        );
        timelock.execute(proposalId);
    }

    function testExecuteDelayHasNotPassedRevert(uint256 proposalId) external {
        _proposalStorageSetup(timelock, proposalId, Status.Scheduled);

        // ExecutableProposals.execute loads proposal into memory, which causes
        // Kontrol to branch on ExternalCalls length if it's symbolic.
        // So we create a dummy proposal just so ExternalCalls is concrete
        // (doesn't matter since execute should revert before call is made)
        FlagSetter target = new FlagSetter();
        _createDummyProposal(timelock, proposalId, target);

        vm.assume(_getLastCancelledProposalId(timelock) < proposalId);

        Duration afterScheduleDelay = timelock.getAfterScheduleDelay();
        Timestamp scheduledAt = Timestamp.wrap(_getScheduledAt(timelock, _getProposalsSlot(proposalId)));

        vm.assume(Timestamps.now() < afterScheduleDelay.addTo(scheduledAt));
        vm.assume(!timelock.isEmergencyModeActive());

        vm.expectRevert(abi.encodeWithSelector(ExecutableProposals.AfterScheduleDelayNotPassed.selector, proposalId));
        timelock.execute(proposalId);
    }

    /**
     * After cancelAllNonExecutedProposals is called, any previously-submitted
     * proposal will be marked as cancelled.
     */
    function testCancelAllNonExecutedProposals(uint256 proposalId)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.cancelAllNonExecutedProposals.selector)
    {
        vm.assume(proposalId < timelock.getProposalsCount());

        _proposalStorageSetup(timelock, proposalId);

        Status statusBefore = timelock.getProposalDetails(proposalId).status;

        vm.prank(timelock.getGovernance());
        timelock.cancelAllNonExecutedProposals();

        if (statusBefore != Status.Executed) {
            Status statusAfter = timelock.getProposalDetails(proposalId).status;
            assert(statusAfter == Status.Cancelled);
        }
    }

    /**
     * cancelAllNonExecutedProposals cannot be called by any address other than
     * the governance address.
     */
    function testOnlyGovernanceCanCancelProposals(address sender) external {
        vm.assume(sender != timelock.getGovernance());

        vm.startPrank(sender);

        bytes4 errorSelector = TimelockState.CallerIsNotGovernance.selector;

        vm.expectRevert(abi.encodeWithSelector(errorSelector, sender));
        timelock.cancelAllNonExecutedProposals();

        vm.stopPrank();
    }

    /**
     * Cancelled proposals cannot be scheduled.
     */
    function testCancelledProposalsCannotBeScheduled(uint256 proposalId) external {
        vm.assume(proposalId < timelock.getProposalsCount());

        _proposalStorageSetup(timelock, proposalId);

        Status proposalStatus = timelock.getProposalDetails(proposalId).status;
        vm.assume(proposalStatus == Status.Cancelled);

        vm.startPrank(timelock.getGovernance());

        bytes4 errorSelector = ExecutableProposals.UnexpectedProposalStatus.selector;

        vm.expectRevert(abi.encodeWithSelector(errorSelector, proposalId, Status.Cancelled));

        timelock.schedule(proposalId);

        vm.stopPrank();
    }

    /**
     * Cancelled proposals cannot be executed.
     */
    function testCancelledProposalsCannotBeExecuted(uint256 proposalId) external {
        vm.assume(proposalId < timelock.getProposalsCount());
        vm.assume(!timelock.isEmergencyModeActive());

        _proposalStorageSetup(timelock, proposalId);

        // ExecutableProposals.execute loads proposal into memory, which causes
        // Kontrol to branch on ExternalCalls length if it's symbolic.
        // So we create a dummy proposal just so ExternalCalls is concrete
        // (doesn't matter since execute should revert before call is made)
        FlagSetter target = new FlagSetter();
        _createDummyProposal(timelock, proposalId, target);

        Status proposalStatus = timelock.getProposalDetails(proposalId).status;
        vm.assume(proposalStatus == Status.Cancelled);

        bytes4 errorSelector = ExecutableProposals.UnexpectedProposalStatus.selector;

        vm.expectRevert(abi.encodeWithSelector(errorSelector, proposalId, Status.Cancelled));

        timelock.execute(proposalId);
    }

    /**
     * Cancelled proposals cannot be emergency-executed.
     */
    function testCancelledProposalsCannotBeEmergencyExecuted(uint256 proposalId) external {
        vm.assume(proposalId < timelock.getProposalsCount());
        vm.assume(timelock.isEmergencyModeActive());

        _proposalStorageSetup(timelock, proposalId);

        // ExecutableProposals.execute loads proposal into memory, which causes
        // Kontrol to branch on ExternalCalls length if it's symbolic.
        // So we create a dummy proposal just so ExternalCalls is concrete
        // (doesn't matter since execute should revert before call is made)
        FlagSetter target = new FlagSetter();
        _createDummyProposal(timelock, proposalId, target);

        Status proposalStatus = timelock.getProposalDetails(proposalId).status;
        vm.assume(proposalStatus == Status.Cancelled);

        vm.startPrank(timelock.getEmergencyExecutionCommittee());

        bytes4 errorSelector = ExecutableProposals.UnexpectedProposalStatus.selector;

        vm.expectRevert(abi.encodeWithSelector(errorSelector, proposalId, Status.Cancelled));

        timelock.emergencyExecute(proposalId);

        vm.stopPrank();
    }

    function testSetGovernance(address newGovernance)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.setGovernance.selector)
    {
        vm.assume(newGovernance != address(0));
        vm.assume(newGovernance != timelock.getGovernance());

        vm.prank(timelock.getAdminExecutor());
        timelock.setGovernance(newGovernance);

        assert(timelock.getGovernance() == newGovernance);
    }

    function testSetAfterSubmitDelay(Duration newAfterSubmitDelay)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.setAfterSubmitDelay.selector)
    {
        vm.assume(newAfterSubmitDelay != timelock.getAfterSubmitDelay());
        vm.assume(newAfterSubmitDelay <= timelock.MAX_AFTER_SUBMIT_DELAY());
        // Overflow assumption
        vm.assume(
            Duration.unwrap(newAfterSubmitDelay) < type(uint32).max - Duration.unwrap(timelock.getAfterScheduleDelay())
        );
        vm.assume(timelock.MIN_EXECUTION_DELAY() <= newAfterSubmitDelay + timelock.getAfterScheduleDelay());

        vm.prank(timelock.getAdminExecutor());
        timelock.setAfterSubmitDelay(newAfterSubmitDelay);

        assert(timelock.getAfterSubmitDelay() == newAfterSubmitDelay);
    }

    function testSetAfterScheduleDelay(Duration newAfterScheduleDelay)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.setAfterScheduleDelay.selector)
    {
        vm.assume(newAfterScheduleDelay != timelock.getAfterScheduleDelay());
        vm.assume(newAfterScheduleDelay <= timelock.MAX_AFTER_SCHEDULE_DELAY());
        // Overflow assumption
        vm.assume(
            Duration.unwrap(newAfterScheduleDelay) < type(uint32).max - Duration.unwrap(timelock.getAfterSubmitDelay())
        );
        vm.assume(timelock.MIN_EXECUTION_DELAY() <= newAfterScheduleDelay + timelock.getAfterSubmitDelay());

        vm.prank(timelock.getAdminExecutor());
        timelock.setAfterScheduleDelay(newAfterScheduleDelay);

        assert(timelock.getAfterScheduleDelay() == newAfterScheduleDelay);
    }

    function testTransferExecutorOwnership(address owner)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.transferExecutorOwnership.selector)
    {
        // The executor owner must be the timelock contract
        Executor executor = new Executor(address(timelock));

        vm.assume(owner != address(0));

        vm.prank(timelock.getAdminExecutor());
        timelock.transferExecutorOwnership(address(executor), owner);

        assert(executor.owner() == owner);
    }

    function testSetEmergencyProtectionActivationCommittee(address newEmergencyActivationCommittee)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.setEmergencyProtectionActivationCommittee.selector)
    {
        vm.assume(newEmergencyActivationCommittee != timelock.getEmergencyActivationCommittee());

        vm.prank(timelock.getAdminExecutor());
        timelock.setEmergencyProtectionActivationCommittee(newEmergencyActivationCommittee);

        assert(timelock.getEmergencyActivationCommittee() == newEmergencyActivationCommittee);
    }

    function testSetEmergencyProtectionExecutionCommittee(address newEmergencyExecutionCommittee)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.setEmergencyProtectionExecutionCommittee.selector)
    {
        vm.assume(newEmergencyExecutionCommittee != timelock.getEmergencyExecutionCommittee());

        vm.prank(timelock.getAdminExecutor());
        timelock.setEmergencyProtectionExecutionCommittee(newEmergencyExecutionCommittee);

        assert(timelock.getEmergencyExecutionCommittee() == newEmergencyExecutionCommittee);
    }

    function testSetEmergencyProtectionEndDate(Timestamp newEmergencyProtectionEndDate)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.setEmergencyProtectionEndDate.selector)
    {
        vm.assume(newEmergencyProtectionEndDate <= timelock.MAX_EMERGENCY_PROTECTION_DURATION().addTo(Timestamps.now()));
        vm.assume(
            newEmergencyProtectionEndDate != timelock.getEmergencyProtectionDetails().emergencyProtectionEndsAfter
        );

        vm.prank(timelock.getAdminExecutor());
        timelock.setEmergencyProtectionEndDate(newEmergencyProtectionEndDate);

        assert(timelock.getEmergencyProtectionDetails().emergencyProtectionEndsAfter == newEmergencyProtectionEndDate);
    }

    function testSetEmergencyModeDuration(Duration newEmergencyModeDuration)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.setEmergencyModeDuration.selector)
    {
        vm.assume(newEmergencyModeDuration <= timelock.MAX_EMERGENCY_MODE_DURATION());
        vm.assume(newEmergencyModeDuration != timelock.getEmergencyProtectionDetails().emergencyModeDuration);

        vm.prank(timelock.getAdminExecutor());
        timelock.setEmergencyModeDuration(newEmergencyModeDuration);

        assert(timelock.getEmergencyProtectionDetails().emergencyModeDuration == newEmergencyModeDuration);
    }

    function testSetEmergencyGovernance(address newEmergencyGovernance)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.setEmergencyGovernance.selector)
    {
        vm.assume(newEmergencyGovernance != timelock.getEmergencyGovernance());

        vm.prank(timelock.getAdminExecutor());
        timelock.setEmergencyGovernance(newEmergencyGovernance);

        assert(timelock.getEmergencyGovernance() == newEmergencyGovernance);
    }

    function testActivateEmergencyMode()
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.activateEmergencyMode.selector)
    {
        vm.assume(Timestamps.now() <= timelock.getEmergencyProtectionDetails().emergencyProtectionEndsAfter);
        vm.assume(!timelock.isEmergencyModeActive());

        vm.prank(timelock.getEmergencyActivationCommittee());
        timelock.activateEmergencyMode();

        assert(timelock.isEmergencyModeActive());
    }

    // Caller is not EmergencyActivationComittee
    function testActivateEmergencyModeRevert(address caller) external {
        vm.assume(caller != timelock.getEmergencyActivationCommittee());

        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyActivationCommittee.selector, caller)
        );
        timelock.activateEmergencyMode();
        vm.stopPrank();
    }

    function testActivateEmergencyModeInEmergencyRevert() external {
        vm.assume(timelock.isEmergencyModeActive());

        vm.startPrank(timelock.getEmergencyActivationCommittee());
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, true));
        timelock.activateEmergencyMode();
        vm.stopPrank();
    }

    function testActivateEmergencyAfterEndDateRevert() external {
        Timestamp protectionEndDate = timelock.getEmergencyProtectionDetails().emergencyProtectionEndsAfter;
        vm.assume(Timestamps.now() > protectionEndDate);
        vm.assume(!timelock.isEmergencyModeActive());

        vm.startPrank(timelock.getEmergencyActivationCommittee());
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.EmergencyProtectionExpired.selector, protectionEndDate)
        );
        timelock.activateEmergencyMode();
        vm.stopPrank();
    }

    /**
     * When emergencyExecute is called for a proposalId,
     * 1) the proposal is marked as executed, and
     * 2) the calls are made to the target contract.
     * The test uses a simplified example proposal that sets a flag in the
     * target contract.
     */
    function testEmergencyExecute(uint256 proposalId)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.emergencyExecute.selector)
    {
        FlagSetter target = new FlagSetter();
        assert(target.flag() == false);

        // The executor owner must be the timelock contract
        Executor executor = new Executor(address(timelock));

        _proposalStorageSetup(timelock, proposalId, address(executor), Status.Scheduled);
        _createDummyProposal(timelock, proposalId, target);

        vm.assume(_getLastCancelledProposalId(timelock) < proposalId);
        vm.assume(timelock.isEmergencyModeActive());
        // Unlike in testExecute, we don't need to assume the delay has passed

        vm.prank(timelock.getEmergencyExecutionCommittee());
        timelock.emergencyExecute(proposalId);

        assert(timelock.getProposalDetails(proposalId).status == Status.Executed);
        assert(target.flag() == true);
    }

    function testEmergencyExecuteNonScheduledRevert(uint256 proposalId) external {
        _proposalStorageSetup(timelock, proposalId);

        // ExecutableProposals.execute loads proposal into memory, which causes
        // Kontrol to branch on ExternalCalls length if it's symbolic.
        // So we create a dummy proposal just so ExternalCalls is concrete
        // (doesn't matter since execute should revert before call is made)
        FlagSetter target = new FlagSetter();
        _createDummyProposal(timelock, proposalId, target);

        Status status = _getProposalStatus(timelock, proposalId);

        vm.assume(status != Status.Scheduled);
        vm.assume(timelock.isEmergencyModeActive());
        // Unlike in testExecute, we don't need to assume the delay has passed

        vm.startPrank(timelock.getEmergencyExecutionCommittee());
        //vm.expectPartialRevert(ExecutableProposals.UnexpectedProposalStatus.selector);
        vm.expectRevert();
        timelock.emergencyExecute(proposalId);
        vm.stopPrank();
    }

    function testEmergencyExecuteExecutedRevert(uint256 proposalId) external {
        _proposalStorageSetup(timelock, proposalId, Status.Executed);

        // ExecutableProposals.execute loads proposal into memory, which causes
        // Kontrol to branch on ExternalCalls length if it's symbolic.
        // So we create a dummy proposal just so ExternalCalls is concrete
        // (doesn't matter since execute should revert before call is made)
        FlagSetter target = new FlagSetter();
        _createDummyProposal(timelock, proposalId, target);

        vm.assume(timelock.isEmergencyModeActive());
        // Unlike in testExecute, we don't need to assume the delay has passed

        vm.startPrank(timelock.getEmergencyExecutionCommittee());
        vm.expectRevert(
            abi.encodeWithSelector(ExecutableProposals.UnexpectedProposalStatus.selector, proposalId, Status.Executed)
        );
        timelock.emergencyExecute(proposalId);
        vm.stopPrank();
    }

    function testEmergencyExecuteNormalModeRevert(uint256 proposalId) external {
        vm.assume(!timelock.isEmergencyModeActive());

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
        timelock.emergencyExecute(proposalId);
    }

    // Caller is not Emergency execution comittee
    function testEmergencyExecuteRevert(address caller, uint256 proposalId) external {
        vm.assume(timelock.isEmergencyModeActive());
        vm.assume(caller != timelock.getEmergencyExecutionCommittee());

        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyExecutionCommittee.selector, caller)
        );
        timelock.emergencyExecute(proposalId);
        vm.stopPrank();
    }

    /**
     * After deactivateEmergencyMode is called, emergency mode is deactivated
     * and any previously-submitted proposal will be marked as cancelled.
     */
    function testDeactivateEmergencyMode(uint256 proposalId)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.deactivateEmergencyMode.selector)
    {
        vm.assume(proposalId < timelock.getProposalsCount());
        vm.assume(timelock.isEmergencyModeActive());

        _proposalStorageSetup(timelock, proposalId);

        Status statusBefore = _getProposalStatus(timelock, proposalId);

        Timestamp emergencyModeEndsAfter = timelock.getEmergencyProtectionDetails().emergencyModeEndsAfter;

        if (Timestamps.now() <= emergencyModeEndsAfter) {
            vm.prank(timelock.getAdminExecutor());
        }

        timelock.deactivateEmergencyMode();

        EmergencyProtection.Context memory postState = _saveEmergencyProtection(timelock);

        assert(!timelock.isEmergencyModeActive());
        assert(postState.emergencyActivationCommittee == address(0));
        assert(postState.emergencyExecutionCommittee == address(0));
        assert(postState.emergencyModeDuration == Durations.ZERO);
        assert(postState.emergencyModeEndsAfter == Timestamps.ZERO);
        assert(postState.emergencyProtectionEndsAfter == Timestamps.ZERO);

        if (statusBefore != Status.Executed) {
            Status statusAfter = timelock.getProposalDetails(proposalId).status;
            assert(statusAfter == Status.Cancelled);
        }
    }

    function testDeactivateEmergencyModeNormalModeRevert(uint256 proposalId) external {
        vm.assume(!timelock.isEmergencyModeActive());

        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
        timelock.deactivateEmergencyMode();
    }

    function testDeactivateEmergencyModeRevert(address caller, uint256 proposalId) external {
        vm.assume(timelock.isEmergencyModeActive());

        Timestamp emergencyModeEndsAfter = timelock.getEmergencyProtectionDetails().emergencyModeEndsAfter;
        vm.assume(Timestamps.now() <= emergencyModeEndsAfter);

        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.deactivateEmergencyMode();
        vm.stopPrank();
    }

    /**
     * After emergencyReset is called, emergency mode is deactivated
     * and any previously-submitted proposal will be marked as cancelled.
     */
    function testEmergencyReset(uint256 proposalId)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.emergencyReset.selector)
    {
        vm.assume(proposalId < timelock.getProposalsCount());
        vm.assume(timelock.isEmergencyModeActive());
        address emergencyGovernance = timelock.getEmergencyGovernance();
        vm.assume(emergencyGovernance != address(0));
        vm.assume(emergencyGovernance != timelock.getGovernance());

        _proposalStorageSetup(timelock, proposalId);

        Status statusBefore = _getProposalStatus(timelock, proposalId);

        vm.prank(timelock.getEmergencyExecutionCommittee());
        timelock.emergencyReset();

        assert(!timelock.isEmergencyModeActive());

        EmergencyProtection.Context memory postState = _saveEmergencyProtection(timelock);

        assert(!timelock.isEmergencyModeActive());
        assert(postState.emergencyActivationCommittee == address(0));
        assert(postState.emergencyExecutionCommittee == address(0));
        assert(postState.emergencyModeDuration == Durations.ZERO);
        assert(postState.emergencyModeEndsAfter == Timestamps.ZERO);
        assert(postState.emergencyProtectionEndsAfter == Timestamps.ZERO);
        assert(postState.emergencyGovernance == emergencyGovernance);
        assert(timelock.getGovernance() == emergencyGovernance);

        if (statusBefore != Status.Executed) {
            Status statusAfter = timelock.getProposalDetails(proposalId).status;
            assert(statusAfter == Status.Cancelled);
        }
    }

    function testEmergencyResetNormalModeRevert(uint256 proposalId) external {
        vm.assume(!timelock.isEmergencyModeActive());

        vm.startPrank(timelock.getEmergencyExecutionCommittee());
        vm.expectRevert(abi.encodeWithSelector(EmergencyProtection.UnexpectedEmergencyModeState.selector, false));
        timelock.emergencyReset();
        vm.stopPrank();
    }

    // Caller is not Emergency Execution Comittee
    function testEmergencyResetRevert(address caller, uint256 proposalId) external {
        vm.assume(caller != timelock.getEmergencyExecutionCommittee());

        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyProtection.CallerIsNotEmergencyExecutionCommittee.selector, caller)
        );
        timelock.emergencyReset();
        vm.stopPrank();
    }

    function testSetAdminExecutor(address newAdminExecutor)
        external
        _checkStateRemainsUnchanged(EmergencyProtectedTimelock.setAdminExecutor.selector)
    {
        vm.assume(newAdminExecutor != address(0));
        vm.assume(newAdminExecutor != timelock.getAdminExecutor());

        vm.prank(timelock.getAdminExecutor());
        timelock.setAdminExecutor(newAdminExecutor);

        assert(timelock.getAdminExecutor() == newAdminExecutor);
    }

    /**
     * Initializes a simple example proposal at proposalId that sets a flag in
     * the target contract, initializing the storage appropriately.
     */
    function _createDummyProposal(
        EmergencyProtectedTimelock _timelock,
        uint256 _proposalId,
        FlagSetter _target
    ) internal {
        // Calculate storage location of ExecutableCalls array
        uint256 proposalSlot = uint256(keccak256(abi.encodePacked(_proposalId, PROPOSALS_SLOT)));
        uint256 callsArraySlot = proposalSlot + CALLS_SLOT;

        // Store array length of 1
        _storeData(address(_timelock), callsArraySlot, CALLS_OFFSET, CALLS_SIZE, 1);

        // Calculate storage location of array element at index 0
        uint256 callSlot = uint256(keccak256(abi.encodePacked(callsArraySlot)));

        // Store call target address
        _storeData(
            address(_timelock), callSlot + TARGET_SLOT, TARGET_OFFSET, TARGET_SIZE, uint256(uint160(address(_target)))
        );

        // Store call value of 0
        _storeData(address(_timelock), callSlot + VALUE_SLOT, VALUE_OFFSET, VALUE_SIZE, 0);

        // Create payload and double-check that it has length 36
        bytes memory payload = abi.encodeWithSelector(FlagSetter.setFlag.selector, true);

        assert(payload.length == 36);

        // Pad payload with 28 zeros so it fits into a multiple of 32 bytes
        bytes memory paddedPayload = abi.encodePacked(payload, bytes28(0));

        assert(paddedPayload.length == 64);

        // Split payload into two 32-byte segments
        bytes32 payloadUpperHalf;
        assembly {
            payloadUpperHalf := mload(add(paddedPayload, 32))
        }
        bytes32 payloadLowerHalf;
        assembly {
            payloadLowerHalf := mload(add(paddedPayload, 64))
        }

        uint256 payloadLengthSlot = callSlot + PAYLOAD_SLOT;

        // Store payload length according to specification for bytes in storage:
        // https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html#bytes-and-string
        _storeData(address(_timelock), payloadLengthSlot, PAYLOAD_OFFSET, PAYLOAD_SIZE, payload.length * 2 + 1);

        // Calculate storage location for bytes data
        uint256 payloadContentSlot = uint256(keccak256(abi.encodePacked(payloadLengthSlot)));

        // Store first half of payload
        _storeData(address(_timelock), payloadContentSlot, 0, 32, uint256(payloadUpperHalf));

        // Store second half of payload
        _storeData(address(_timelock), payloadContentSlot + 1, 0, 32, uint256(payloadLowerHalf));
    }

    function testSetGovernanceRevert(address caller, address newGovernance) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.setGovernance(newGovernance);
        vm.stopPrank();
    }

    function testSetAfterSubmitDelayRevert(address caller, Duration newAfterSubmitDelay) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.setAfterSubmitDelay(newAfterSubmitDelay);
        vm.stopPrank();
    }

    function testSetAfterScheduleDelayRevert(address caller, Duration newAfterScheduleDelay) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.setAfterScheduleDelay(newAfterScheduleDelay);
        vm.stopPrank();
    }

    function testTransferExecutorOwnershipRevert(address caller, address executor, address owner) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.transferExecutorOwnership(address(executor), owner);
        vm.stopPrank();
    }

    function testSetAdminExecutorRevert(address caller, address newAdminExecutor) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.setAdminExecutor(newAdminExecutor);
        vm.stopPrank();
    }

    function testSetEmergencyProtectionActivationCommitteeRevert(
        address caller,
        address newEmergencyActivationCommittee
    ) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.setEmergencyProtectionActivationCommittee(newEmergencyActivationCommittee);
        vm.stopPrank();
    }

    function testSetEmergencyProtectionExecutionCommitteeRevert(
        address caller,
        address newEmergencyExecutionCommittee
    ) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.setEmergencyProtectionExecutionCommittee(newEmergencyExecutionCommittee);
        vm.stopPrank();
    }

    function testSetEmergencyProtectionEndDateRevert(
        address caller,
        Timestamp newEmergencyProtectionEndDate
    ) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.setEmergencyProtectionEndDate(newEmergencyProtectionEndDate);
        vm.stopPrank();
    }

    function testSetEmergencyModeDurationRevert(address caller, Duration newEmergencyModeDuration) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.setEmergencyModeDuration(newEmergencyModeDuration);
        vm.stopPrank();
    }

    function testSetEmergencyGovernanceRevert(address caller, address newEmergencyGovernance) external {
        vm.assume(caller != timelock.getAdminExecutor());

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(TimelockState.CallerIsNotAdminExecutor.selector, caller));
        timelock.setEmergencyGovernance(newEmergencyGovernance);
        vm.stopPrank();
    }
}
