// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";

import {TimeConstraints} from "../utils/time-constraints.sol";
import {ExternalCall, ExternalCallHelpers} from "../utils/executor-calls.sol";
import {ScenarioTestBlueprint, LidoUtils, console} from "../utils/scenario-test-blueprint.sol";

interface ITimeSensitiveContract {
    function timeSensitiveMethod() external;
}

contract ScheduledProposalExecution is ScenarioTestBlueprint {
    TimeConstraints private immutable _TIME_CONSTRAINTS = new TimeConstraints();

    Duration private immutable _EXECUTION_DELAY = Durations.from(30 days); // Proposal may be executed not earlier than the 30 days from launch
    Duration private immutable _EXECUTION_START_DAY_TIME = Durations.from(4 hours); // And at time frame starting from the 4:00 UTC
    Duration private immutable _EXECUTION_END_DAY_TIME = Durations.from(12 hours); // till the 12:00 UTC

    function setUp() external {
        _deployDualGovernanceSetup({isEmergencyProtectionEnabled: false});
    }

    function testFork_TimeFrameProposalExecution() external {
        Timestamp executableAfter = _EXECUTION_DELAY.addTo(Timestamps.now());
        // Prepare the call to be launched not earlier than the minExecutionDelay seconds from the creation of the
        // Aragon Voting to submit proposal and only in the day time range [executionStartDayTime, executionEndDayTime] in UTC
        ExternalCall[] memory scheduledProposalCalls = ExternalCallHelpers.create(
            [
                ExternalCall({
                    target: address(_TIME_CONSTRAINTS),
                    value: 0 wei,
                    payload: abi.encodeCall(_TIME_CONSTRAINTS.checkExecuteAfterTimestamp, (executableAfter))
                }),
                ExternalCall({
                    target: address(_TIME_CONSTRAINTS),
                    value: 0 wei,
                    payload: abi.encodeCall(
                        _TIME_CONSTRAINTS.checkExecuteWithinDayTime, (_EXECUTION_START_DAY_TIME, _EXECUTION_END_DAY_TIME)
                    )
                }),
                ExternalCall({
                    target: address(_targetMock),
                    value: 0 wei,
                    payload: abi.encodeCall(ITimeSensitiveContract.timeSensitiveMethod, ())
                })
            ]
        );

        uint256 proposalId;
        _step("1. Submit time sensitive proposal");
        {
            proposalId =
                _submitProposal(_dualGovernance, "DAO performs some time sensitive action", scheduledProposalCalls);

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, scheduledProposalCalls);
        }

        _step("2. Wait while the DG timelock has passed & schedule proposal");
        {
            _wait(_timelock.getAfterSubmitDelay().plusSeconds(1));
            _assertCanScheduleViaDualGovernance(proposalId, true);
            _scheduleProposalViaDualGovernance(proposalId);
            _assertProposalScheduled(proposalId);
        }

        _step("3. Proposal can't be executed earlier than specified date");
        {
            _waitAfterScheduleDelayPassed();
            _assertCanExecute(proposalId, true);
            assertTrue(Timestamps.now() < executableAfter);

            vm.expectRevert(abi.encodeWithSelector(TimeConstraints.TimestampNotReached.selector, (executableAfter)));
            _executeProposal(proposalId);
        }

        _step("4. Wait until the proposal become executable");
        {
            _wait(_EXECUTION_DELAY);
            assertTrue(Timestamps.now() >= executableAfter);
        }

        uint256 midnightSnapshotId;
        _step("5. Adjust current day time of the node to 00:00 UTC");
        {
            // adjust current time to 00:00 UTC
            _wait(_TIME_CONSTRAINTS.DAY_DURATION() - _TIME_CONSTRAINTS.getCurrentDayTime());
            assertEq(_TIME_CONSTRAINTS.getCurrentDayTime(), Durations.ZERO);

            midnightSnapshotId = vm.snapshot();
        }

        _step("6.a. Execution reverts when current time is less than allowed range");
        {
            assertTrue(_TIME_CONSTRAINTS.getCurrentDayTime() < _EXECUTION_START_DAY_TIME);

            vm.expectRevert(
                abi.encodeWithSelector(
                    TimeConstraints.DayTimeOutOfRange.selector,
                    _TIME_CONSTRAINTS.getCurrentDayTime(),
                    _EXECUTION_START_DAY_TIME,
                    _EXECUTION_END_DAY_TIME
                )
            );
            _executeProposal(proposalId);
        }
        vm.revertTo(midnightSnapshotId);

        _step("6.b. Execution reverts when current time is greater than allowed range");
        {
            _wait(_EXECUTION_END_DAY_TIME.plusSeconds(1));
            assertTrue(_TIME_CONSTRAINTS.getCurrentDayTime() > _EXECUTION_END_DAY_TIME);

            vm.expectRevert(
                abi.encodeWithSelector(
                    TimeConstraints.DayTimeOutOfRange.selector,
                    _TIME_CONSTRAINTS.getCurrentDayTime(),
                    _EXECUTION_START_DAY_TIME,
                    _EXECUTION_END_DAY_TIME
                )
            );
            _executeProposal(proposalId);
        }
        vm.revertTo(midnightSnapshotId);

        ExternalCall[] memory expectedProposalCalls = ExternalCallHelpers.create([scheduledProposalCalls[2]]);

        _step("6.c. Proposal executes successfully at the first second of the allowed range");
        {
            _wait(_EXECUTION_START_DAY_TIME);
            assertTrue(
                _TIME_CONSTRAINTS.getCurrentDayTime() >= _EXECUTION_START_DAY_TIME
                    && _TIME_CONSTRAINTS.getCurrentDayTime() <= _EXECUTION_END_DAY_TIME
            );

            _executeProposal(proposalId);
            _assertTargetMockCalls(_timelock.getAdminExecutor(), expectedProposalCalls);
        }
        vm.revertTo(midnightSnapshotId);

        _step("6.d. Proposal executes successfully at the last second of the allowed range");
        {
            _wait(_EXECUTION_END_DAY_TIME);
            assertTrue(
                _TIME_CONSTRAINTS.getCurrentDayTime() >= _EXECUTION_START_DAY_TIME
                    && _TIME_CONSTRAINTS.getCurrentDayTime() <= _EXECUTION_END_DAY_TIME
            );

            _executeProposal(proposalId);
            _assertTargetMockCalls(_timelock.getAdminExecutor(), expectedProposalCalls);
        }
        vm.revertTo(midnightSnapshotId);

        _step("6.e. Proposal executes successfully at the middle of the allowed range");
        {
            _wait((_EXECUTION_END_DAY_TIME - _EXECUTION_START_DAY_TIME).dividedBy(2));
            assertTrue(
                _TIME_CONSTRAINTS.getCurrentDayTime() >= _EXECUTION_START_DAY_TIME
                    && _TIME_CONSTRAINTS.getCurrentDayTime() <= _EXECUTION_END_DAY_TIME
            );

            _executeProposal(proposalId);
            _assertTargetMockCalls(_timelock.getAdminExecutor(), expectedProposalCalls);
        }
        vm.revertTo(midnightSnapshotId);
    }
}
