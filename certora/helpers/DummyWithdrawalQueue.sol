pragma solidity ^0.8.26;



import "../../contracts/interfaces/IStETH.sol";

// This implementation is only mock for ESCROW contract 
contract DummyWithdrawalQueue  {

    // The Prover will assume a contant but random value;
    uint256 public MAX_STETH_WITHDRAWAL_AMOUNT; 
    uint256 public MIN_STETH_WITHDRAWAL_AMOUNT;
    
    uint256 internal lastRequestId;
    
    mapping(address => uint256) balances;
    mapping(uint256 => address) owner;

    IStETH public stETH;
/*
    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {

        //summary as nondet 
    }
*/
    function transferFrom(address from, address to, uint256 requestId) external {
        require (owner[requestId] == from && balances[from] >= 1);
        owner[requestId] = to;
        balances[from] = balances[from] -1;
        balances[to] = balances[to] -1;
    }


    function balanceOf(address owner) external view returns (uint256) {
        return balances[owner];
    }

    mapping(uint256 => uint256) amountOfETH;
    function getClaimableEther(
        uint256[] calldata _requestIds,
        uint256[] calldata _hints
    ) external view returns (uint256[] memory claimableEthValues) {
        claimableEthValues = new uint256[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            claimableEthValues[i] = amountOfETH[_requestIds[i]];
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
                requestIds[i] = lastRequestId + 1;
                lastRequestId += 1;
                amountOfETH[requestIds[i]] = _amounts[i];
                owner[requestIds[i]] = _owner;
        }
    }

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external {
        for (uint256 i = 0; i < requestIds.length; ++i) {
            //todo;
                (bool success,) = msg.sender.call{value: amountOfETH[requestIds[i]]}("");
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
