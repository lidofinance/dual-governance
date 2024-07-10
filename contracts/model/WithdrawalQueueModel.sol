pragma solidity 0.8.23;

contract WithdrawalQueueModel {
    uint256 public constant MIN_STETH_WITHDRAWAL_AMOUNT = 100;
    uint256 public constant MAX_STETH_WITHDRAWAL_AMOUNT = 1000 * 1e18;

    uint256 _lastFinalizedRequestId;

    function getLastFinalizedRequestId() external view returns (uint256) {
        return _lastFinalizedRequestId;
    }
}
