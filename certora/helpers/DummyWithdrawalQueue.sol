pragma solidity ^0.8.26;

import {IWithdrawalQueue, WithdrawalRequestStatus} from "../../contracts/interfaces/IWithdrawalQueue.sol";

// This implementation is only mock which will is later summarised by NONDET and HAVOC summary
contract DummyWithdrawalQueue is IWithdrawalQueue {
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256) {
        uint256 res;
        return res;
    }

    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256) {
        uint256 res;
        return res;
    }

    function getLastRequestId() external view returns (uint256) {
        uint256 res;
        return res;
    }

    function getClaimableEther(
        uint256[] calldata _requestIds,
        uint256[] calldata _hints
    ) external view returns (uint256[] memory claimableEthValues) {
        uint256[] memory res;
        return res;
    }

    function findCheckpointHints(
        uint256[] calldata _requestIds,
        uint256 _firstIndex,
        uint256 _lastIndex
    ) external view returns (uint256[] memory hintIds) {
        uint256[] memory res;
        return res;
    }

    function getLastCheckpointIndex() external view returns (uint256) {
        uint256 res;
        return res;
    }

    function grantRole(bytes32 role, address account) external {}
    function pauseFor(uint256 duration) external {}

    function isPaused() external returns (bool) {
        bool res;
        return res;
    }

    function requestWithdrawalsWstETH(uint256[] calldata amounts, address owner) external returns (uint256[] memory) {
        uint256[] memory res;
        return res;
    }

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external {}

    function getLastFinalizedRequestId() external view returns (uint256) {
        uint256 res;
        return res;
    }

    function transferFrom(address from, address to, uint256 requestId) external {}

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {}

    function balanceOf(address owner) external view returns (uint256) {
        uint256 res;
        return res;
    }

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds) {}
}
