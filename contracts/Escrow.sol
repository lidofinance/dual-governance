// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Configuration} from "./Configuration.sol";
import {GovernanceState} from "./GovernanceState.sol";

struct WithdrawalRequestStatus {
    uint256 amountOfStETH;
    uint256 amountOfShares;
    address owner;
    uint256 timestamp;
    bool isFinalized;
    bool isClaimed;
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function totalShares() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

interface IStETH {
    function getSharesByPooledEth(
        uint256 ethAmount
    ) external view returns (uint256);

    function getPooledEthByShares(
        uint256 sharesAmount
    ) external view returns (uint256);

    function transferShares(address to, uint256 amount) external;
}

interface IWstETH {
    function wrap(uint256 stETHAmount) external returns (uint256);

    function unwrap(uint256 wstETHAmount) external returns (uint256);
}

interface IWithdrawalQueue {
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    function requestWithdrawalsWstETH(
        uint256[] calldata amounts,
        address owner
    ) external returns (uint256[] memory);

    function claimWithdrawals(
        uint256[] calldata requestIds,
        uint256[] calldata hints
    ) external;

    function getLastFinalizedRequestId() external view returns (uint256);

    function safeTransferFrom(
        address from,
        address to,
        uint256 requestId
    ) external;

    function getWithdrawalStatus(
        uint256[] calldata _requestIds
    ) external view returns (WithdrawalRequestStatus[] memory statuses);

    function balanceOf(address owner) external view returns (uint256);

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);
}

/**
 * A contract serving as a veto signalling and rage quit escrow.
 */
