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

import {StorageSetup} from "test/kontrol/StorageSetup.sol";

contract EscrowInvariants is StorageSetup {
    function escrowInvariants(Mode mode, Escrow escrow) external view {
        IStETH stEth = escrow.ST_ETH();
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
        EscrowState currentState = EscrowState(_getCurrentState(escrow));
        _establish(mode, 0 < uint8(currentState));
        _establish(mode, uint8(currentState) < 3);
    }

    function signallingEscrowInvariants(Mode mode, Escrow escrow) external view {
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

    function escrowUserInvariants(Mode mode, Escrow escrow, address user) external view {
        _establish(
            mode, escrow.getVetoerState(user).stETHLockedShares <= escrow.getLockedAssetsTotals().stETHLockedShares
        );
    }
}
