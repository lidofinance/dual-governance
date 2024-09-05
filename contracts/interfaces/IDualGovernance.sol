// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGovernance} from "./IGovernance.sol";
import {ITimelock} from "./ITimelock.sol";

interface IDualGovernance is IGovernance {
    function activateNextState() external;

    function resealSealable(address sealables) external;

    function tiebreakerScheduleProposal(uint256 proposalId) external;
    function tiebreakerResumeSealable(address sealable) external;
    function TIMELOCK() external view returns (ITimelock);
}
