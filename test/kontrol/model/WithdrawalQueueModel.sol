pragma solidity 0.8.26;

import "contracts/interfaces/IWithdrawalQueue.sol";
import "contracts/interfaces/IStETH.sol";
import "forge-std/Vm.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract WithdrawalQueueModel is KontrolCheats, IWithdrawalQueue, ERC721 {
    Vm immutable vm;
    IStETH public immutable stETH;
    uint256 public constant MIN_STETH_WITHDRAWAL_AMOUNT = 100;
    uint256 public constant MAX_STETH_WITHDRAWAL_AMOUNT = 1000 * 1e18;

    uint256 _lastRequestId;
    uint256 _lastFinalizedRequestId;
    uint256 _lockedEtherAmount;

    struct WithdrawalRequest {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    mapping(uint256 => WithdrawalRequest) private _requests;

    constructor(Vm _vm, IStETH _stETH) ERC721("WithdrawalQueue", "WQ") {
        vm = _vm;
        stETH = _stETH;
    }

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) public override returns (uint256[] memory requestIds) {
        // Assume queue is not paused
        //_checkResumed();
        if (_owner == address(0)) _owner = msg.sender;
        requestIds = new uint256[](_amounts.length);
        for (uint256 i = 0; i < _amounts.length; ++i) {
            require(_amounts[i] >= MIN_STETH_WITHDRAWAL_AMOUNT, "Amount too small");
            require(_amounts[i] <= MAX_STETH_WITHDRAWAL_AMOUNT, "Amount too large");

            stETH.transferFrom(msg.sender, address(this), _amounts[i]);

            uint256 amountOfShares = stETH.getSharesByPooledEth(_amounts[i]);

            if (i == 0) {
                requestIds[i] = _lastRequestId + 1;
            } else {
                requestIds[i] = requestIds[i - 1] + 1;
            }
        }

        kevm.symbolicStorage(address(this));
    }

    function finalizeWithdrawal(address _to, uint256 _requestId) external {
        require(_exists(_requestId), "Request does not exist");
        WithdrawalRequest storage request = _requests[_requestId];
        require(!request.isFinalized, "Already finalized");

        request.isFinalized = true;
        _lastFinalizedRequestId = _requestId;

        stETH.transfer(_to, request.amountOfStETH);
    }

    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external override {
        require(_requestIds.length == _hints.length, "Arrays length mismatch");

        for (uint256 i = 0; i < _requestIds.length; ++i) {
            require(_requestIds[i] != 0, "Invalid request");
            require(_requestIds[i] <= _lastFinalizedRequestId, "Request not found or not finalized");

            WithdrawalRequest storage request = _requests[_requestIds[i]];

            require(!request.isClaimed, "Request already claimed");
            require(request.owner == msg.sender, "Not owner");

            request.isClaimed = true;
            // Not tracking requests by owner in this model
            //assert(_getRequestsByOwner()[request.owner].remove(_requestId));

            uint128 ethWithDiscount = freshUInt128("ethWithDiscount");
            vm.assume(ethWithDiscount < 2 ** 96);
            vm.assume(ethWithDiscount <= _lockedEtherAmount);
            // because of the stETH rounding issue
            // (issue: https://github.com/lidofinance/lido-dao/issues/442 )
            // some dust (1-2 wei per request) will be accumulated upon claiming
            _lockedEtherAmount -= ethWithDiscount;
            _sendValue(msg.sender, ethWithDiscount);
        }
    }

    function _sendValue(address _recipient, uint256 _amount) internal {
        require(address(this).balance >= _amount, "Not enough ether");

        // solhint-disable-next-line
        (bool success,) = _recipient.call{value: _amount}("");
        require(success, "Can't send value; recipient may have reverted");
    }

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        override
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        statuses = new WithdrawalRequestStatus[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; i++) {
            uint256 requestId = _requestIds[i];
            WithdrawalRequest storage request = _requests[requestId];
            statuses[i] = WithdrawalRequestStatus({
                amountOfStETH: request.amountOfStETH,
                amountOfShares: request.amountOfShares,
                owner: request.owner,
                timestamp: request.timestamp,
                isFinalized: request.isFinalized,
                isClaimed: request.isClaimed
            });
        }
    }

    function getClaimableEther(
        uint256[] calldata _requestIds,
        uint256[] calldata
    ) external view override(IWithdrawalQueue) returns (uint256[] memory claimableEthValues) {
        claimableEthValues = new uint256[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            claimableEthValues[i] = freshUInt256("claimableEther");
        }
    }

    function findCheckpointHints(
        uint256[] calldata _requestIds,
        uint256,
        uint256
    ) external view override(IWithdrawalQueue) returns (uint256[] memory hintIds) {
        hintIds = new uint256[](_requestIds.length);

        for (uint256 i = 0; i < _requestIds.length; ++i) {
            hintIds[i] = freshUInt256("hintId");
        }
    }

    function getLastRequestId() external view override(IWithdrawalQueue) returns (uint256) {
        return _lastRequestId;
    }

    function getLastFinalizedRequestId() external view override(IWithdrawalQueue) returns (uint256) {
        return _lastFinalizedRequestId;
    }

    function getLastCheckpointIndex() external view override(IWithdrawalQueue) returns (uint256) {
        return freshUInt256("lastCheckpointIndex");
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function transferFrom(address from, address to, uint256 requestId) public override(IWithdrawalQueue, ERC721) {
        require(_isApprovedOrOwnerCustom(msg.sender, requestId), "Not owner nor approved");
        _transfer(from, to, requestId);
    }

    function _isApprovedOrOwnerCustom(address spender, uint256 tokenId) internal view returns (bool) {
        require(_exists(tokenId), "Token does not exist");
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }
}
