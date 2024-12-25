// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";

interface IWithdrawalQueue is IERC721 {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external;

    function transferFrom(address from, address to, uint256 requestId) external;

    function getLastRequestId() external view returns (uint256);
    function getLastFinalizedRequestId() external view returns (uint256);

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);

    /// @notice Returns amount of ether available for claim for each provided request id
    /// @param _requestIds array of request ids
    /// @param _hints checkpoint hints. can be found with `findCheckpointHints(_requestIds, 1, getLastCheckpointIndex())`
    /// @return claimableEthValues amount of claimable ether for each request, amount is equal to 0 if request
    ///  is not finalized or already claimed
    function getClaimableEther(
        uint256[] calldata _requestIds,
        uint256[] calldata _hints
    ) external view returns (uint256[] memory claimableEthValues);

    function findCheckpointHints(
        uint256[] calldata _requestIds,
        uint256 _firstIndex,
        uint256 _lastIndex
    ) external view returns (uint256[] memory hintIds);
    function getLastCheckpointIndex() external view returns (uint256);

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);
}