contract Escrow {
    error Unauthorized();
    error InvalidState();
    error NoUnrequestedWithdrawalsLeft();
    error SenderIsNotOwner(uint256 id);
    error TransferFailed(uint256 id);
    error NotClaimedWQRequests();

    event RageQuitAccumulationStarted();
    event RageQuitStarted();
    event WithdrawalsBatchRequested(
        uint256 indexed firstRequestId,
        uint256 indexed lastRequestId,
        uint256 wstEthLeftToRequest
    );

    enum State {
        Signalling,
        RageQuitAccumulation,
        RageQuit
    }

    Configuration internal immutable CONFIG;
    address internal immutable ST_ETH;
    address internal immutable WST_ETH;
    address internal immutable WITHDRAWAL_QUEUE;

    address internal _govState;
    State internal _state;

    uint256 internal _totalStEthSharesLocked;
    uint256 internal _totalWstEthLocked;
    uint256 internal _totalWithdrawalNftsAmountLocked;
    uint256 internal _totalNonNFTEthToShare;

    uint256 internal _rageQuitWstEthAmountTotal;
    uint256 internal _rageQuitWstEthAmountRequested;
    uint256 internal _lastWithdrawalRequestId;

    mapping(address => uint256) private _wstEthBalances;
    mapping(address => uint256) private _stEthSharesBalances;
    mapping(address => uint256) private _wqRequestsBalances;

    uint256 internal constant WITHDRAWAL_REQUESTS_LIMIT = 10_000 * 10 ** 18;

    mapping(uint256 => WithdrawalRequestStatus) private wqRequests;

    constructor(
        address config,
        address stEth,
        address wstEth,
        address withdrawalQueue
    ) {
        CONFIG = Configuration(config);
        ST_ETH = stEth;
        WST_ETH = wstEth;
        WITHDRAWAL_QUEUE = withdrawalQueue;
    }

    function initialize(address governanceState) external {
        if (_govState != address(0)) {
            revert Unauthorized();
        }
        _govState = governanceState;
    }

    ///
    /// Staker interface
    ///
    function lockStEth(uint256 amount) external {
        if (_state == State.RageQuit) {
            revert InvalidState();
        }
        IERC20(ST_ETH).transferFrom(msg.sender, address(this), amount);

        uint256 amountInShares = IStETH(ST_ETH).getSharesByPooledEth(amount);
        _stEthSharesBalances[msg.sender] += amountInShares;
        _totalStEthSharesLocked += amountInShares;

        _activateNextGovernanceState();
    }

    function lockWstEth(uint256 amount) external {
        if (_state == State.RageQuit) {
            revert InvalidState();
        }

        IERC20(WST_ETH).transferFrom(msg.sender, address(this), amount);

        _wstEthBalances[msg.sender] += amount;
        _totalWstEthLocked += amount;

        _activateNextGovernanceState();
    }

    function lockWithdrawalNFT(uint256[] memory ids) external {
        if (_state == State.RageQuit) {
            revert InvalidState();
        }

        WithdrawalRequestStatus[] memory wqRequestStatuses = IWithdrawalQueue(
            WITHDRAWAL_QUEUE
        ).getWithdrawalStatus(ids);
        uint256 wqRequestsAmount = 0;

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            IWithdrawalQueue(WITHDRAWAL_QUEUE).safeTransferFrom(
                msg.sender,
                address(this),
                id
            );
            wqRequests[id] = wqRequestStatuses[i];
            wqRequestsAmount += wqRequestStatuses[i].amountOfStETH;
        }

        _totalWithdrawalNftsAmountLocked += wqRequestsAmount;
        _wqRequestsBalances[msg.sender] += wqRequestsAmount;

        _activateNextGovernanceState();
    }

    function unlockStEth() external {
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        address sender = msg.sender;
        uint256 amountInShares = _stEthSharesBalances[sender];

        IStETH(ST_ETH).transferShares(sender, amountInShares);

        _stEthSharesBalances[sender] = 0;
        _totalStEthSharesLocked -= amountInShares;

        _activateNextGovernanceState();
    }

    function unlockWstEth() external {
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        address sender = msg.sender;
        uint256 amount = _wstEthBalances[sender];

        IStETH(ST_ETH).transferShares(sender, amount);

        _wstEthBalances[sender] = 0;
        _totalWstEthLocked -= amount;

        _activateNextGovernanceState();
    }

    function unlockWithdrawalNFT(uint256[] memory ids) external {
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        WithdrawalRequestStatus[] memory wqRequestStatuses = IWithdrawalQueue(
            WITHDRAWAL_QUEUE
        ).getWithdrawalStatus(ids);
        uint256 wqRequestsAmount = 0;

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            if (wqRequests[ids[i]].owner == msg.sender) {
                revert SenderIsNotOwner(id);
            }
            IWithdrawalQueue(WITHDRAWAL_QUEUE).safeTransferFrom(
                address(this),
                msg.sender,
                id
            );
            wqRequests[id].owner = address(0);
            wqRequestsAmount += wqRequestStatuses[i].amountOfStETH;
        }

        _wqRequestsBalances[msg.sender] -= wqRequestsAmount;
        _totalWithdrawalNftsAmountLocked -= wqRequestsAmount;

        _activateNextGovernanceState();
    }

    function initiateStEthWithdrawal(uint) external {
        if (_state == State.Signalling) {
            revert InvalidState();
        }

        uint256 wstEthBalance = IERC20(WST_ETH).balanceOf(address(this));
        if (wstEthBalance > 0) {
            IWstETH(WST_ETH).unwrap(wstEthBalance);
            _totalStEthSharesLocked += wstEthBalance;
            _totalWstEthLocked = 0;
        }

        _activateNextGovernanceState();
    }

    function claimETH() external {
        if (_state != State.RageQuit) {
            revert InvalidState();
        }

        if (IWithdrawalQueue(WITHDRAWAL_QUEUE).balanceOf(address(this)) > 0) {
            revert NotClaimedWQRequests();
        }

        address sender = msg.sender;

        uint256 ethToClaim = (_stEthSharesBalances[sender] *
            _totalNonNFTEthToShare) / _totalStEthSharesLocked;

        ethToClaim += _wqRequestsBalances[sender];

        _stEthSharesBalances[sender] = 0;
        _wqRequestsBalances[sender] = 0;

        payable(sender).transfer(ethToClaim);
    }

    ///
    /// State transitions
    ///

    function totalStEthLocked() public view returns (uint256) {
        return IStETH(ST_ETH).getPooledEthByShares(_totalStEthSharesLocked);
    }

    function getSignallingState()
        external
        view
        returns (uint256 totalSupport, uint256 rageQuitSupport)
    {
        uint256 stEthTotalSupply = IERC20(ST_ETH).totalSupply();
        uint256 totalRageQuitStEthLocked = IStETH(ST_ETH).getPooledEthByShares(
            _totalWstEthLocked + _totalStEthSharesLocked
        );
        uint256 totalStakedEthLocked = totalRageQuitStEthLocked +
            _totalWithdrawalNftsAmountLocked;
        totalSupport = (totalStakedEthLocked * 10 ** 18) / stEthTotalSupply;
        rageQuitSupport =
            (totalRageQuitStEthLocked * 10 ** 18) /
            stEthTotalSupply;
    }

    function startRageQuitAccumulation() external {
        if (msg.sender != _govState) {
            revert Unauthorized();
        }
        if (_state != State.Signalling) {
            revert InvalidState();
        }
        _state = State.RageQuitAccumulation;
        emit RageQuitAccumulationStarted();
    }

    function startRageQuit() external {
        if (msg.sender != _govState) {
            revert Unauthorized();
        }
        if (_state != State.RageQuitAccumulation) {
            revert InvalidState();
        }

        assert(_rageQuitWstEthAmountTotal == 0);
        assert(_rageQuitWstEthAmountRequested == 0);
        assert(_lastWithdrawalRequestId == 0);

        _state = State.RageQuit;

        uint256 stEthBalance = IERC20(ST_ETH).balanceOf(address(this));
        if (stEthBalance != 0) {
            IERC20(ST_ETH).approve(WST_ETH, stEthBalance);
            IWstETH(WST_ETH).wrap(stEthBalance);
        }

        _rageQuitWstEthAmountTotal = IERC20(WST_ETH).balanceOf(address(this));

        IERC20(WST_ETH).approve(WITHDRAWAL_QUEUE, type(uint256).max);

        emit RageQuitStarted();
    }

    function requestNextWithdrawalsBatch(
        uint256 maxNumRequests
    ) external returns (uint256, uint256, uint256) {
        if (_state != State.RageQuit) {
            revert InvalidState();
        }

        uint256 maxStRequestAmount = IWithdrawalQueue(WITHDRAWAL_QUEUE)
            .MAX_STETH_WITHDRAWAL_AMOUNT();
        uint256 maxWstRequestAmount = IStETH(ST_ETH).getSharesByPooledEth(
            maxStRequestAmount
        );

        uint256 total = _rageQuitWstEthAmountTotal;
        uint256 requested = _rageQuitWstEthAmountRequested;

        if (requested >= total) {
            revert NoUnrequestedWithdrawalsLeft();
        }

        uint256 remainder = total - requested;
        uint256 numFullRequests = remainder / maxWstRequestAmount;

        if (numFullRequests > maxNumRequests) {
            numFullRequests = maxNumRequests;
        }

        requested += maxWstRequestAmount * numFullRequests;
        remainder = total - requested;

        uint256[] memory amounts;

        if (
            numFullRequests < maxNumRequests && remainder < maxWstRequestAmount
        ) {
            amounts = new uint256[](numFullRequests + 1);
            amounts[numFullRequests] = remainder;
            requested += remainder;
            remainder = 0;
        } else {
            amounts = new uint256[](numFullRequests);
        }

        assert(requested <= total);
        assert(amounts.length > 0);

        for (uint256 i = 0; i < numFullRequests; ++i) {
            amounts[i] = maxWstRequestAmount;
        }

        _rageQuitWstEthAmountRequested = requested;

        uint256[] memory reqIds = IWithdrawalQueue(WITHDRAWAL_QUEUE)
            .requestWithdrawalsWstETH(amounts, address(this));

        uint256 lastRequestId = reqIds[reqIds.length - 1];
        _lastWithdrawalRequestId = lastRequestId;

        emit WithdrawalsBatchRequested(reqIds[0], lastRequestId, remainder);
        return (reqIds[0], lastRequestId, remainder);
    }

    function isRageQuitFinalized() external view returns (bool) {
        return
            _state == State.RageQuit &&
            _rageQuitWstEthAmountRequested == _rageQuitWstEthAmountTotal &&
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastFinalizedRequestId() >=
            _lastWithdrawalRequestId;
    }

    function claimNextETHBatch(
        uint256[] calldata requestIds,
        uint256[] calldata hints
    ) external {
        if (_state == State.Signalling) {
            revert InvalidState();
        }

        IWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawals(requestIds, hints);
        if (IWithdrawalQueue(WITHDRAWAL_QUEUE).balanceOf(address(this)) == 0) {
            _totalNonNFTEthToShare =
                address(this).balance -
                _totalWithdrawalNftsAmountLocked;
        }

        WithdrawalRequestStatus[] memory wqRequestStatuses = IWithdrawalQueue(
            WITHDRAWAL_QUEUE
        ).getWithdrawalStatus(requestIds);

        for (uint256 i = 0; i < requestIds.length; i++) {
            uint256 id = requestIds[i];
            if (
                wqRequests[id].owner != address(0) &&
                wqRequests[id].amountOfStETH !=
                wqRequestStatuses[i].amountOfStETH
            ) {
                _wqRequestsBalances[wqRequests[id].owner] =
                    _wqRequestsBalances[wqRequests[id].owner] -
                    wqRequests[id].amountOfStETH +
                    wqRequestStatuses[i].amountOfStETH;
                _totalWithdrawalNftsAmountLocked =
                    _totalWithdrawalNftsAmountLocked -
                    wqRequests[id].amountOfStETH +
                    wqRequestStatuses[i].amountOfStETH;
            }
        }

        IWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawals(requestIds, hints);
    }

    function _activateNextGovernanceState() internal {
        GovernanceState(_govState).activateNextState();
    }
}
