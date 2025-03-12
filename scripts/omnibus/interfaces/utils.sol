// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../../../contracts/types/Duration.sol";
import {Timestamp} from "../../../contracts/types/Timestamp.sol";

interface IRolesValidator {
    function validate(address dgAdminExecutor, address dgResealManager) external;
    function validateAfterDG() external;
}

interface IDGLaunchVerifier {
    function verify() external;
}

interface IFoo {
    function bar() external;
}

interface ITimeConstraints {
    function checkExecuteWithinDayTime(Duration startDayTime, Duration endDayTime) external view;
    function checkExecuteAfterTimestamp(Timestamp timestamp) external view;
    function getCurrentDayTime() external view returns (Duration);
}

interface ITokenManager {
    function forward(bytes calldata _evmScript) external;
}
