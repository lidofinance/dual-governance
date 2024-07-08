pragma solidity 0.8.23;

contract WithdrawalQueueModel {
    uint256 _lastFinalizedRequestId;

    function getLastFinalizedRequestId() external view returns (uint256) {
        return _lastFinalizedRequestId;
    }
}
