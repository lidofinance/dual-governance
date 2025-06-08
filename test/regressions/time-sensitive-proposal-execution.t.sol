// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Durations, Duration} from "contracts/types/Duration.sol";
import {Timestamps, Timestamp} from "contracts/types/Timestamp.sol";
import {TimeConstraints} from "scripts/launch/TimeConstraints.sol";

import {DGRegressionTestSetup} from "../utils/integration-tests.sol";

import {ExternalCall, ExternalCallsBuilder} from "scripts/utils/ExternalCallsBuilder.sol";

interface ITimeSensitiveContract {
    function timeSensitiveMethod() external;
}

contract TimeSensitiveProposalsRegressionTest is DGRegressionTestSetup {
    using ExternalCallsBuilder for ExternalCallsBuilder.Context;

    TimeConstraints internal _timelockConstraints;

    Duration private immutable _EXECUTION_DELAY = Durations.from(30 days); // Proposal may be executed not earlier than the 30 days from launch
    Duration private immutable _EXECUTION_START_DAY_TIME = Durations.from(4 hours); // And at time frame starting from the 4:00 UTC
    Duration private immutable _EXECUTION_END_DAY_TIME = Durations.from(12 hours); // till the 12:00 UTC

    function setUp() external {
        _loadOrDeployDGSetup();
        _timelockConstraints = new TimeConstraints();
    }

    function testFork_TimeFrameProposalExecution_HappyPath() external {
        Timestamp executableAfter = _EXECUTION_DELAY.addTo(Timestamps.now());

        ExternalCallsBuilder.Context memory scheduleProposalCallsBuilder = ExternalCallsBuilder.create({callsCount: 3});

        // Prepare the call to be launched not earlier than the minExecutionDelay seconds from the creation of the
        // Aragon Voting to submit proposal and only in the day time range [executionStartDayTime, executionEndDayTime] in UTC
        scheduleProposalCallsBuilder.addCall(
            address(_timelockConstraints),
            abi.encodeCall(_timelockConstraints.checkTimeAfterTimestamp, (executableAfter))
        );
        scheduleProposalCallsBuilder.addCall(
            address(_timelockConstraints),
            abi.encodeCall(
                _timelockConstraints.checkTimeWithinDayTime, (_EXECUTION_START_DAY_TIME, _EXECUTION_END_DAY_TIME)
            )
        );
        scheduleProposalCallsBuilder.addCall(
            address(_targetMock), abi.encodeCall(ITimeSensitiveContract.timeSensitiveMethod, ())
        );

        ExternalCall[] memory scheduledProposalCalls = scheduleProposalCallsBuilder.getResult();

        uint256 proposalId;
        _step("1. Submit time sensitive proposal");
        {
            proposalId =
                _submitProposalByAdminProposer(scheduledProposalCalls, "DAO performs some time sensitive action");

            _assertProposalSubmitted(proposalId);
            _assertSubmittedProposalData(proposalId, scheduledProposalCalls);
        }

        _step("2. Wait while the DG timelock has passed & schedule proposal");
        {
            _wait(_timelock.getAfterSubmitDelay().plusSeconds(1));
            _assertCanSchedule(proposalId, true);
            _scheduleProposal(proposalId);
            _assertProposalScheduled(proposalId);
        }

        _step("3. Proposal can't be executed earlier than specified date");
        {
            _wait(_getAfterScheduleDelay());
            _assertCanExecute(proposalId, true);
            assertTrue(Timestamps.now() < executableAfter);

            vm.expectRevert(abi.encodeWithSelector(TimeConstraints.TimestampNotPassed.selector, (executableAfter)));
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
            _wait(_timelockConstraints.DAY_DURATION() - _timelockConstraints.getCurrentDayTime());
            assertEq(_timelockConstraints.getCurrentDayTime(), Durations.ZERO);

            midnightSnapshotId = vm.snapshot();
        }

        _step("6.a. Execution reverts when current time is less than allowed range");
        {
            assertTrue(_timelockConstraints.getCurrentDayTime() < _EXECUTION_START_DAY_TIME);

            vm.expectRevert(
                abi.encodeWithSelector(
                    TimeConstraints.DayTimeOutOfRange.selector,
                    _timelockConstraints.getCurrentDayTime(),
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
            assertTrue(_timelockConstraints.getCurrentDayTime() > _EXECUTION_END_DAY_TIME);

            vm.expectRevert(
                abi.encodeWithSelector(
                    TimeConstraints.DayTimeOutOfRange.selector,
                    _timelockConstraints.getCurrentDayTime(),
                    _EXECUTION_START_DAY_TIME,
                    _EXECUTION_END_DAY_TIME
                )
            );
            _executeProposal(proposalId);
        }
        vm.revertTo(midnightSnapshotId);

        ExternalCall[] memory expectedProposalCalls = new ExternalCall[](1);
        expectedProposalCalls[0] = scheduledProposalCalls[2];

        _step("6.c. Proposal executes successfully at the first second of the allowed range");
        {
            _wait(_EXECUTION_START_DAY_TIME);
            assertTrue(
                _timelockConstraints.getCurrentDayTime() >= _EXECUTION_START_DAY_TIME
                    && _timelockConstraints.getCurrentDayTime() <= _EXECUTION_END_DAY_TIME
            );

            _executeProposal(proposalId);
            _assertTargetMockCalls(_timelock.getAdminExecutor(), expectedProposalCalls);
        }
        vm.revertTo(midnightSnapshotId);

        _step("6.d. Proposal executes successfully at the last second of the allowed range");
        {
            _wait(_EXECUTION_END_DAY_TIME);
            assertTrue(
                _timelockConstraints.getCurrentDayTime() >= _EXECUTION_START_DAY_TIME
                    && _timelockConstraints.getCurrentDayTime() <= _EXECUTION_END_DAY_TIME
            );

            _executeProposal(proposalId);
            _assertTargetMockCalls(_timelock.getAdminExecutor(), expectedProposalCalls);
        }
        vm.revertTo(midnightSnapshotId);

        _step("6.e. Proposal executes successfully at the middle of the allowed range");
        {
            _wait((_EXECUTION_END_DAY_TIME - _EXECUTION_START_DAY_TIME).dividedBy(2));
            assertTrue(
                _timelockConstraints.getCurrentDayTime() >= _EXECUTION_START_DAY_TIME
                    && _timelockConstraints.getCurrentDayTime() <= _EXECUTION_END_DAY_TIME
            );

            _executeProposal(proposalId);
            _assertTargetMockCalls(_timelock.getAdminExecutor(), expectedProposalCalls);
        }
        vm.revertTo(midnightSnapshotId);
    }
}
