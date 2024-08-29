pragma solidity ^0.8.26;



import "../../contracts/interfaces/IStETH.sol";

// This implementation is only mock for ESCROW contract 
contract DummyWithdrawalQueue  {

    // The Prover will assume a contant but random value;
    uint256 public MAX_STETH_WITHDRAWAL_AMOUNT; 
    uint256 public MIN_STETH_WITHDRAWAL_AMOUNT;
    
    uint256 internal lastRequestId;
    uint256 internal lastFinalizedRequestId;
    
    mapping(address => uint256) balances;
    

    IStETH public stETH;

    struct WithdrawalRequestStatus {
        uint256 amountOfStETH; //
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    mapping(uint256 => WithdrawalRequestStatus) requests;


    function getLastFinalizedRequestId() public view returns (uint256) {
        return lastFinalizedRequestId;
    }

    uint256 randomNumOfFinalzied;
    // if reduction true we simulate reduce by half
    function finalize(uint256 upToRequestId, bool reduction)  external {
        for(uint256 i = lastFinalizedRequestId; i <= upToRequestId ; i++) {
         require(!requests[i].isFinalized);
         requests[i].isFinalized = true;
         if (reduction) {
            requests[i].amountOfStETH =  requests[i].amountOfStETH / 2;
         }
        }
        lastFinalizedRequestId = upToRequestId; 
    }

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        statuses = new WithdrawalRequestStatus[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            require(_requestIds[i] <= lastRequestId);
            statuses[i] = requests[_requestIds[i]];
        }
    }

    function transferFrom(address from, address to, uint256 requestId) external {
        require (requests[requestId].owner == from && balances[from] >= 1);
        requests[requestId].owner = to;
        balances[from] = balances[from] -1;
        balances[to] = balances[to] -1;
    }


    function balanceOf(address owner) external view returns (uint256) {
        return balances[owner];
    }


    function getClaimableEther(
        uint256[] calldata _requestIds,
        uint256[] calldata _hints
    ) external view returns (uint256[] memory claimableEthValues) {
        claimableEthValues = new uint256[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            uint256 _requestId = _requestIds[i];
            require (_requestId != 0 && _requestId <= lastRequestId) ;
            if (_requestId > lastFinalizedRequestId ||  requests[_requestId].isClaimed) {
                claimableEthValues[i] = 0;
            }
            else {
                claimableEthValues[i] = requests[_requestIds[i]].amountOfStETH;
            }
        }
    }

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds) {
        requestIds = new uint256[](_amounts.length);
        for (uint256 i = 0; i < _amounts.length; ++i) { 
                stETH.transferFrom(msg.sender, address(this), _amounts[i]);
                uint256 amountOfShares = stETH.getSharesByPooledEth(_amounts[i]);
                lastRequestId += 1;
                requestIds[i] = lastRequestId;
                requests[lastRequestId] = 
                        WithdrawalRequestStatus(
                            _amounts[i],
                            amountOfShares,
                            _owner,
                            block.timestamp,
                            false,
                            false);
        }
    }

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external {
        for (uint256 i = 0; i < requestIds.length; ++i) {
                require( ! requests[requestIds[i]].isClaimed && requests[requestIds[i]].isFinalized);
                requests[requestIds[i]].isClaimed = true;
                (bool success,) = msg.sender.call{value: requests[requestIds[i]].amountOfStETH }("");
                require(success);
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


}
