// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol"; /*, ERC721("test", "test")*/
import {IWithdrawalQueue, WithdrawalRequestStatus} from "contracts/interfaces/IWithdrawalQueue.sol";

contract WithdrawalQueueMock is IWithdrawalQueue {
    uint256 _lastRequestId;
    uint256 _lastFinalizedRequestId;
    uint256 _minStETHWithdrawalAmount;
    uint256 _maxStETHWithdrawalAmount;
    uint256[] _requestWithdrawalsResult;

    constructor() {}

    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256) {
        return _minStETHWithdrawalAmount;
    }

    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256) {
        return _maxStETHWithdrawalAmount;
    }

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external {
        revert("Not Implemented");
    }

    function getLastRequestId() external view returns (uint256) {
        return _lastRequestId;
    }

    function getLastFinalizedRequestId() external view returns (uint256) {
        return _lastFinalizedRequestId;
    }

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        revert("Not Implemented");
    }

    /// @notice Returns amount of ether available for claim for each provided request id
    /// @param _requestIds array of request ids
    /// @param _hints checkpoint hints. can be found with `findCheckpointHints(_requestIds, 1, getLastCheckpointIndex())`
    /// @return claimableEthValues amount of claimable ether for each request, amount is equal to 0 if request
    ///  is not finalized or already claimed
    function getClaimableEther(
        uint256[] calldata _requestIds,
        uint256[] calldata _hints
    ) external view returns (uint256[] memory claimableEthValues) {
        revert("Not Implemented");
    }

    function findCheckpointHints(
        uint256[] calldata _requestIds,
        uint256 _firstIndex,
        uint256 _lastIndex
    ) external view returns (uint256[] memory hintIds) {
        revert("Not Implemented");
    }

    function getLastCheckpointIndex() external view returns (uint256) {
        revert("Not Implemented");
    }

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds) {
        return _requestWithdrawalsResult;
    }

    function balanceOf(address owner) external view returns (uint256 balance) {
        revert("Not Implemented");
    }

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        revert("Not Implemented");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external {
        revert("Not Implemented");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        revert("Not Implemented");
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        revert("Not Implemented");
    }

    function approve(address to, uint256 tokenId) external {
        revert("Not Implemented");
    }

    function setApprovalForAll(address operator, bool approved) external {
        revert("Not Implemented");
    }

    function getApproved(uint256 tokenId) external view returns (address operator) {
        revert("Not Implemented");
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        revert("Not Implemented");
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        revert("Not Implemented");
    }

    function setLastRequestId(uint256 id) public {
        _lastRequestId = id;
    }

    function setLastFinalizedRequestId(uint256 id) public {
        _lastFinalizedRequestId = id;
    }

    function setMinStETHWithdrawalAmount(uint256 amount) public {
        _minStETHWithdrawalAmount = amount;
    }

    function setMaxStETHWithdrawalAmount(uint256 amount) public {
        _maxStETHWithdrawalAmount = amount;
    }

    function setRequestWithdrawalsResult(uint256[] memory requestIds) public {
        _requestWithdrawalsResult = requestIds;
    }
}
