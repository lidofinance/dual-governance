// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "contracts/types/Duration.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";

interface ITimeConstraints {
    function checkTimeWithinDayTime(Duration startDayTime, Duration endDayTime) external view;
    function checkTimeAfterTimestamp(Timestamp timestamp) external view;
    function checkTimeBeforeTimestamp(Timestamp timestamp) external view;
    function checkTimeWithinDayTimeAndEmit(Duration startDayTime, Duration endDayTime) external;
    function checkTimeAfterTimestampAndEmit(Timestamp timestamp) external;
    function checkTimeBeforeTimestampAndEmit(Timestamp timestamp) external;
    function getCurrentDayTime() external view returns (Duration);
}
