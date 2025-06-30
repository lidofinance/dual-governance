// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";
import {ETHValues, sendTo} from "contracts/types/ETHValue.sol";

/* solhint-disable no-unused-vars,custom-errors */
contract WithdrawalQueueMock is IWithdrawalQueue {
    error InvalidRequestId();
    error ArraysLengthMismatch();

    uint256 public immutable REVERT_ON_ID = type(uint256).max;

    uint256 private _lastRequestId;
    uint256 private _lastFinalizedRequestId;
    uint256 private _minStETHWithdrawalAmount;
    uint256 private _maxStETHWithdrawalAmount;
    uint256 private _claimableAmount;
    uint256 private _requestWithdrawalsTransferAmount;
    uint256 private _lastCheckpointIndex;
    uint256[] private _getClaimableEtherResult;
    uint256[] private _requestWithdrawalsResult;
    IERC20 private _stETH;
    uint256[] private _checkpointHints;
    WithdrawalRequestStatus[] private _withdrawalRequestsStatuses;

    constructor(IERC20 stETH) {
        _stETH = stETH;
    }

    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256) {
        return _minStETHWithdrawalAmount;
    }

    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256) {
        return _maxStETHWithdrawalAmount;
    }

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external {
        if (requestIds.length != hints.length) {
            revert ArraysLengthMismatch();
        }

        if (_claimableAmount == 0) {
            return;
        }

        ETHValues.from(_claimableAmount).sendTo(payable(msg.sender));

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
        view
        returns (WithdrawalRequestStatus[] memory)
    {
        return _withdrawalRequestsStatuses;
    }

    function getClaimableEther(
        uint256[] calldata _requestIds,
        uint256[] calldata /* _hints */
    ) external view returns (uint256[] memory) {
        if (_requestIds.length > 0 && REVERT_ON_ID == _requestIds[0]) {
            revert InvalidRequestId();
        }

        return _getClaimableEtherResult;
    }

    function findCheckpointHints(
        uint256[] calldata, /* _requestIds */
        uint256, /* _firstIndex */
        uint256 /* _lastIndex */
    ) external view returns (uint256[] memory) {
        return _checkpointHints;
    }

    function getLastCheckpointIndex() external view returns (uint256) {
        return _lastCheckpointIndex;
    }

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds) {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            if (_amounts[i] < _minStETHWithdrawalAmount) {
                revert("Amount is less than MIN_STETH_WITHDRAWAL_AMOUNT");
            }
            if (_amounts[i] > _maxStETHWithdrawalAmount) {
                revert("Amount is more than MAX_STETH_WITHDRAWAL_AMOUNT");
            }
            totalAmount += _amounts[i];
        }

        if (_requestWithdrawalsTransferAmount > 0) {
            _stETH.transferFrom(_owner, address(this), _requestWithdrawalsTransferAmount);
            setRequestWithdrawalsTransferAmount(0);
        } else {
            if (totalAmount > 0) {
                _stETH.transferFrom(_owner, address(this), totalAmount);
            }
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

    function transferFrom(address, /* from */ address, /* to */ uint256 /* tokenId */ ) external pure {}

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

    function setWithdrawalRequestsStatuses(WithdrawalRequestStatus[] memory statuses) public {
        delete _withdrawalRequestsStatuses;

        for (uint256 i = 0; i < statuses.length; ++i) {
            _withdrawalRequestsStatuses.push(statuses[i]);
        }
    }

    function setClaimableEtherResult(uint256[] memory claimableEther) public {
        _getClaimableEtherResult = claimableEther;
    }

    function setLastCheckpointIndex(uint256 index) public {
        _lastCheckpointIndex = index;
    }

    function setCheckpointHints(uint256[] memory hints) public {
        _checkpointHints = hints;
    }

    function PAUSE_ROLE() external pure returns (bytes32) {
        return keccak256("PAUSE_ROLE");
    }

    function RESUME_ROLE() external pure returns (bytes32) {
        return keccak256("PAUSE_ROLE");
    }
}
