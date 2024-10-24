// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IWithdrawalQueue, WithdrawalRequestStatus} from "contracts/interfaces/IWithdrawalQueue.sol";
import {IStETH} from "contracts/interfaces/IStETH.sol";
import {StETHMock} from "./StETHMock.sol";

contract UnsafeWithdrawalQueueMock is IWithdrawalQueue, IERC721Metadata {
    using EnumerableSet for EnumerableSet.UintSet;

    struct WithdrawalRequest {
        /// @notice sum of the all ST_ETH submitted for withdrawals including this request
        uint128 cumulativeStETH;
        /// @notice sum of the all shares locked for withdrawal including this request
        uint128 cumulativeShares;
        /// @notice address that can claim or transfer the request
        address owner;
        /// @notice block.timestamp when the request was created
        uint40 timestamp;
        /// @notice flag if the request was claimed
        bool claimed;
        /// @notice timestamp of last oracle report for this request
        uint40 reportTimestamp;
    }

    struct Checkpoint {
        uint256 fromRequestId;
        uint256 maxShareRate;
    }

    ///

    error ApprovalToOwner();
    error ArraysLengthMismatch(uint256 _firstArrayLength, uint256 _secondArrayLength);
    error InvalidHint(uint256 _hint);
    error InvalidRequestId(uint256 _requestId);
    error InvalidRequestIdRange(uint256 startId, uint256 endId);
    error NotOwnerOrApproved(address sender);
    error NotOwnerOrApprovedForAll(address sender);
    error RequestAlreadyClaimed(uint256 _requestId);
    error RequestIdsNotSorted();
    error RequestNotFoundOrNotFinalized(uint256 _requestId);
    error TransferToThemselves();
    error TransferToZeroAddress();

    ///

    uint256 public constant MIN_STETH_WITHDRAWAL_AMOUNT = 100;
    uint256 public constant MAX_STETH_WITHDRAWAL_AMOUNT = 1000 * 1e18;
    uint256 public constant PAUSE_INFINITELY = type(uint256).max;
    uint256 internal constant NOT_FOUND = 0;
    uint256 internal constant E27_PRECISION_BASE = 1e27;

    ///

    IStETH public ST_ETH;
    address payable private refundAddress;
    uint256 private lastRequestId = 0;
    uint256 private lastReportTimestamp = 0;
    uint256 private lastFinalizedRequestId = 0;
    uint256 private lastCheckpointIndex = 0;
    uint256 private lockedEtherAmount = 0;
    uint256 private resumeSinceTimestamp = 0;
    mapping(uint256 => WithdrawalRequest) private queue;
    mapping(address => EnumerableSet.UintSet) private requestsByOwner;
    mapping(uint256 => Checkpoint) private checkpoints;
    mapping(uint256 => address) private tokenApprovals;
    mapping(address => mapping(address => bool)) private operatorApprovals;

    ///

    constructor(address stEth, address payable _refundAddress) {
        ST_ETH = IStETH(stEth);
        refundAddress = _refundAddress;

        queue[0] = WithdrawalRequest(0, 0, address(0), uint40(block.timestamp), true, 0);
        checkpoints[lastCheckpointIndex] = Checkpoint(0, 0);
    }

    function name() external pure override returns (string memory) {
        return "WithdrawalQueueMock";
    }

    function symbol() external pure override returns (string memory) {
        return "MockUnstETH";
    }

    function tokenURI(uint256 /* _requestId */ ) public view virtual override returns (string memory) {
        return "";
    }

    function balanceOf(address _owner) external view override returns (uint256) {
        return requestsByOwner[_owner].length();
    }

    function ownerOf(uint256 _requestId) public view override returns (address) {
        if (_requestId == 0 || _requestId > lastRequestId) revert InvalidRequestId(_requestId);

        WithdrawalRequest storage request = queue[_requestId];
        if (request.claimed) revert RequestAlreadyClaimed(_requestId);

        return request.owner;
    }

    function getLastRequestId() public view returns (uint256) {
        return lastRequestId;
    }

    function getLastFinalizedRequestId() public view returns (uint256) {
        return lastFinalizedRequestId;
    }

    function getLastCheckpointIndex() public view returns (uint256) {
        return lastCheckpointIndex;
    }

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) public returns (uint256[] memory requestIds) {
        requestIds = new uint256[](_amounts.length);
        for (uint256 i = 0; i < _amounts.length; ++i) {
            requestIds[i] = _requestWithdrawal(_amounts[i], _owner);
        }
    }

    function findCheckpointHints(
        uint256[] calldata _requestIds,
        uint256 _firstIndex,
        uint256 _lastIndex
    ) external view returns (uint256[] memory hintIds) {
        hintIds = new uint256[](_requestIds.length);
        uint256 prevRequestId = 0;
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            if (_requestIds[i] < prevRequestId) revert RequestIdsNotSorted();
            hintIds[i] = _findCheckpointHint(_requestIds[i], _firstIndex, _lastIndex);
            _firstIndex = hintIds[i];
            prevRequestId = _requestIds[i];
        }
    }

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        statuses = new WithdrawalRequestStatus[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            statuses[i] = _getStatus(_requestIds[i]);
        }
    }

    function getClaimableEther(
        uint256[] calldata _requestIds,
        uint256[] calldata _hints
    ) external view returns (uint256[] memory claimableEthValues) {
        claimableEthValues = new uint256[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            claimableEthValues[i] = _getClaimableEther(_requestIds[i], _hints[i]);
        }
    }

    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external {
        if (_requestIds.length != _hints.length) {
            revert ArraysLengthMismatch(_requestIds.length, _hints.length);
        }

        for (uint256 i = 0; i < _requestIds.length; ++i) {
            _claim(_requestIds[i], _hints[i], payable(msg.sender));
        }
    }

    function safeTransferFrom(address _from, address _to, uint256 _requestId) external override {
        safeTransferFrom(_from, _to, _requestId, "");
    }

    function safeTransferFrom(
        address, /* _from */
        address, /* _to */
        uint256, /* _requestId */
        bytes memory /* _data */
    ) public override {
        revert("Not implemented");
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _requestId
    ) external override(IWithdrawalQueue, IERC721) {
        _transfer(_from, _to, _requestId);
    }

    function approve(address _to, uint256 _requestId) external override {
        address _owner = ownerOf(_requestId);
        if (_to == _owner) revert ApprovalToOwner();
        if (msg.sender != _owner && !isApprovedForAll(_owner, msg.sender)) revert NotOwnerOrApprovedForAll(msg.sender);

        tokenApprovals[_requestId] = _to;
    }

    function setApprovalForAll(address _operator, bool _approved) external override {
        operatorApprovals[msg.sender][_operator] = _approved;
    }

    function getApproved(uint256 _requestId) external view override returns (address) {
        if (!_existsAndNotClaimed(_requestId)) revert InvalidRequestId(_requestId);

        return tokenApprovals[_requestId];
    }

    function isApprovedForAll(address _owner, address _operator) public view override returns (bool) {
        return operatorApprovals[_owner][_operator];
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721).interfaceId || interfaceId == type(IERC721Metadata).interfaceId
        // 0x49064906 is magic number ERC4906 interfaceId as defined in the standard https://eips.ethereum.org/EIPS/eip-4906
        || interfaceId == bytes4(0x49064906);
    }

    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable {
        _finalize(_lastRequestIdToBeFinalized, msg.value, _maxShareRate);
    }

    function refundEth(uint256 amountOfETH) public {
        Address.sendValue(refundAddress, amountOfETH);
    }

    function markClaimed(uint256[] calldata _requestIds) external {
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            _markClaimed(_requestIds[i]);
        }
    }

    function resume() external {
        resumeSinceTimestamp = block.timestamp;
    }

    function pauseFor(uint256 _duration) external {
        uint256 resumeSince;
        if (_duration == PAUSE_INFINITELY) {
            resumeSince = PAUSE_INFINITELY;
        } else {
            resumeSince = block.timestamp + _duration;
        }
        resumeSinceTimestamp = resumeSince;
    }

    function isPaused() external view returns (bool) {
        return block.timestamp < resumeSinceTimestamp;
    }

    function getResumeSinceTimestamp() external view returns (uint256) {
        return resumeSinceTimestamp;
    }

    ///////////////////////////////

    function _requestWithdrawal(uint256 _amountOfStETH, address _owner) internal returns (uint256 requestId) {
        ST_ETH.transferFrom(msg.sender, address(this), _amountOfStETH);

        uint256 amountOfShares = ST_ETH.getSharesByPooledEth(_amountOfStETH);

        requestId = _enqueue(uint128(_amountOfStETH), uint128(amountOfShares), _owner);
    }

    function _enqueue(
        uint128 _amountOfStETH,
        uint128 _amountOfShares,
        address _owner
    ) internal returns (uint256 requestId) {
        WithdrawalRequest memory lastRequest = queue[lastRequestId];

        uint128 cumulativeShares = lastRequest.cumulativeShares + _amountOfShares;
        uint128 cumulativeStETH = lastRequest.cumulativeStETH + _amountOfStETH;

        requestId = lastRequestId + 1;

        lastRequestId = requestId;

        WithdrawalRequest memory newRequest = WithdrawalRequest(
            cumulativeStETH, cumulativeShares, _owner, uint40(block.timestamp), false, uint40(lastReportTimestamp)
        );
        queue[requestId] = newRequest;
        assert(requestsByOwner[_owner].add(requestId));
    }

    function _findCheckpointHint(uint256 _requestId, uint256 _start, uint256 _end) internal view returns (uint256) {
        if (_requestId == 0 || _requestId > lastRequestId) revert InvalidRequestId(_requestId);

        if (_start == 0 || _end > lastCheckpointIndex) revert InvalidRequestIdRange(_start, _end);

        if (lastCheckpointIndex == 0 || _requestId > lastFinalizedRequestId || _start > _end) return NOT_FOUND;

        if (_requestId >= checkpoints[_end].fromRequestId) {
            if (_end == lastCheckpointIndex) return _end;
            if (_requestId < checkpoints[_end + 1].fromRequestId) return _end;

            return NOT_FOUND;
        }

        if (_requestId < checkpoints[_start].fromRequestId) {
            return NOT_FOUND;
        }

        uint256 min = _start;
        uint256 max = _end - 1;

        while (max > min) {
            uint256 mid = (max + min + 1) / 2;
            if (checkpoints[mid].fromRequestId <= _requestId) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    function _getStatus(uint256 _requestId) internal view returns (WithdrawalRequestStatus memory status) {
        if (_requestId == 0 || _requestId > lastRequestId) revert InvalidRequestId(_requestId);

        WithdrawalRequest memory request = queue[_requestId];
        WithdrawalRequest memory previousRequest = queue[_requestId - 1];

        status = WithdrawalRequestStatus(
            request.cumulativeStETH - previousRequest.cumulativeStETH,
            request.cumulativeShares - previousRequest.cumulativeShares,
            request.owner,
            request.timestamp,
            _requestId <= lastFinalizedRequestId,
            request.claimed
        );
    }

    function _getClaimableEther(uint256 _requestId, uint256 _hint) internal view returns (uint256) {
        if (_requestId == 0 || _requestId > lastRequestId) revert InvalidRequestId(_requestId);

        if (_requestId > lastFinalizedRequestId) return 0;

        WithdrawalRequest storage request = queue[_requestId];
        if (request.claimed) return 0;

        return _calculateClaimableEther(request, _requestId, _hint);
    }

    function _calculateClaimableEther(
        WithdrawalRequest storage _request,
        uint256 _requestId,
        uint256 _hint
    ) internal view returns (uint256 claimableEther) {
        if (_hint == 0) revert InvalidHint(_hint);

        if (_hint > lastCheckpointIndex) revert InvalidHint(_hint);

        Checkpoint memory checkpoint = checkpoints[_hint];

        if (_requestId < checkpoint.fromRequestId) revert InvalidHint(_hint);
        if (_hint < lastCheckpointIndex) {
            Checkpoint memory nextCheckpoint = checkpoints[_hint + 1];
            if (nextCheckpoint.fromRequestId <= _requestId) revert InvalidHint(_hint);
        }

        WithdrawalRequest memory prevRequest = queue[_requestId - 1];
        (uint256 batchShareRate, uint256 eth, uint256 shares) = _calcBatch(prevRequest, _request);

        if (batchShareRate > checkpoint.maxShareRate) {
            eth = shares * checkpoint.maxShareRate / E27_PRECISION_BASE;
        }

        return eth;
    }

    function _calcBatch(
        WithdrawalRequest memory _preStartRequest,
        WithdrawalRequest memory _endRequest
    ) internal pure returns (uint256 shareRate, uint256 _stETH, uint256 shares) {
        _stETH = _endRequest.cumulativeStETH - _preStartRequest.cumulativeStETH;
        shares = _endRequest.cumulativeShares - _preStartRequest.cumulativeShares;

        shareRate = _stETH * E27_PRECISION_BASE / shares;
    }

    function _claim(uint256 _requestId, uint256 _hint, address payable _recipient) internal {
        if (_requestId == 0) revert InvalidRequestId(_requestId);
        if (_requestId > lastFinalizedRequestId) revert RequestNotFoundOrNotFinalized(_requestId);

        WithdrawalRequest storage request = queue[_requestId];

        if (request.claimed) revert RequestAlreadyClaimed(_requestId);

        // NB! This allows claim for anyone! // if (request.owner != msg.sender) revert NotOwner(msg.sender, request.owner);

        request.claimed = true;
        assert(requestsByOwner[request.owner].remove(_requestId));

        uint256 ethWithDiscount = _calculateClaimableEther(request, _requestId, _hint);
        lockedEtherAmount = lockedEtherAmount - ethWithDiscount;
        Address.sendValue(_recipient, ethWithDiscount);
    }

    function _transfer(address _from, address _to, uint256 _requestId) internal {
        if (_to == address(0)) revert TransferToZeroAddress();
        if (_to == _from) revert TransferToThemselves();
        if (_requestId == 0 || _requestId > lastRequestId) revert InvalidRequestId(_requestId);

        WithdrawalRequest storage request = queue[_requestId];
        if (request.claimed) revert RequestAlreadyClaimed(_requestId);

        // NB! This allows transfer for anyone // if (_from != request.owner) revert TransferFromIncorrectOwner(_from, request.owner);

        address msgSender = msg.sender;
        if (!(_from == msgSender || isApprovedForAll(_from, msgSender) || tokenApprovals[_requestId] == msgSender)) {
            revert NotOwnerOrApproved(msgSender);
        }

        delete tokenApprovals[_requestId];
        request.owner = _to;

        assert(requestsByOwner[_from].remove(_requestId));
        assert(requestsByOwner[_to].add(_requestId));
    }

    function _existsAndNotClaimed(uint256 _requestId) internal view returns (bool) {
        return _requestId > 0 && _requestId <= lastRequestId && !queue[_requestId].claimed;
    }

    function _finalize(uint256 _lastRequestIdToBeFinalized, uint256 _amountOfETH, uint256 _maxShareRate) internal {
        if (_lastRequestIdToBeFinalized > lastRequestId) revert InvalidRequestId(_lastRequestIdToBeFinalized);
        if (_lastRequestIdToBeFinalized <= lastFinalizedRequestId) revert InvalidRequestId(_lastRequestIdToBeFinalized);

        WithdrawalRequest memory lastFinalizedRequest = queue[lastFinalizedRequestId];
        WithdrawalRequest memory requestToFinalize = queue[_lastRequestIdToBeFinalized];

        uint128 stETHToFinalize = requestToFinalize.cumulativeStETH - lastFinalizedRequest.cumulativeStETH;

        uint256 firstRequestIdToFinalize = lastFinalizedRequestId + 1;

        checkpoints[lastCheckpointIndex + 1] = Checkpoint(firstRequestIdToFinalize, _maxShareRate);
        lastCheckpointIndex = lastCheckpointIndex + 1;

        lockedEtherAmount = lockedEtherAmount + _amountOfETH;
        lastFinalizedRequestId = _lastRequestIdToBeFinalized;

        StETHMock(address(ST_ETH)).burn(address(this), stETHToFinalize);
    }

    function _markClaimed(uint256 _requestId) internal {
        if (_requestId == 0) revert InvalidRequestId(_requestId);
        if (_requestId > lastFinalizedRequestId) revert RequestNotFoundOrNotFinalized(_requestId);

        WithdrawalRequest storage request = queue[_requestId];

        if (request.claimed) revert RequestAlreadyClaimed(_requestId);

        request.claimed = true;
        assert(requestsByOwner[request.owner].remove(_requestId));
    }
}
