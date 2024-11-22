// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWithdrawalQueue, WithdrawalRequestStatus} from "contracts/interfaces/IWithdrawalQueue.sol";
import {ETHValues, sendTo} from "contracts/types/ETHValue.sol";

/* solhint-disable no-unused-vars,custom-errors */
contract WithdrawalQueueMock is IWithdrawalQueue {
    address private _stETH;
    uint256 private _lastRequestId;
    uint256 private _lastFinalizedRequestId;
    uint256 private _minStETHWithdrawalAmount;
    uint256 private _maxStETHWithdrawalAmount;
    uint256 private _claimableAmount;
    uint256 private _requestWithdrawalsTransferAmount;
    uint256[] private _requestWithdrawalsResult;

    constructor(address stETH) {
        _stETH = stETH;
    }

    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256) {
        return _minStETHWithdrawalAmount;
    }

    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256) {
        return _maxStETHWithdrawalAmount;
    }

    function claimWithdrawals(uint256[] calldata, /* requestIds */ uint256[] calldata /* hints */ ) external {
        if (_claimableAmount == 0) {
            return;
        }

        sendTo(ETHValues.from(_claimableAmount), payable(msg.sender));

        setClaimableAmount(0);
    }

    function getLastRequestId() external view returns (uint256) {
        return _lastRequestId;
    }

    function getLastFinalizedRequestId() external view returns (uint256) {
        return _lastFinalizedRequestId;
    }

    function getWithdrawalStatus(uint256[] calldata /* _requestIds */ )
        external
        pure
        returns (WithdrawalRequestStatus[] memory /* statuses */ )
    {
        revert("Not Implemented");
    }

    function getClaimableEther(
        uint256[] calldata, /* _requestIds */
        uint256[] calldata /* _hints */
    ) external pure returns (uint256[] memory /* claimableEthValues */ ) {
        revert("Not Implemented");
    }

    function findCheckpointHints(
        uint256[] calldata, /* _requestIds */
        uint256, /* _firstIndex */
        uint256 /* _lastIndex */
    ) external pure returns (uint256[] memory /* hintIds */ ) {
        revert("Not Implemented");
    }

    function getLastCheckpointIndex() external pure returns (uint256) {
        revert("Not Implemented");
    }

    function requestWithdrawals(
        uint256[] calldata, /* _amounts */
        address /* _owner */
    ) external returns (uint256[] memory requestIds) {
        if (_requestWithdrawalsTransferAmount > 0) {
            IERC20(_stETH).transferFrom(msg.sender, address(this), _requestWithdrawalsTransferAmount);
            setRequestWithdrawalsTransferAmount(0);
        }

        return _requestWithdrawalsResult;
    }

    function balanceOf(address /* owner */ ) external pure returns (uint256 /* balance */ ) {
        revert("Not Implemented");
    }

    function ownerOf(uint256 /* tokenId */ ) external pure returns (address /* owner */ ) {
        revert("Not Implemented");
    }

    function safeTransferFrom(
        address, /* from */
        address, /* to */
        uint256, /* tokenId */
        bytes calldata /* data */
    ) external pure {
        revert("Not Implemented");
    }

    function safeTransferFrom(address, /* from */ address, /* to */ uint256 /* tokenId */ ) external pure {
        revert("Not Implemented");
    }

    function transferFrom(address, /* from */ address, /* to */ uint256 /* tokenId */ ) external pure {
        revert("Not Implemented");
    }

    function approve(address, /* to */ uint256 /* tokenId */ ) external pure {
        revert("Not Implemented");
    }

    function setApprovalForAll(address, /* operator */ bool /* approved */ ) external pure {
        revert("Not Implemented");
    }

    function getApproved(uint256 /* tokenId */ ) external pure returns (address /* operator */ ) {
        revert("Not Implemented");
    }

    function isApprovedForAll(address, /* owner */ address /* operator */ ) external pure returns (bool) {
        revert("Not Implemented");
    }

    function supportsInterface(bytes4 /* interfaceId */ ) external pure returns (bool) {
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

    function setClaimableAmount(uint256 claimableAmount) public {
        _claimableAmount = claimableAmount;
    }

    function setRequestWithdrawalsTransferAmount(uint256 requestWithdrawalsTransferAmount) public {
        _requestWithdrawalsTransferAmount = requestWithdrawalsTransferAmount;
    }
}
