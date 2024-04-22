// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IEscrow} from "./interfaces/IEscrow.sol";
import {IConfiguration} from "./interfaces/IConfiguration.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IWithdrawalQueue, WithdrawalRequestStatus} from "./interfaces/IWithdrawalQueue.sol";

import {AssetsAccounting, LockedAssetsStats, LockedAssetsTotals} from "./libraries/AssetsAccounting.sol";

import {ArrayUtils} from "./utils/arrays.sol";

interface IDualGovernance {
    function activateNextState() external;
}

enum EscrowState {
    NotInitialized,
    SignallingEscrow,
    RageQuitEscrow
}

struct VetoerState {
    uint256 stETHShares;
    uint256 wstETHShares;
    uint256 unstETHShares;
}

contract Escrow is IEscrow {
    using AssetsAccounting for AssetsAccounting.State;

    error EmptyBatch();
    error ZeroWithdraw();
    error WithdrawalsTimelockNotPassed();
    error InvalidETHSender(address actual, address expected);
    error NotDualGovernance(address actual, address expected);
    error InvalidNextBatch(uint256 actualRequestId, uint256 expectedRequestId);
    error MasterCopyCallForbidden();
    error InvalidState(EscrowState actual, EscrowState expected);
    error RageQuitExtraTimelockNotStarted();

    uint256 public immutable RAGE_QUIT_TIMELOCK = 30 days;
    address public immutable MASTER_COPY;

    IStETH public immutable ST_ETH;
    IWstETH public immutable WST_ETH;
    IWithdrawalQueue public immutable WITHDRAWAL_QUEUE;

    IConfiguration public immutable CONFIG;

    EscrowState internal _escrowState;
    IDualGovernance private _dualGovernance;
    AssetsAccounting.State private _accounting;

    uint256[] internal _withdrawalUnstETHIds;

    uint256 internal _rageQuitExtraTimelock;
    uint256 internal _rageQuitWithdrawalsTimelock;
    uint256 internal _rageQuitTimelockStartedAt;

    constructor(address stETH, address wstETH, address withdrawalQueue, address config) {
        ST_ETH = IStETH(stETH);
        WST_ETH = IWstETH(wstETH);
        WITHDRAWAL_QUEUE = IWithdrawalQueue(withdrawalQueue);
        MASTER_COPY = address(this);
        CONFIG = IConfiguration(config);
    }

    function initialize(address dualGovernance) external {
        if (address(this) == MASTER_COPY) {
            revert MasterCopyCallForbidden();
        }
        _checkEscrowState(EscrowState.NotInitialized);

        _escrowState = EscrowState.SignallingEscrow;
        _dualGovernance = IDualGovernance(dualGovernance);

        ST_ETH.approve(address(WITHDRAWAL_QUEUE), type(uint256).max);
        WST_ETH.approve(address(WITHDRAWAL_QUEUE), type(uint256).max);
    }

    // ---
    // Lock & Unlock stETH
    // ---

    function lockStETH(uint256 amount) external {
        uint256 shares = ST_ETH.getSharesByPooledEth(amount);
        _accounting.accountStETHLock(msg.sender, shares);
        ST_ETH.transferSharesFrom(msg.sender, address(this), shares);
        _activateNextGovernanceState();
    }

    function unlockStETH() external {
        _accounting.checkAssetsUnlockDelayPassed(msg.sender, CONFIG.SIGNALLING_ESCROW_MIN_LOCK_TIME());
        uint256 sharesUnlocked = _accounting.accountStETHUnlock(msg.sender);
        ST_ETH.transferShares(msg.sender, sharesUnlocked);
        _activateNextGovernanceState();
    }

    function requestWithdrawalsStETH(uint256[] calldata amounts) external returns (uint256[] memory unstETHIds) {
        unstETHIds = WITHDRAWAL_QUEUE.requestWithdrawals(amounts, address(this));
        WithdrawalRequestStatus[] memory statuses = WITHDRAWAL_QUEUE.getWithdrawalStatus(unstETHIds);

        uint256 sharesTotal = 0;
        for (uint256 i = 0; i < statuses.length; ++i) {
            sharesTotal += statuses[i].amountOfShares;
        }
        _accounting.accountStETHUnlock(msg.sender, sharesTotal);
        _accounting.accountUnstETHLock(msg.sender, unstETHIds, statuses);
    }

    // ---
    // Lock / Unlock wstETH
    // ---

    function lockWstETH(uint256 amount) external {
        _accounting.accountWstETHLock(msg.sender, amount);
        WST_ETH.transferFrom(msg.sender, address(this), amount);
        _activateNextGovernanceState();
    }

    function unlockWstETH() external returns (uint256 wstETHUnlocked) {
        _accounting.checkAssetsUnlockDelayPassed(msg.sender, CONFIG.SIGNALLING_ESCROW_MIN_LOCK_TIME());
        wstETHUnlocked = _accounting.accountWstETHUnlock(msg.sender);
        WST_ETH.transfer(msg.sender, wstETHUnlocked);
        _activateNextGovernanceState();
    }

    function requestWithdrawalsWstETH(uint256[] calldata amounts) external returns (uint256[] memory unstETHIds) {
        uint256 totalAmount = ArrayUtils.sum(amounts);
        _accounting.accountWstETHUnlock(msg.sender, totalAmount);
        unstETHIds = WITHDRAWAL_QUEUE.requestWithdrawalsWstETH(amounts, address(this));
        _accounting.accountUnstETHLock(msg.sender, unstETHIds, WITHDRAWAL_QUEUE.getWithdrawalStatus(unstETHIds));
    }

    // ---
    // Lock / Unlock unstETH
    // ---
    function lockUnstETH(uint256[] memory unstETHIds) external {
        WithdrawalRequestStatus[] memory statuses = WITHDRAWAL_QUEUE.getWithdrawalStatus(unstETHIds);
        _accounting.accountUnstETHLock(msg.sender, unstETHIds, statuses);

        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            WITHDRAWAL_QUEUE.transferFrom(msg.sender, address(this), unstETHIds[i]);
        }
    }

    function unlockUnstETH(uint256[] memory unstETHIds) external {
        _accounting.accountUnstETHUnlock(CONFIG.SIGNALLING_ESCROW_MIN_LOCK_TIME(), msg.sender, unstETHIds);
        uint256 unstETHIdsCount = unstETHIds.length;
        for (uint256 i = 0; i < unstETHIdsCount; ++i) {
            WITHDRAWAL_QUEUE.transferFrom(address(this), msg.sender, unstETHIds[i]);
        }
    }

    function markUnstETHFinalized(uint256[] memory unstETHIds, uint256[] calldata hints) external {
        _checkEscrowState(EscrowState.SignallingEscrow);

        uint256[] memory claimableAmounts = WITHDRAWAL_QUEUE.getClaimableEther(unstETHIds, hints);
        _accounting.accountUnstETHFinalized(unstETHIds, claimableAmounts);
    }

    // ---
    // State Updates
    // ---

    function startRageQuit(uint256 rageQuitExtraTimelock, uint256 rageQuitWithdrawalsTimelock) external {
        _checkDualGovernance(msg.sender);
        _checkEscrowState(EscrowState.SignallingEscrow);

        _escrowState = EscrowState.RageQuitEscrow;
        _rageQuitExtraTimelock = rageQuitExtraTimelock;
        _rageQuitWithdrawalsTimelock = rageQuitWithdrawalsTimelock;

        uint256 wstETHBalance = WST_ETH.balanceOf(address(this));
        if (wstETHBalance > 0) {
            WST_ETH.unwrap(wstETHBalance);
        }
        ST_ETH.approve(address(WITHDRAWAL_QUEUE), type(uint256).max);
    }

    function requestNextWithdrawalsBatch(uint256 maxWithdrawalRequestsCount) external {
        _checkEscrowState(EscrowState.RageQuitEscrow);

        uint256[] memory requestAmounts = _accounting.formWithdrawalBatch(
            WITHDRAWAL_QUEUE.MIN_STETH_WITHDRAWAL_AMOUNT(),
            WITHDRAWAL_QUEUE.MAX_STETH_WITHDRAWAL_AMOUNT(),
            ST_ETH.balanceOf(address(this)),
            maxWithdrawalRequestsCount
        );
        uint256[] memory unstETHIds = WITHDRAWAL_QUEUE.requestWithdrawals(requestAmounts, address(this));
        _accounting.accountWithdrawalBatch(unstETHIds);
    }

    function claimNextWithdrawalsBatch(uint256 offset, uint256[] calldata hints) external {
        _checkEscrowState(EscrowState.RageQuitEscrow);
        uint256[] memory unstETHIds = _accounting.accountWithdrawalBatchClaimed(offset, hints.length);

        if (unstETHIds.length > 0) {
            uint256 ethBalanceBefore = address(this).balance;
            WITHDRAWAL_QUEUE.claimWithdrawals(unstETHIds, hints);
            uint256 ethAmountClaimed = address(this).balance - ethBalanceBefore;

            _accounting.accountClaimedETH(ethAmountClaimed);
        }
        if (_accounting.getIsWithdrawalsClaimed()) {
            _rageQuitTimelockStartedAt = block.timestamp;
        }
    }

    function claimWithdrawalRequests(uint256[] calldata unstETHIds, uint256[] calldata hints) external {
        _checkEscrowState(EscrowState.RageQuitEscrow);
        uint256[] memory claimableAmounts = WITHDRAWAL_QUEUE.getClaimableEther(unstETHIds, hints);

        uint256 ethBalanceBefore = address(this).balance;
        WITHDRAWAL_QUEUE.claimWithdrawals(unstETHIds, hints);
        uint256 ethBalanceAfter = address(this).balance;

        uint256 totalAmountClaimed = _accounting.accountUnstETHClaimed(unstETHIds, claimableAmounts);
        assert(totalAmountClaimed == ethBalanceAfter - ethBalanceBefore);
    }

    // ---
    // Withdraw Logic
    // ---

    function withdrawStETHAsETH() external {
        _checkEscrowState(EscrowState.RageQuitEscrow);
        _checkWithdrawalsTimelockPassed();
        Address.sendValue(payable(msg.sender), _accounting.accountStETHWithdraw(msg.sender));
    }

    function withdrawWstETH() external {
        _checkEscrowState(EscrowState.RageQuitEscrow);
        _checkWithdrawalsTimelockPassed();
        Address.sendValue(payable(msg.sender), _accounting.accountWstETHWithdraw(msg.sender));
    }

    function withdrawUnstETHAsETH(uint256[] calldata unstETHIds) external {
        _checkEscrowState(EscrowState.RageQuitEscrow);
        _checkWithdrawalsTimelockPassed();
        Address.sendValue(payable(msg.sender), _accounting.accountUnstETHWithdraw(msg.sender, unstETHIds));
    }

    // ---
    // Getters
    // ---

    function getLockedAssetsTotals() external view returns (LockedAssetsTotals memory totals) {
        totals = _accounting.totals;
    }

    function getVetoerState(address vetoer) external view returns (VetoerState memory vetoerState) {
        LockedAssetsStats memory stats = _accounting.assets[vetoer];
        vetoerState.stETHShares = stats.stETHShares;
        vetoerState.wstETHShares = stats.wstETHShares;
        vetoerState.unstETHShares = stats.unstETHShares;
    }

    function getNextWithdrawalBatches(uint256 limit)
        external
        view
        returns (uint256 offset, uint256 total, uint256[] memory unstETHIds)
    {
        offset = _accounting.claimedBatchesCount;
        total = _accounting.withdrawalBatchIds.length;
        if (total == offset) {
            return (offset, total, unstETHIds);
        }
        uint256 count = Math.min(limit, total - offset);
        unstETHIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            unstETHIds[i] = _accounting.withdrawalBatchIds[offset + i];
        }
    }

    function getIsWithdrawalsClaimed() external view returns (bool) {
        return _accounting.getIsWithdrawalsClaimed();
    }

    function getRageQuitTimelockStartedAt() external view returns (uint256) {
        return _rageQuitTimelockStartedAt;
    }

    function getRageQuitSupport() external view returns (uint256 rageQuitSupport) {
        (uint256 rebaseableShares, uint256 finalizedAmount) = _accounting.getLocked();
        uint256 rebaseableAmount = ST_ETH.getPooledEthByShares(rebaseableShares);
        rageQuitSupport = (10 ** 18 * (rebaseableAmount + finalizedAmount)) / (ST_ETH.totalSupply() + finalizedAmount);
    }

    function isRageQuitFinalized() external view returns (bool) {
        return _escrowState == EscrowState.RageQuitEscrow && _accounting.getIsWithdrawalsClaimed()
            && _rageQuitTimelockStartedAt != 0 && block.timestamp > _rageQuitTimelockStartedAt + _rageQuitExtraTimelock;
    }

    // ---
    // RECEIVE
    // ---

    receive() external payable {
        if (msg.sender != address(WITHDRAWAL_QUEUE)) {
            revert InvalidETHSender(msg.sender, address(WITHDRAWAL_QUEUE));
        }
    }

    // ---
    // Internal Methods
    // ---

    function _activateNextGovernanceState() internal {
        _dualGovernance.activateNextState();
    }

    function _checkEscrowState(EscrowState expected) internal view {
        if (_escrowState != expected) {
            revert InvalidState(_escrowState, expected);
        }
    }

    function _checkDualGovernance(address account) internal view {
        if (account != address(_dualGovernance)) {
            revert NotDualGovernance(account, address(_dualGovernance));
        }
    }

    function _checkWithdrawalsTimelockPassed() internal view {
        if (_rageQuitTimelockStartedAt == 0) {
            revert RageQuitExtraTimelockNotStarted();
        }
        if (block.timestamp <= _rageQuitTimelockStartedAt + _rageQuitExtraTimelock + _rageQuitWithdrawalsTimelock) {
            revert WithdrawalsTimelockNotPassed();
        }
    }
}
