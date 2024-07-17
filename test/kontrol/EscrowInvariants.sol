pragma solidity 0.8.23;

import "contracts/Configuration.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";

import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import "contracts/model/StETHModel.sol";
import "contracts/model/WithdrawalQueueModel.sol";
import "contracts/model/WstETHAdapted.sol";

import {DualGovernanceSetUp} from "test/kontrol/DualGovernanceSetUp.sol";

contract EscrowInvariants is DualGovernanceSetUp {
    function _escrowInvariants(Mode mode, Escrow escrow) internal view {
        LockedAssetsTotals memory totals = escrow.getLockedAssetsTotals();
        _establish(mode, totals.stETHLockedShares <= stEth.sharesOf(address(escrow)));
        // TODO: Adapt to updated code
        //_establish(mode, totals.sharesFinalized <= totals.stETHLockedShares);
        uint256 totalPooledEther = stEth.getPooledEthByShares(totals.stETHLockedShares);
        _establish(mode, totalPooledEther <= stEth.balanceOf(address(escrow)));
        // TODO: Adapt to updated code
        //_establish(mode, totals.amountFinalized == stEth.getPooledEthByShares(totals.sharesFinalized));
        //_establish(mode, totals.amountFinalized <= totalPooledEther);
        //_establish(mode, totals.amountClaimed <= totals.amountFinalized);
        EscrowState currentState = _getCurrentState(escrow);
        _establish(mode, 0 < uint8(currentState));
        _establish(mode, uint8(currentState) < 3);
    }

    function _signallingEscrowInvariants(Mode mode, Escrow escrow) internal view {
        // TODO: Adapt to updated code
        /*
        if (_getCurrentState(escrow) == EscrowState.SignallingEscrow) {
            LockedAssetsTotals memory totals = escrow.getLockedAssetsTotals();
            _establish(mode, totals.sharesFinalized == 0);
            _establish(mode, totals.amountFinalized == 0);
            _establish(mode, totals.amountClaimed == 0);
        }
        */
    }

    function _escrowUserInvariants(Mode mode, Escrow escrow, address user) internal view {
        _establish(
            mode, escrow.getVetoerState(user).stETHLockedShares <= escrow.getLockedAssetsTotals().stETHLockedShares
        );
    }

    struct AccountingRecord {
        EscrowState escrowState;
        uint256 allowance;
        uint256 userBalance;
        uint256 escrowBalance;
        uint256 userShares;
        uint256 escrowShares;
        uint256 userSharesLocked;
        uint256 totalSharesLocked;
        uint256 totalEth;
        uint256 userUnstEthLockedShares;
        uint256 unfinalizedShares;
        Timestamp userLastLockedTime;
    }

    function _saveAccountingRecord(address user, Escrow escrow) internal view returns (AccountingRecord memory ar) {
        IStETH stEth = escrow.ST_ETH();
        ar.escrowState = _getCurrentState(escrow);
        ar.allowance = stEth.allowance(user, address(escrow));
        ar.userBalance = stEth.balanceOf(user);
        ar.escrowBalance = stEth.balanceOf(address(escrow));
        ar.userShares = stEth.sharesOf(user);
        ar.escrowShares = stEth.sharesOf(address(escrow));
        ar.userSharesLocked = escrow.getVetoerState(user).stETHLockedShares;
        ar.totalSharesLocked = escrow.getLockedAssetsTotals().stETHLockedShares;
        ar.totalEth = stEth.getPooledEthByShares(ar.totalSharesLocked);
        ar.userUnstEthLockedShares = escrow.getVetoerState(user).unstETHLockedShares;
        ar.unfinalizedShares = escrow.getLockedAssetsTotals().unstETHUnfinalizedShares;
        uint256 lastAssetsLockTimestamp = _getLastAssetsLockTimestamp(escrow, user);
        require(lastAssetsLockTimestamp < timeUpperBound);
        ar.userLastLockedTime = Timestamp.wrap(uint40(lastAssetsLockTimestamp));
    }
}
