// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutorCall} from "./IExecutor.sol";

interface ITimelockController {
    function handleProposalCreation(address sender) external returns (address executor);
    function handleProposalAdoption(address sender) external;
    function handleProposalsRevocation(address sender) external;

    function isProposalsAdoptionAllowed() external view returns (bool);
}

interface ITimelock {
    function submit(ExecutorCall[] calldata calls) external returns (uint256 newProposalId);
    function cancelAll() external;
}
