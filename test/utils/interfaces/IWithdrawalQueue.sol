// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IWithdrawalQueue as IWithdrawalQueueBase} from "contracts/interfaces/IWithdrawalQueue.sol";

interface IWithdrawalQueue is IWithdrawalQueueBase {
    function getLastRequestId() external view returns (uint256);
    function setApprovalForAll(address _operator, bool _approved) external;
    function grantRole(bytes32 role, address account) external;
    function pauseFor(uint256 duration) external;
    function isPaused() external returns (bool);
    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;
}
