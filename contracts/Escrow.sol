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

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);
}

interface IStETH {
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);

    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);

    function transferShares(address to, uint256 amount) external;
}

interface IWstETH {
    function wrap(uint256 stETHAmount) external returns (uint256);

    function unwrap(uint256 wstETHAmount) external returns (uint256);
}

interface IWithdrawalQueue {
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    function requestWithdrawalsWstETH(uint256[] calldata amounts, address owner) external returns (uint256[] memory);

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external;

    function getLastFinalizedRequestId() external view returns (uint256);

    function transferFrom(address from, address to, uint256 requestId) external;

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);

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
    error FinalizedRequest(uint256);
    error RequestNotFound(uint256 id);
    error SenderIsNotAllowed();
    error RequestIsNotFromBatch(uint256 id);
    error RequestFromBatch(uint256 id);

    event RageQuitStarted();
    event WithdrawalsBatchRequested(
        uint256 indexed firstRequestId, uint256 indexed lastRequestId, uint256 stEthLeftToRequest
    );

    enum State {
        Signalling,
        RageQuit
    }

    struct HolderState {
        uint256 stEthInEthShares;
        uint256 wstEthInEthShares;
        uint256 wqRequestsBalance;
        uint256 finalizedWqRequestsBalance;
        uint256 eth;
        uint256[] wqRequestIds;
    }

    struct WithdrawalRequest {
        uint256 stEthInEthShares;
        uint256 wstEthInEthShares;
        uint256 wqRequestsBalance;
        uint256 finalizedWqRequestsBalance;
    }

    struct Balance {
        uint256 stEth;
        uint256 wstEth;
        uint256 wqRequestsBalance;
        uint256 finalizedWqRequestsBalance;
        uint256 eth;
        uint256[] wqRequestIds;
    }

    Configuration internal immutable CONFIG;
    address internal immutable ST_ETH;
    address internal immutable WST_ETH;
    address internal immutable WITHDRAWAL_QUEUE;
    address internal immutable BURNER_VAULT;

    address internal _govState;
    State internal _state;

    uint256 internal _totalStEthInEthLocked;
    uint256 internal _totalWstEthInEthLocked;
    uint256 internal _totalWithdrawalNftsAmountLocked;
    uint256 internal _totalFinalizedWithdrawalNftsAmountLocked;
    uint256 internal _totalClaimedEthLocked;

    uint256 internal _totalEscrowShares;
    uint256 internal _claimedWQRequestsAmount;

    uint256 internal _rageQuitAmountTotal;
    uint256 internal _rageQuitAmountRequested;
    uint256 internal _lastWithdrawalRequestId;

    mapping(address => HolderState) private _balances;
    mapping(uint256 => WithdrawalRequestStatus) private _wqRequests;

    constructor(address config, address stEth, address wstEth, address withdrawalQueue, address burnerVault) {
        CONFIG = Configuration(config);
        ST_ETH = stEth;
        WST_ETH = wstEth;
        WITHDRAWAL_QUEUE = withdrawalQueue;
        BURNER_VAULT = burnerVault;

        _govState = address(this);
    }

    function initialize(address governanceState) external {
        if (_govState != address(0)) {
            revert Unauthorized();
        }
        _totalStEthInEthLocked = 1;
        _totalEscrowShares = 1;
        _govState = governanceState;
    }

    ///
    /// Staker interface
    ///
    function balanceOf(address holder) public view returns (Balance memory balance) {
        HolderState memory state = _balances[holder];

        balance.stEth = _getETHByShares(state.stEthInEthShares);
        balance.wstEth = IStETH(ST_ETH).getSharesByPooledEth(_getETHByShares(state.wstEthInEthShares));
        balance.wqRequestsBalance = state.wqRequestsBalance;
        balance.finalizedWqRequestsBalance = state.finalizedWqRequestsBalance;
        balance.eth = state.eth;
        balance.wqRequestIds = state.wqRequestIds;
    }

    function lockStEth(uint256 amount) external {
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        IERC20(ST_ETH).transferFrom(msg.sender, address(this), amount);

        uint256 shares = _getSharesByETH(amount);

        _balances[msg.sender].stEthInEthShares += shares;
        _totalEscrowShares += shares;
        _totalStEthInEthLocked += amount;

        _activateNextGovernanceState();
    }

    function lockWstEth(uint256 amount) external {
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        IERC20(WST_ETH).transferFrom(msg.sender, address(this), amount);

        uint256 amountInEth = IStETH(ST_ETH).getPooledEthByShares(amount);
        uint256 shares = _getSharesByETH(amountInEth);

        _balances[msg.sender].wstEthInEthShares = shares;
        _totalEscrowShares += shares;
        _totalWstEthInEthLocked += amountInEth;

        _activateNextGovernanceState();
    }

    function lockWithdrawalNFT(uint256[] memory ids) external {
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        WithdrawalRequestStatus[] memory wqRequestStatuses = IWithdrawalQueue(WITHDRAWAL_QUEUE).getWithdrawalStatus(ids);

        uint256 wqRequestsAmount = 0;
        address sender = msg.sender;

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            if (wqRequestStatuses[i].isFinalized == true) {
                revert FinalizedRequest(id);
            }

            IWithdrawalQueue(WITHDRAWAL_QUEUE).transferFrom(sender, address(this), id);
            _wqRequests[id] = wqRequestStatuses[i];
            wqRequestsAmount += wqRequestStatuses[i].amountOfStETH;
            _balances[sender].wqRequestIds.push(ids[i]);
        }

        _balances[sender].wqRequestsBalance += wqRequestsAmount;
        _totalWithdrawalNftsAmountLocked += wqRequestsAmount;

        _activateNextGovernanceState();
    }

    function unlockStEth() external {
        _activateNextGovernanceState();
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        burnRewards();

        address sender = msg.sender;
        uint256 escrowShares = _balances[sender].stEthInEthShares;
        uint256 amount = _getETHByShares(escrowShares);

        IERC20(ST_ETH).transfer(sender, amount);

        _balances[sender].stEthInEthShares = 0;
        _totalEscrowShares -= escrowShares;
        _totalStEthInEthLocked -= amount;

        _activateNextGovernanceState();
    }

    function unlockWstEth() external {
        _activateNextGovernanceState();
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        burnRewards();

        address sender = msg.sender;
        uint256 escrowShares = _balances[sender].wstEthInEthShares;
        uint256 amount = _getETHByShares(escrowShares);
        uint256 amountInShares = IStETH(ST_ETH).getSharesByPooledEth(amount);

        IERC20(WST_ETH).transfer(sender, amountInShares);

        _balances[sender].wstEthInEthShares = 0;
        _totalEscrowShares -= escrowShares;
        _totalWstEthInEthLocked -= amount;

        _activateNextGovernanceState();
    }

    function unlockWithdrawalNFT(uint256[] memory ids) external {
        _activateNextGovernanceState();
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        WithdrawalRequestStatus[] memory wqRequestStatuses = IWithdrawalQueue(WITHDRAWAL_QUEUE).getWithdrawalStatus(ids);

        uint256 wqRequestsAmount = 0;
        uint256 finalizedWqRequestsAmount = 0;
        address sender = msg.sender;

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            if (_wqRequests[ids[i]].owner != sender) {
                revert SenderIsNotOwner(id);
            }
            IWithdrawalQueue(WITHDRAWAL_QUEUE).transferFrom(address(this), sender, id);
            _wqRequests[id].owner = address(0);
            if (_wqRequests[id].isFinalized == true) {
                finalizedWqRequestsAmount += wqRequestStatuses[i].amountOfStETH;
            } else {
                wqRequestsAmount += wqRequestStatuses[i].amountOfStETH;
            }
        }

        _balances[sender].wqRequestsBalance -= wqRequestsAmount;
        _balances[sender].finalizedWqRequestsBalance -= finalizedWqRequestsAmount;
        _totalWithdrawalNftsAmountLocked -= wqRequestsAmount;
        _totalFinalizedWithdrawalNftsAmountLocked -= finalizedWqRequestsAmount;

        _activateNextGovernanceState();
    }

    function unlockEth() public {
        _activateNextGovernanceState();
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        address sender = msg.sender;
        uint256 ethToUnlock = _balances[sender].eth;

        if (ethToUnlock > 0) {
            _balances[sender].eth = 0;
            _totalClaimedEthLocked -= ethToUnlock;
            IERC20(WST_ETH).transfer(sender, ethToUnlock);

            _activateNextGovernanceState();
        }
    }

    function claimETH() external {
        if (_state != State.RageQuit) {
            revert InvalidState();
        }

        if (_claimedWQRequestsAmount < _rageQuitAmountTotal) {
            revert NotClaimedWQRequests();
        }

        address sender = msg.sender;
        HolderState memory state = _balances[sender];

        uint256 ethToClaim = _getETHByShares(state.stEthInEthShares);
        ethToClaim += _getETHByShares(state.wstEthInEthShares);
        ethToClaim += _balances[sender].eth;

        _balances[sender].stEthInEthShares = 0;
        _balances[sender].wstEthInEthShares = 0;
        _balances[sender].eth = 0;

        if (ethToClaim > 0) {
            payable(sender).transfer(ethToClaim);
        }
    }

    ///
    /// State transitions
    ///

    function burnRewards() public {
        uint256 minRewardsAmount = 1e9;
        uint256 wstEthLocked = IStETH(ST_ETH).getSharesByPooledEth(_totalWstEthInEthLocked);
        uint256 wstEthBalance = IERC20(WST_ETH).balanceOf(address(this));

        uint256 stEthBalance = IERC20(ST_ETH).balanceOf(address(this));

        if (wstEthLocked + minRewardsAmount < wstEthBalance) {
            uint256 wstEthRewards = wstEthBalance - wstEthLocked;
            IWstETH(WST_ETH).unwrap(wstEthRewards);
        }
        if (wstEthLocked > wstEthBalance) {
            _totalWstEthInEthLocked = IStETH(ST_ETH).getPooledEthByShares(wstEthBalance);
        }

        uint256 stEthRewards = 0;

        if (_totalStEthInEthLocked < stEthBalance) {
            stEthBalance = IERC20(ST_ETH).balanceOf(address(this));
            stEthRewards = stEthBalance - _totalStEthInEthLocked;
            IERC20(ST_ETH).transfer(BURNER_VAULT, stEthRewards);
        } else {
            _totalStEthInEthLocked = stEthBalance;
        }
    }

    function checkForFinalization(uint256[] memory ids) public {
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        WithdrawalRequestStatus[] memory wqRequestStatuses = IWithdrawalQueue(WITHDRAWAL_QUEUE).getWithdrawalStatus(ids);

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            address requestOwner = _wqRequests[ids[i]].owner;

            if (requestOwner == address(0)) {
                revert RequestNotFound(id);
            }

            if (_wqRequests[id].isFinalized == false && wqRequestStatuses[i].isFinalized == true) {
                _totalWithdrawalNftsAmountLocked -= _wqRequests[id].amountOfStETH;
                _totalFinalizedWithdrawalNftsAmountLocked += wqRequestStatuses[i].amountOfStETH;
                _balances[requestOwner].wqRequestsBalance -= _wqRequests[id].amountOfStETH;
                _balances[requestOwner].finalizedWqRequestsBalance += wqRequestStatuses[i].amountOfStETH;

                _wqRequests[id].amountOfStETH = wqRequestStatuses[i].amountOfStETH;
                _wqRequests[id].isFinalized = true;
            }
        }
    }

    function getSignallingState() external view returns (uint256 totalSupport, uint256 rageQuitSupport) {
        uint256 stEthTotalSupply = IERC20(ST_ETH).totalSupply();

        uint256 totalRageQuitStEthLocked =
            _totalStEthInEthLocked + _totalWstEthInEthLocked + _totalWithdrawalNftsAmountLocked;
        rageQuitSupport = (totalRageQuitStEthLocked * 10 ** 18) / stEthTotalSupply;

        uint256 totalStakedEthLocked =
            totalRageQuitStEthLocked + _totalFinalizedWithdrawalNftsAmountLocked + _totalClaimedEthLocked;
        totalSupport = (totalStakedEthLocked * 10 ** 18) / stEthTotalSupply;
    }

    function startRageQuit() external {
        if (msg.sender != _govState) {
            revert Unauthorized();
        }
        if (_state != State.Signalling) {
            revert InvalidState();
        }

        burnRewards();

        assert(_rageQuitAmountRequested == 0);
        assert(_lastWithdrawalRequestId == 0);

        _rageQuitAmountTotal = _totalStEthInEthLocked + _totalWstEthInEthLocked;

        _state = State.RageQuit;

        uint256 wstEthBalance = IERC20(WST_ETH).balanceOf(address(this));
        if (wstEthBalance != 0) {
            IWstETH(WST_ETH).unwrap(wstEthBalance);
        }

        IERC20(ST_ETH).approve(WITHDRAWAL_QUEUE, type(uint256).max);

        emit RageQuitStarted();
    }

    function requestNextWithdrawalsBatch(uint256 maxNumRequests) external returns (uint256, uint256, uint256) {
        if (_state != State.RageQuit) {
            revert InvalidState();
        }

        uint256 maxStRequestAmount = IWithdrawalQueue(WITHDRAWAL_QUEUE).MAX_STETH_WITHDRAWAL_AMOUNT();

        uint256 total = _rageQuitAmountTotal;
        uint256 requested = _rageQuitAmountRequested;

        if (requested >= total) {
            revert NoUnrequestedWithdrawalsLeft();
        }

        uint256 remainder = total - requested;
        uint256 numFullRequests = remainder / maxStRequestAmount;

        if (numFullRequests > maxNumRequests) {
            numFullRequests = maxNumRequests;
        }

        requested += maxStRequestAmount * numFullRequests;
        remainder = total - requested;

        uint256[] memory amounts;

        if (numFullRequests < maxNumRequests && remainder < maxStRequestAmount) {
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
            amounts[i] = maxStRequestAmount;
        }

        _rageQuitAmountRequested = requested;

        uint256[] memory reqIds = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, address(this));

        WithdrawalRequestStatus[] memory wqRequestStatuses =
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getWithdrawalStatus(reqIds);

        for (uint256 i = 0; i < reqIds.length; ++i) {
            _wqRequests[reqIds[i]] = wqRequestStatuses[i];
        }

        uint256 lastRequestId = reqIds[reqIds.length - 1];
        _lastWithdrawalRequestId = lastRequestId;

        emit WithdrawalsBatchRequested(reqIds[0], lastRequestId, remainder);
        return (reqIds[0], lastRequestId, remainder);
    }

    function isRageQuitFinalized() external view returns (bool) {
        return _state == State.RageQuit && _rageQuitAmountRequested == _rageQuitAmountTotal
            && IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastFinalizedRequestId() >= _lastWithdrawalRequestId;
    }

    function claimNextETHBatch(uint256[] calldata requestIds, uint256[] calldata hints) external {
        if (_state != State.RageQuit) {
            revert InvalidState();
        }

        IWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawals(requestIds, hints);

        WithdrawalRequestStatus[] memory wqRequestStatuses =
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getWithdrawalStatus(requestIds);

        for (uint256 i = 0; i < requestIds.length; ++i) {
            uint256 id = requestIds[i];
            address owner = _wqRequests[id].owner;

            if (owner != address(this)) {
                revert RequestIsNotFromBatch(id);
            }
            _claimedWQRequestsAmount += wqRequestStatuses[i].amountOfStETH;

            for (uint256 idx = 0; i < _balances[owner].wqRequestIds.length; i++) {
                if (_balances[owner].wqRequestIds[idx] == requestIds[i]) {
                    _balances[owner].wqRequestIds[idx] =
                        _balances[owner].wqRequestIds[_balances[owner].wqRequestIds.length - 1];
                    _balances[owner].wqRequestIds.pop();
                    break;
                }
            }
        }
    }

    function claimWithdrawalRequests(uint256[] calldata requestIds, uint256[] calldata hints) external {
        IWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawals(requestIds, hints);

        WithdrawalRequestStatus[] memory wqRequestStatuses =
            IWithdrawalQueue(WITHDRAWAL_QUEUE).getWithdrawalStatus(requestIds);

        for (uint256 i = 0; i < requestIds.length; ++i) {
            uint256 id = requestIds[i];
            WithdrawalRequestStatus memory request = _wqRequests[id];
            address owner = request.owner;

            if (owner == address(this) || owner == address(0)) {
                revert RequestFromBatch(id);
            }

            if (request.isFinalized) {
                _balances[owner].finalizedWqRequestsBalance -= request.amountOfStETH;
                _totalFinalizedWithdrawalNftsAmountLocked -= request.amountOfStETH;
            } else {
                _balances[owner].wqRequestsBalance -= request.amountOfStETH;
                _totalWithdrawalNftsAmountLocked -= request.amountOfStETH;
            }
            _balances[owner].eth += wqRequestStatuses[i].amountOfStETH;
            _totalClaimedEthLocked += wqRequestStatuses[i].amountOfStETH;

            for (uint256 idx = 0; i < _balances[owner].wqRequestIds.length; i++) {
                if (_balances[owner].wqRequestIds[idx] == requestIds[i]) {
                    _balances[owner].wqRequestIds[idx] =
                        _balances[owner].wqRequestIds[_balances[owner].wqRequestIds.length - 1];
                    _balances[owner].wqRequestIds.pop();
                    break;
                }
            }
        }
    }

    receive() external payable {
        if (msg.sender != WITHDRAWAL_QUEUE) {
            revert SenderIsNotAllowed();
        }
    }

    function _activateNextGovernanceState() internal {
        GovernanceState(_govState).activateNextState();
    }

    function _getSharesByETH(uint256 eth) internal view returns (uint256 shares) {
        uint256 totalEthLocked = _totalStEthInEthLocked + _totalWstEthInEthLocked;

        shares = eth * _totalEscrowShares / totalEthLocked;
    }

    function _getETHByShares(uint256 shares) internal view returns (uint256 eth) {
        uint256 totalEthLocked = _totalStEthInEthLocked + _totalWstEthInEthLocked;

        eth = shares * totalEthLocked / _totalEscrowShares;
    }
}
