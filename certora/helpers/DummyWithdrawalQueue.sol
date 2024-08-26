pragma solidity ^0.8.26;

import {IWithdrawalQueue, WithdrawalRequestStatus} from "../../contracts/interfaces/IWithdrawalQueue.sol";


import "../../contracts/interfaces/IStETH.sol";

// This implementation is only mock which will is later summarised by NONDET and HAVOC summary
contract DummyWithdrawalQueue is IWithdrawalQueue {

    // The Prover will assume a contant but random value;
    uint256 public MAX_STETH_WITHDRAWAL_AMOUNT; 
    uint256 public MIN_STETH_WITHDRAWAL_AMOUNT;
    
    uint256 internal lastRequestId;
    
    mapping(address => uint256) balances;
    mapping(uint256 => address) owner;

    IStETH public stETH;

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {

        //summary as nondet 
    }

    function transferFrom(address from, address to, uint256 requestId) external {
        require (owner[requestId] == from && balances[from] >= 1);
        owner[requestId] = to;
        balances[from] = balances[from] -1;
        balances[to] = balances[to] -1;
    }


    function balanceOf(address owner) external view returns (uint256) {
        return balances[owner];
    }

    mapping(uint256 => uint256) amountOfStETH;
    function getClaimableEther(
        uint256[] calldata _requestIds,
        uint256[] calldata _hints
    ) external view returns (uint256[] memory claimableEthValues) {
        //summary as nondet 
    }

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds) {
        for (uint256 i = 0; i < _amounts.length; ++i) { 
                stETH.transferFrom(msg.sender, address(this), _amounts[i]);
                uint256 amountOfShares = stETH.getSharesByPooledEth(_amounts[i]);
                requestIds[i] = lastRequestId + 1;
                lastRequestId += 1;
                //todo - update amountOfStETH
                owner[requestIds[i]] = _owner;
        }
    }

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external {
        for (uint256 i = 0; i < requestIds.length; ++i) {
            //todo;
        }
    }


    uint256[] internal  hints;

    function findCheckpointHints(
        uint256[] calldata _requestIds,
        uint256 _firstIndex,
        uint256 _lastIndex
    ) external view returns (uint256[] memory ) {
        return hints;
    }

    uint256 lastCheckpointIndex;
    function getLastCheckpointIndex() external view returns (uint256) {
        return lastCheckpointIndex;
    }




    function grantRole(bytes32 role, address account) external {
        //unused
        assert(false);
    }
    function pauseFor(uint256 duration) external {}

    function isPaused() external returns (bool b) {
        //unused
        assert(false);
    }

    function getLastRequestId() external view returns (uint256 r) {
        //unused
        assert(false);
    }

    function requestWithdrawalsWstETH(uint256[] calldata amounts, address owner) external returns (uint256[] memory b) {
        //unused
    assert(false);
    }



    function getLastFinalizedRequestId() external view returns (uint256 c) {
        //unused
        assert(false);
    }




}
