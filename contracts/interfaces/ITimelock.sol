// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutorCall} from "./IExecutor.sol";

interface ITimelockController {
    function handleProposalCreation() external;
    function handleProposalAdoption() external;
    function handleProposalsRevocation() external;

    function isTiebreak() external view returns (bool);
    function isProposalsAdoptionAllowed() external view returns (bool);
}

interface ITimelock {
    function submit(address executor, ExecutorCall[] calldata calls) external returns (uint256 newProposalId);
    function cancelAll() external;
}
