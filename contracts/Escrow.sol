// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Configuration} from "./Configuration.sol";
import {GovernanceState} from "./GovernanceState.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IStETH {
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
}

interface IWstETH {
    function wrap(uint256 stETHAmount) external returns (uint256);
}

interface IWithdrawalQueue {
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);
    function requestWithdrawalsWstETH(uint256[] calldata amounts, address owner) external returns (uint256[] memory);
    function claimWithdrawalsTo(uint256[] calldata requestIds, uint256[] calldata hints, address recipient) external;
    function getLastFinalizedRequestId() external view returns (uint256);
}

/**
 * A contract serving as a veto signalling and rage quit escrow.
 */
contract Escrow {
    error Unauthorized();
    error InvalidState();
    error NoUnrequestedWithdrawalsLeft();

    event RageQuitAccumulationStarted();
    event RageQuitStarted();
    event WithdrawalsBatchRequested(
        uint256 indexed firstRequestId, uint256 indexed lastRequestId, uint256 wstEthLeftToRequest
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

    uint256 internal _totalStEthLocked;
    uint256 internal _totalWstEthLocked;

    uint256 internal _rageQuitWstEthAmountTotal;
    uint256 internal _rageQuitWstEthAmountRequested;
    uint256 internal _lastWithdrawalRequestId;

    constructor(address config, address stEth, address wstEth, address withdrawalQueue) {
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

    // FIXME remove after locking/unlocking is implemented
    function mock__lockStEth(uint256 amount) external {
        _totalStEthLocked += amount;
        _activateNextGovernanceState();
    }

    // FIXME remove after locking/unlocking is implemented
    function mock__unlockStEth(uint256 amount) external {
        _totalStEthLocked -= amount;
        _activateNextGovernanceState();
    }

    function lockStEth() external {
        // TODO: transferFrom caller, record caller's new total amount
        // TODO: only allow in Signalling and RageQuitAccumulation
        _activateNextGovernanceState();
    }

    function lockWstEth() external {
        // TODO: transferFrom caller, record caller's new total amount
        // TODO: only allow in Signalling and RageQuitAccumulation
        _activateNextGovernanceState();
    }

    function initiateStEthWithdrawal() external {
        // TODO: convert locked stETH to locked withdrawal NFTs
        // TODO: only allow in Signalling
        _activateNextGovernanceState();
    }

    function unlockStEth() external {
        // TODO: only allow in Signalling
        _activateNextGovernanceState();
    }

    function unlockWstEth() external {
        // TODO: only allow in Signalling
        _activateNextGovernanceState();
    }

    function lockWithdrawalNFT() external {
        // TODO: only allow in Signalling and RageQuitAccumulation
        _activateNextGovernanceState();
    }

    function unlockWithdrawalNFT() external {
        // TODO: only allow in Signalling
        _activateNextGovernanceState();
    }

    function claimETH() external {
        // TODO: only allow in RageQuit
        // TODO: only allow if all withdrawal requests are claimed from WQ
    }

    ///
    /// State transitions
    ///

    function totalStEthLocked() external returns (uint256) {
        return _totalStEthLocked;
    }

    function totalWstEthLocked() external returns (uint256) {
        return _totalWstEthLocked;
    }

    function getSignallingState() external view returns (uint256 totalSupport, uint256 rageQuitSupport) {
        uint256 stEthTotalSupply = IERC20(ST_ETH).totalSupply();
        uint256 wstEthLockedAsStEth = IStETH(ST_ETH).getPooledEthByShares(_totalWstEthLocked);
        // TODO: include locked NFTs underlying stETH balance
        uint256 totalStakedEthLocked = _totalStEthLocked + wstEthLockedAsStEth;
        totalSupport = totalStakedEthLocked * 10 ** 18 / stEthTotalSupply;
        // TODO: rageQuitSupport = totalSupport but not not counting withdrawal NFTs
        rageQuitSupport = totalSupport;
        return (totalSupport, rageQuitSupport);
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

    function requestNextWithdrawalsBatch(uint256 maxNumRequests) external returns (uint256, uint256, uint256) {
        if (_state != State.RageQuit) {
            revert InvalidState();
        }

        uint256 maxStRequestAmount = IWithdrawalQueue(WITHDRAWAL_QUEUE).MAX_STETH_WITHDRAWAL_AMOUNT();
        uint256 maxWstRequestAmount = IStETH(ST_ETH).getSharesByPooledEth(maxStRequestAmount);

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

        if (numFullRequests < maxNumRequests && remainder < maxWstRequestAmount) {
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

        uint256[] memory reqIds = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawalsWstETH(amounts, address(this));

        uint256 lastRequestId = reqIds[reqIds.length - 1];
        _lastWithdrawalRequestId = lastRequestId;

        emit WithdrawalsBatchRequested(reqIds[0], lastRequestId, remainder);
        return (reqIds[0], lastRequestId, remainder);
    }

    function isRageQuitFinalized() external view returns (bool) {
        return _state == State.RageQuit && _rageQuitWstEthAmountRequested == _rageQuitWstEthAmountTotal
            && IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastFinalizedRequestId() >= _lastWithdrawalRequestId;
    }

    function claimNextETHBatch(uint256[] calldata requestIds, uint256[] calldata hints) external {
        // TODO: check that all requests are claimed
        IWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawalsTo(requestIds, hints, address(this));
    }

    function _activateNextGovernanceState() internal {
        GovernanceState(_govState).activateNextState();
    }
}
