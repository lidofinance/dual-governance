// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IWithdrawalQueue, WithdrawalRequestStatus} from "./interfaces/IWithdrawalQueue.sol";

interface IDualGovernance {
    function activateNextState() external;
}

struct LockedAssetsStats {
    uint128 stEthShares;
    uint128 wstEthShares;
    uint128 unstEthShares;
    uint128 finalizedShares;
    uint128 finalizedAmount;
}

struct LockedAssetsTotals {
    uint128 shares;
    uint128 unstEthShares;
    uint128 finalizedShares;
    uint128 finalizedAmount;
    uint128 claimedEthAmount;
}

struct WithdrawalRequestState {
    bool isFinalized;
    bool isClaimed;
    bool isWithdrawn;
    address owner;
    // index of the unstEth NFT associated with WithdrawalRequestState in the
    // array _vetoersUnstEthIds[owner]
    uint64 vetoerUnstEthIndexOneBased;
    uint128 ethAmount;
}

enum EscrowState {
    SignallingEscrow,
    RageQuitEscrow
}

/**
 * A contract serving as a veto signalling and rage quit escrow.
 */
contract Escrow {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    error ZeroWithdraw();
    error NoRequestsToClaim();
    error InvalidEscrowState();
    error NoBatchesToWithdraw();
    error WithdrawalRequestFinalized(uint256 requestId);
    error WithdrawalRequestNotClaimed(uint256 requestId);
    error WithdrawalRequestAlreadyLocked(uint256 requestId);
    error WithdrawalRequestAlreadyWithdrawn(uint256 requestId);
    error InvalidOwner(uint256 unstEthId, address actualOwner, address expectedOwner);

    IStETH public immutable ST_ETH;
    IWstETH public immutable WST_ETH;
    IWithdrawalQueue public immutable WITHDRAWAL_QUEUE;

    EscrowState internal _escrowState;
    IDualGovernance private _dualGovernance;
    LockedAssetsTotals internal _totalLockedAssets;

    // Count

    uint128 internal _claimRequestsCount;
    uint128 internal _claimedRequestsCount;
    uint128 internal _lastRequestedIdToWaitClaimed;

    mapping(address vetoer => LockedAssetsStats) internal _lockedAssetsStats;
    mapping(address vetoer => uint256[] unstEthIds) internal _vetoersUnstEthIds;
    mapping(uint256 unstEthId => WithdrawalRequestState) internal _withdrawalRequestStates;

    // ---
    // Lock / Unlock stETH
    // ---

    function lockStEth(uint256 amount) external {
        uint256 shares = ST_ETH.getSharesByPooledEth(amount);
        ST_ETH.transferSharesFrom(msg.sender, address(this), shares);
        _accountStEthLock(_lockedAssetsStats[msg.sender], shares);
        _activateNextGovernanceState();
    }

    function unlockStEth() external {
        uint256 sharesUnlocked = _accountStEthUnlock(_lockedAssetsStats[msg.sender]);
        ST_ETH.transferShares(msg.sender, sharesUnlocked);
        _activateNextGovernanceState();
    }

    // ---
    // Lock / Unlock wstETH
    // ---

    function lockWstEth(uint256 amount) external {
        WST_ETH.transferFrom(msg.sender, address(this), amount);
        _accountWstEthLock(_lockedAssetsStats[msg.sender], amount);
        _activateNextGovernanceState();
    }

    function unlockWstEth() external {
        uint256 sharesUnlocked = _accountWstEthUnlock(_lockedAssetsStats[msg.sender]);
        WST_ETH.transfer(msg.sender, sharesUnlocked);
        _activateNextGovernanceState();
    }

    // ---
    // Lock / Unlock unstETH
    // ---

    function lockUnstEth(uint256[] memory unstEthIds) external {
        WithdrawalRequestStatus[] memory wrStatuses = WITHDRAWAL_QUEUE.getWithdrawalStatus(unstEthIds);

        uint256 unstEthId;
        uint256 sharesToLock;
        for (uint256 i = 0; i < unstEthIds.length; ++i) {
            unstEthId = unstEthIds[i];
            WithdrawalRequestStatus memory wrStatus = wrStatuses[unstEthId];
            WITHDRAWAL_QUEUE.transferFrom(msg.sender, address(this), unstEthId);

            if (wrStatus.isFinalized) {
                revert WithdrawalRequestFinalized(unstEthId);
            }
            assert(!wrStatus.isClaimed);

            WithdrawalRequestState memory withdrawalRequestState = _withdrawalRequestStates[unstEthId];

            if (withdrawalRequestState.owner != address(0)) {
                revert WithdrawalRequestAlreadyLocked(unstEthId);
            }
            assert(!withdrawalRequestState.isClaimed);
            assert(!withdrawalRequestState.isFinalized);

            _withdrawalRequestStates[unstEthId].owner = wrStatus.owner;
            sharesToLock += wrStatus.amountOfShares;
        }
        _accountUnstEthLock(_lockedAssetsStats[msg.sender], sharesToLock);
        _activateNextGovernanceState();
    }

    function unlockUnstEth(uint256[] memory unstEthIds) external {
        WithdrawalRequestStatus[] memory wrStatuses = WITHDRAWAL_QUEUE.getWithdrawalStatus(unstEthIds);

        uint256 unstEthId;
        uint256 sharesToUnlock;
        uint256 finalizedAmountToUnlock;
        uint256 finalizedSharesToUnlock;

        for (uint256 i = 0; i < unstEthIds.length; ++i) {
            unstEthId = unstEthIds[i];
            WithdrawalRequestState memory state = _withdrawalRequestStates[unstEthId];

            if (state.owner != msg.sender) {
                revert InvalidOwner(unstEthId, msg.sender, state.owner);
            }
            WITHDRAWAL_QUEUE.transferFrom(address(this), msg.sender, unstEthId);

            WithdrawalRequestStatus memory status = wrStatuses[i];

            if (status.isFinalized) {
                finalizedSharesToUnlock += status.amountOfShares;
                finalizedAmountToUnlock += _withdrawalRequestStates[unstEthId].ethAmount;
            }

            delete _withdrawalRequestStates[unstEthId];
            uint256[] storage vetoerUnstEthIds = _vetoersUnstEthIds[msg.sender];
            // todo: add underflow checks
            uint256 unstEthIdIndex = state.vetoerUnstEthIndexOneBased - 1;
            uint256 lastUnstEthIdIndex = vetoerUnstEthIds.length - 1;
            if (lastUnstEthIdIndex != unstEthIdIndex) {
                vetoerUnstEthIds[unstEthIdIndex] = vetoerUnstEthIds[lastUnstEthIdIndex];
            }
            vetoerUnstEthIds.pop();
        }

        LockedAssetsStats storage vetoerLockedAssets = _lockedAssetsStats[msg.sender];
        vetoerLockedAssets.unstEthShares -= sharesToUnlock.toUint128();
        vetoerLockedAssets.finalizedAmount -= finalizedAmountToUnlock.toUint128();
        vetoerLockedAssets.finalizedShares -= finalizedSharesToUnlock.toUint128();

        _totalLockedAssets.unstEthShares -= sharesToUnlock.toUint128();
        _totalLockedAssets.finalizedAmount -= finalizedAmountToUnlock.toUint128();
        _totalLockedAssets.finalizedShares -= finalizedSharesToUnlock.toUint128();

        _activateNextGovernanceState();
    }

    // ---
    // State Updates
    // ---
    function markFinalized(uint256[] memory unstEthIds, uint256[] calldata hints) external {
        if (_escrowState != EscrowState.SignallingEscrow) {
            revert InvalidEscrowState();
        }

        uint256[] memory claimableEthValues = WITHDRAWAL_QUEUE.getClaimableEther(unstEthIds, hints);
        WithdrawalRequestStatus[] memory wrStatuses = WITHDRAWAL_QUEUE.getWithdrawalStatus(unstEthIds);

        uint256 unstEthId;
        uint256 totalAmountFinalized;
        uint256 totalSharesFinalized;
        for (uint256 i = 0; i < unstEthIds.length; ++i) {
            unstEthId = unstEthIds[i];
            WithdrawalRequestState memory state = _withdrawalRequestStates[unstEthId];
            if (state.isFinalized || state.owner == address(0) || claimableEthValues[i] == 0) {
                // skip the NFTs which were not locked or not finalized or already locked
                continue;
            }
            assert(!state.isClaimed);

            totalAmountFinalized += claimableEthValues[i];
            totalSharesFinalized += wrStatuses[i].amountOfShares;

            _withdrawalRequestStates[unstEthId].isFinalized = true;
            _withdrawalRequestStates[unstEthId].ethAmount = claimableEthValues[i].toUint128();
        }
        _totalLockedAssets.finalizedAmount += totalAmountFinalized.toUint128();
        _totalLockedAssets.finalizedShares += totalSharesFinalized.toUint128();
    }

    function startRageQuit() external {
        _escrowState = EscrowState.RageQuitEscrow;

        uint256 wstEthBalance = WST_ETH.balanceOf(address(this));
        if (wstEthBalance > 0) {
            WST_ETH.unwrap(wstEthBalance);
        }

        ST_ETH.approve(address(WITHDRAWAL_QUEUE), type(uint256).max);
    }

    function requestWithdrawalsBatch(uint256 maxWithdrawalRequestsCount) external {
        if (_escrowState != EscrowState.RageQuitEscrow) {
            revert InvalidEscrowState();
        }

        if (_lastRequestedIdToWaitClaimed != 0) {
            revert NoBatchesToWithdraw();
        }

        uint256 minRequestAmount = WITHDRAWAL_QUEUE.MIN_STETH_WITHDRAWAL_AMOUNT();
        uint256 maxRequestAmount = WITHDRAWAL_QUEUE.MAX_STETH_WITHDRAWAL_AMOUNT();

        uint256 currentBalance = ST_ETH.balanceOf(address(this));
        uint256 requestsCount = Math.min(maxWithdrawalRequestsCount, currentBalance / maxRequestAmount + 1);

        uint256[] memory requestAmounts = new uint256[](requestsCount);
        for (uint256 i = 0; i < requestsCount; ++i) {
            requestAmounts[i] = maxRequestAmount;
        }

        // if we preparing the final batch, last withdrawal request will contain less
        // stETH than maxRequestAmount
        if (currentBalance < requestsCount * maxRequestAmount) {
            uint256 lastRequestAmount = currentBalance % maxRequestAmount;
            requestAmounts[requestsCount - 1] = lastRequestAmount;
            // completely remove the last item if it's less than the minimal withdrawal amount
            if (lastRequestAmount < minRequestAmount) {
                assembly {
                    mstore(requestAmounts, sub(requestsCount, 1))
                }
            }
        }

        if (requestAmounts.length > 0) {
            WITHDRAWAL_QUEUE.requestWithdrawals(requestAmounts, address(this));
            _claimRequestsCount += requestAmounts.length.toUint128();
        }

        if (ST_ETH.balanceOf(address(this)) < minRequestAmount) {
            _lastRequestedIdToWaitClaimed = WITHDRAWAL_QUEUE.getLastRequestId().toUint128();
        }
    }

    function claimWithdrawalsBatch(uint256[] calldata requestIds, uint256[] calldata hints) external {
        if (_escrowState != EscrowState.RageQuitEscrow) {
            revert InvalidEscrowState();
        }

        if (_claimRequestsCount == _claimedRequestsCount) {
            revert NoRequestsToClaim();
        }

        uint256 ethBalanceBefore = address(this).balance;
        WITHDRAWAL_QUEUE.claimWithdrawals(requestIds, hints);
        uint256 ethAmountClaimed = address(this).balance - ethBalanceBefore;

        _totalLockedAssets.claimedEthAmount += ethAmountClaimed.toUint128();
        _claimedRequestsCount += requestIds.length.toUint128();

        if (_claimedRequestsCount == _claimRequestsCount) {
            // TODO: start the `RageQuitExtraTimelock`
        }
    }

    function claimWithdrawalRequests(uint256[] calldata requestIds, uint256[] calldata hints) external {
        if (_escrowState != EscrowState.RageQuitEscrow) {
            revert InvalidEscrowState();
        }
        uint256[] memory claimedAmounts = WITHDRAWAL_QUEUE.getClaimableEther(requestIds, hints);

        uint256 ethBalanceBefore = address(this).balance;
        WITHDRAWAL_QUEUE.claimWithdrawals(requestIds, hints);
        uint256 ethAmountClaimed = address(this).balance - ethBalanceBefore;

        for (uint256 i = 0; i < requestIds.length; ++i) {
            WithdrawalRequestState storage wq = _withdrawalRequestStates[requestIds[i]];
            wq.isClaimed = true;
            wq.ethAmount = claimedAmounts[i].toUint128();
            _lockedAssetsStats[wq.owner].finalizedAmount += claimedAmounts[i].toUint128();
        }

        _totalLockedAssets.claimedEthAmount += ethAmountClaimed.toUint128();
    }

    // ---
    // Withdraw Logic
    // ---

    function withdrawStEth() external {
        LockedAssetsTotals memory totals = _totalLockedAssets;
        LockedAssetsStats memory stats = _lockedAssetsStats[msg.sender];

        uint256 ethAmount = totals.claimedEthAmount * stats.stEthShares / totals.shares;

        _lockedAssetsStats[msg.sender].stEthShares = 0;

        if (ethAmount == 0) {
            revert ZeroWithdraw();
        }

        Address.sendValue(payable(msg.sender), ethAmount);
    }

    function withdrawWstEth() external {
        LockedAssetsTotals memory totals = _totalLockedAssets;
        LockedAssetsStats memory stats = _lockedAssetsStats[msg.sender];

        uint256 ethAmount = totals.claimedEthAmount * stats.wstEthShares / totals.shares;

        _lockedAssetsStats[msg.sender].wstEthShares = 0;

        if (ethAmount == 0) {
            revert ZeroWithdraw();
        }

        Address.sendValue(payable(msg.sender), ethAmount);
    }

    function withdrawUnstEth(uint256[] calldata requestIds) external {
        uint256 requestId;
        for (uint256 i = 0; i < requestIds.length; ++i) {
            requestId = requestIds[i];
            WithdrawalRequestState memory state = _withdrawalRequestStates[requestIds[i]];
            if (state.owner != msg.sender) {
                revert InvalidOwner(requestId, msg.sender, state.owner);
            }
            if (!state.isClaimed) {
                revert WithdrawalRequestNotClaimed(requestId);
            }
            if (state.isWithdrawn) {
                revert WithdrawalRequestAlreadyWithdrawn(requestId);
            }
            state.isWithdrawn = true;
            Address.sendValue(payable(msg.sender), state.ethAmount);
        }
    }

    // ---
    // Getters
    // ---

    function getRageQuitSupport() external view returns (uint256) {
        LockedAssetsTotals memory totals = _totalLockedAssets;

        uint256 rebaseableAmount = ST_ETH.getPooledEthByShares(totals.shares - totals.finalizedShares);
        return 10 ** 18 * (rebaseableAmount + totals.finalizedAmount) / (ST_ETH.totalSupply() + totals.finalizedAmount);
    }

    // ---
    // Internal Methods
    // ---

    function _accountStEthLock(LockedAssetsStats storage assets, uint256 shares) internal {
        uint128 sharesUint128 = shares.toUint128();
        assets.stEthShares += sharesUint128;
        _totalLockedAssets.shares += sharesUint128;
    }

    function _accountStEthUnlock(LockedAssetsStats storage assets) internal returns (uint128 sharesUnlocked) {
        sharesUnlocked = assets.stEthShares;
        assets.stEthShares = 0;
        _totalLockedAssets.shares -= sharesUnlocked;
    }

    function _accountWstEthLock(LockedAssetsStats storage assets, uint256 shares) internal {
        uint128 sharesUint128 = shares.toUint128();
        assets.wstEthShares += sharesUint128;
        _totalLockedAssets.shares += sharesUint128;
    }

    function _accountWstEthUnlock(LockedAssetsStats storage assets) internal returns (uint128 sharesUnlocked) {
        sharesUnlocked = assets.wstEthShares;
        assets.wstEthShares = 0;
        _totalLockedAssets.shares -= sharesUnlocked;
    }

    function _accountUnstEthLock(LockedAssetsStats storage assets, uint256 shares) internal {
        uint128 sharesUint128 = shares.toUint128();
        assets.unstEthShares += sharesUint128;
        _totalLockedAssets.unstEthShares += sharesUint128;
    }

    function _activateNextGovernanceState() internal {
        _dualGovernance.activateNextState();
    }
}
