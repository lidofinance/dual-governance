pragma solidity 0.8.26;

import "contracts/interfaces/IWithdrawalQueue.sol";
import "contracts/interfaces/IStETH.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract WithdrawalQueueModel is IWithdrawalQueue, ERC721 {
    IStETH public stETH;
    uint256 public constant MIN_STETH_WITHDRAWAL_AMOUNT = 100;
    uint256 public constant MAX_STETH_WITHDRAWAL_AMOUNT = 1000 * 1e18;

    uint256 _lastRequestId;
    uint256 _lastFinalizedRequestId;

    struct WithdrawalRequest {
        uint256 amountOfStETH;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    mapping(uint256 => WithdrawalRequest) private _requests;

    constructor(IStETH _stETH) ERC721("WithdrawalQueue", "WQ") {
        stETH = _stETH;
    }

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external override returns (uint256[] memory requestIds) {
        require(_amounts.length > 0, "No amounts provided");
        requestIds = new uint256[](_amounts.length);

        for (uint256 i = 0; i < _amounts.length; i++) {
            require(_amounts[i] >= MIN_STETH_WITHDRAWAL_AMOUNT, "Amount too small");
            require(_amounts[i] <= MAX_STETH_WITHDRAWAL_AMOUNT, "Amount too large");

            stETH.transferFrom(msg.sender, address(this), _amounts[i]);

            // Create a new withdrawal request
            _lastRequestId++;
            _requests[_lastRequestId] = WithdrawalRequest({
                amountOfStETH: _amounts[i],
                owner: _owner,
                timestamp: block.timestamp,
                isFinalized: false,
                isClaimed: false
            });

            _mint(_owner, _lastRequestId);
            requestIds[i] = _lastRequestId;
        }
    }

    function finalizeWithdrawal(address _to, uint256 _requestId) external {
        require(_exists(_requestId), "Request does not exist");
        WithdrawalRequest storage request = _requests[_requestId];
        require(!request.isFinalized, "Already finalized");

        request.isFinalized = true;
        _lastFinalizedRequestId = _requestId;

        stETH.transfer(_to, request.amountOfStETH);
    }

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata) external override {
        for (uint256 i = 0; i < requestIds.length; i++) {
            uint256 requestId = requestIds[i];
            require(ownerOf(requestId) == msg.sender, "Not the owner");
            require(_requests[requestId].isFinalized, "Not finalized");

            // Mark the request as claimed
            _requests[requestId].isClaimed = true;

            _burn(requestId);
        }
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
                amountOfShares: 0, // add real calculation if needed
                owner: request.owner,
                timestamp: request.timestamp,
                isFinalized: request.isFinalized,
                isClaimed: request.isClaimed
            });
        }
    }

    function getClaimableEther(
        uint256[] calldata,
        uint256[] calldata
    ) external view override(IWithdrawalQueue) returns (uint256[] memory claimableEthValues) {
        uint256[] memory emptyArray;
        return emptyArray;
    }

    function findCheckpointHints(
        uint256[] calldata,
        uint256,
        uint256
    ) external view override(IWithdrawalQueue) returns (uint256[] memory hintIds) {
        uint256[] memory emptyArray;
        return emptyArray;
    }

    function getLastRequestId() external view override(IWithdrawalQueue) returns (uint256) {
        return _lastRequestId;
    }

    function getLastFinalizedRequestId() external view override(IWithdrawalQueue) returns (uint256) {
        return _lastFinalizedRequestId;
    }

    function getLastCheckpointIndex() external view override(IWithdrawalQueue) returns (uint256) {
        return 0;
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
