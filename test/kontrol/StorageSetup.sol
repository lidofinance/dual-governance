pragma solidity 0.8.23;

import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";

import {Timestamp} from "contracts/types/Timestamp.sol";
import "contracts/libraries/WithdrawalBatchesQueue.sol";

import "contracts/model/StETHModel.sol";
import "contracts/model/WstETHAdapted.sol";

import "test/kontrol/KontrolTest.sol";

contract StorageSetup is KontrolTest {
    function _stEthStorageSetup(StETHModel _stEth, IEscrow _escrow) internal {
        kevm.symbolicStorage(address(_stEth));
        // Slot 0
        uint256 totalPooledEther = kevm.freshUInt(32);
        vm.assume(0 < totalPooledEther);
        vm.assume(totalPooledEther < ethUpperBound);
        _stEth.setTotalPooledEther(totalPooledEther);
        // Slot 1
        uint256 totalShares = kevm.freshUInt(32);
        vm.assume(0 < totalShares);
        vm.assume(totalShares < ethUpperBound);
        _stEth.setTotalShares(totalShares);
        // Slot 2
        uint256 shares = kevm.freshUInt(32);
        vm.assume(shares < totalShares);
        _stEth.setShares(address(_escrow), shares);
    }

    function _wstEthStorageSetup(WstETHAdapted _wstEth, IStETH _stEth) internal {
        kevm.symbolicStorage(address(_wstEth));
    }

    function _getCurrentState(DualGovernance _dualGovernance) internal view returns (uint8) {
        return uint8(_loadUInt256(address(_dualGovernance), 5));
    }

    function _getEnteredAt(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_dualGovernance), 5) >> 8);
    }

    function _getVetoSignallingActivationTime(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_dualGovernance), 5) >> 48);
    }

    function _getVetoSignallingReactivationTime(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_dualGovernance), 6));
    }

    function _getLastAdoptableStateExitedAt(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_dualGovernance), 6) >> 40);
    }

    function _getRageQuitRound(DualGovernance _dualGovernance) internal view returns (uint8) {
        return uint8(_loadUInt256(address(_dualGovernance), 6) >> 240);
    }

    function _dualGovernanceStorageSetup(
        DualGovernance _dualGovernance,
        IEscrow _signallingEscrow,
        IEscrow _rageQuitEscrow
    ) internal {
        kevm.symbolicStorage(address(_dualGovernance));
        // Slot 5 + 0 = 5
        uint8 currentState = uint8(kevm.freshUInt(1));
        uint40 enteredAt = uint40(kevm.freshUInt(5));
        uint40 vetoSignallingActivationTime = uint40(kevm.freshUInt(5));
        bytes memory slot5Abi = abi.encodePacked(
            uint8(0),
            uint160(address(_signallingEscrow)),
            uint40(vetoSignallingActivationTime),
            uint40(enteredAt),
            uint8(currentState)
        );
        bytes32 slot5;
        assembly {
            slot5 := mload(add(slot5Abi, 0x20))
        }
        _storeBytes32(address(_dualGovernance), 5, slot5);
        // Slot 5 + 1 = 6
        uint40 vetoSignallingReactivationTime = uint40(kevm.freshUInt(5));
        uint40 lastAdoptableStateExitedAt = uint40(kevm.freshUInt(5));
        uint8 rageQuitRound = uint8(kevm.freshUInt(1));
        bytes memory slot6Abi = abi.encodePacked(
            uint8(0),
            uint8(rageQuitRound),
            uint160(address(_rageQuitEscrow)),
            uint40(lastAdoptableStateExitedAt),
            uint40(vetoSignallingReactivationTime)
        );
        bytes32 slot6;
        assembly {
            slot6 := mload(add(slot6Abi, 0x20))
        }
        _storeBytes32(address(_dualGovernance), 6, slot6);
    }

    function _dualGovernanceStorageInvariants(Mode mode, DualGovernance _dualGovernance) internal {
        uint8 currentState = _getCurrentState(_dualGovernance);
        uint40 enteredAt = _getEnteredAt(_dualGovernance);
        uint40 vetoSignallingActivationTime = _getVetoSignallingActivationTime(_dualGovernance);
        uint40 vetoSignallingReactivationTime = _getVetoSignallingReactivationTime(_dualGovernance);
        uint40 lastAdoptableStateExitedAt = _getLastAdoptableStateExitedAt(_dualGovernance);
        uint8 rageQuitRound = _getRageQuitRound(_dualGovernance);

        _establish(mode, currentState <= 4);
        _establish(mode, enteredAt <= block.timestamp);
        _establish(mode, vetoSignallingActivationTime <= block.timestamp);
        _establish(mode, vetoSignallingReactivationTime <= block.timestamp);
        _establish(mode, lastAdoptableStateExitedAt <= block.timestamp);
    }

    function _dualGovernanceAssumeBounds(DualGovernance _dualGovernance) internal {
        uint40 enteredAt = _getEnteredAt(_dualGovernance);
        uint40 vetoSignallingActivationTime = _getVetoSignallingActivationTime(_dualGovernance);
        uint40 vetoSignallingReactivationTime = _getVetoSignallingReactivationTime(_dualGovernance);
        uint40 lastAdoptableStateExitedAt = _getLastAdoptableStateExitedAt(_dualGovernance);
        uint8 rageQuitRound = _getRageQuitRound(_dualGovernance);

        vm.assume(enteredAt < timeUpperBound);
        vm.assume(vetoSignallingActivationTime < timeUpperBound);
        vm.assume(vetoSignallingReactivationTime < timeUpperBound);
        vm.assume(lastAdoptableStateExitedAt < timeUpperBound);
        vm.assume(rageQuitRound < type(uint8).max);
    }

    function _dualGovernanceInitializeStorage(
        DualGovernance _dualGovernance,
        IEscrow _signallingEscrow,
        IEscrow _rageQuitEscrow
    ) internal {
        _dualGovernanceStorageSetup(_dualGovernance, _signallingEscrow, _rageQuitEscrow);
        _dualGovernanceStorageInvariants(Mode.Assume, _dualGovernance);
        _dualGovernanceAssumeBounds(_dualGovernance);
    }

    function _getCurrentState(IEscrow _escrow) internal view returns (uint8) {
        return uint8(_loadUInt256(address(_escrow), 0));
    }

    function _getStEthLockedShares(IEscrow _escrow) internal view returns (uint128) {
        return uint128(_loadUInt256(address(_escrow), 1));
    }

    function _getClaimedEth(IEscrow _escrow) internal view returns (uint128) {
        return uint128(_loadUInt256(address(_escrow), 1) >> 128);
    }

    function _getUnfinalizedShares(IEscrow _escrow) internal view returns (uint128) {
        return uint128(_loadUInt256(address(_escrow), 2));
    }

    function _getFinalizedEth(IEscrow _escrow) internal view returns (uint128) {
        return uint128(_loadUInt256(address(_escrow), 2) >> 128);
    }

    function _getLastAssetsLockTimestamp(IEscrow _escrow, address _vetoer) internal view returns (uint256) {
        uint256 assetsSlot = 3;
        uint256 vetoerAddressPadded = uint256(uint160(_vetoer));
        bytes32 vetoerAssetsSlot = keccak256(abi.encodePacked(vetoerAddressPadded, assetsSlot));
        uint256 lastAssetsLockTimestampSlot = uint256(vetoerAssetsSlot) + 1;
        return _loadUInt256(address(_escrow), lastAssetsLockTimestampSlot);
    }

    function _getBatchesQueueStatus(IEscrow _escrow) internal view returns (uint8) {
        return uint8(_loadUInt256(address(_escrow), 5));
    }

    function _getRageQuitExtensionDelay(IEscrow _escrow) internal view returns (uint32) {
        return uint32(_loadUInt256(address(_escrow), 9));
    }

    function _getRageQuitWithdrawalsTimelock(IEscrow _escrow) internal view returns (uint32) {
        return uint32(_loadUInt256(address(_escrow), 9) >> 32);
    }

    function _getRageQuitTimelockStartedAt(IEscrow _escrow) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_escrow), 9) >> 64);
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

    struct EscrowRecord {
        EscrowState escrowState;
        AccountingRecord accounting;
    }

    function _saveEscrowRecord(address user, Escrow escrow) internal view returns (EscrowRecord memory er) {
        AccountingRecord memory accountingRecord = _saveAccountingRecord(user, escrow);
        er.escrowState = EscrowState(_getCurrentState(escrow));
        er.accounting = accountingRecord;
    }

    function _saveAccountingRecord(address user, Escrow escrow) internal view returns (AccountingRecord memory ar) {
        IStETH stEth = escrow.ST_ETH();
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

    function _establishEqualAccountingRecords(
        Mode mode,
        AccountingRecord memory ar1,
        AccountingRecord memory ar2
    ) internal view {
        _establish(mode, ar1.allowance == ar2.allowance);
        _establish(mode, ar1.userBalance == ar2.userBalance);
        _establish(mode, ar1.escrowBalance == ar2.escrowBalance);
        _establish(mode, ar1.userShares == ar2.userShares);
        _establish(mode, ar1.escrowShares == ar2.escrowShares);
        _establish(mode, ar1.userSharesLocked == ar2.userSharesLocked);
        _establish(mode, ar1.totalSharesLocked == ar2.totalSharesLocked);
        _establish(mode, ar1.totalEth == ar2.totalEth);
        _establish(mode, ar1.userUnstEthLockedShares == ar2.userUnstEthLockedShares);
        _establish(mode, ar1.unfinalizedShares == ar2.unfinalizedShares);
        _establish(mode, ar1.userLastLockedTime == ar2.userLastLockedTime);
    }

    function _escrowStorageSetup(IEscrow _escrow, DualGovernance _dualGovernance, EscrowState _currentState) internal {
        kevm.symbolicStorage(address(_escrow));
        // Slot 0
        {
            bytes memory slot0Abi = abi.encodePacked(uint88(0), uint160(address(_dualGovernance)), uint8(_currentState));
            bytes32 slot0;
            assembly {
                slot0 := mload(add(slot0Abi, 0x20))
            }
            _storeBytes32(address(_escrow), 0, slot0);
        }
        // Slot 1 + 0 + 0 = 1
        {
            uint128 lockedShares = uint128(kevm.freshUInt(16));
            uint128 claimedETH = uint128(kevm.freshUInt(16));
            bytes memory slot1Abi = abi.encodePacked(uint128(claimedETH), uint128(lockedShares));
            bytes32 slot1;
            assembly {
                slot1 := mload(add(slot1Abi, 0x20))
            }
            _storeBytes32(address(_escrow), 1, slot1);
        }
        // Slot 1 + 1 + 0 = 2
        {
            uint128 unfinalizedShares = uint128(kevm.freshUInt(16));
            uint128 finalizedETH = uint128(kevm.freshUInt(16));
            bytes memory slot2Abi = abi.encodePacked(uint128(finalizedETH), uint128(unfinalizedShares));
            bytes32 slot2;
            assembly {
                slot2 := mload(add(slot2Abi, 0x20))
            }
            _storeBytes32(address(_escrow), 2, slot2);
        }
        // Slot 5
        {
            uint8 batchesQueueStatus = uint8(kevm.freshUInt(1));
            _storeUInt256(address(_escrow), 5, batchesQueueStatus);
        }
        // Slot 9
        {
            uint32 rageQuitExtensionDelay = uint32(kevm.freshUInt(4));
            uint32 rageQuitWithdrawalsTimelock = uint32(kevm.freshUInt(4));
            uint40 rageQuitTimelockStartedAt = uint40(kevm.freshUInt(5));
            bytes memory slot9Abi = abi.encodePacked(
                uint152(0),
                uint40(rageQuitTimelockStartedAt),
                uint32(rageQuitWithdrawalsTimelock),
                uint32(rageQuitExtensionDelay)
            );
            bytes32 slot9;
            assembly {
                slot9 := mload(add(slot9Abi, 0x20))
            }
            _storeBytes32(address(_escrow), 9, slot9);
        }
    }

    function _escrowStorageInvariants(Mode mode, IEscrow _escrow) internal {
        uint8 batchesQueueStatus = _getBatchesQueueStatus(_escrow);
        uint32 rageQuitExtensionDelay = _getRageQuitExtensionDelay(_escrow);
        uint32 rageQuitWithdrawalsTimelock = _getRageQuitWithdrawalsTimelock(_escrow);
        uint40 rageQuitTimelockStartedAt = _getRageQuitTimelockStartedAt(_escrow);

        _establish(mode, batchesQueueStatus < 3);
        _establish(mode, rageQuitExtensionDelay <= block.timestamp);
        _establish(mode, rageQuitWithdrawalsTimelock <= block.timestamp);
        _establish(mode, rageQuitTimelockStartedAt <= block.timestamp);
    }

    function _escrowAssumeBounds(IEscrow _escrow) internal {
        uint128 lockedShares = _getStEthLockedShares(_escrow);
        uint128 claimedEth = _getClaimedEth(_escrow);
        uint128 unfinalizedShares = _getUnfinalizedShares(_escrow);
        uint128 finalizedEth = _getFinalizedEth(_escrow);
        uint32 rageQuitExtensionDelay = _getRageQuitExtensionDelay(_escrow);
        uint32 rageQuitWithdrawalsTimelock = _getRageQuitWithdrawalsTimelock(_escrow);
        uint40 rageQuitTimelockStartedAt = _getRageQuitTimelockStartedAt(_escrow);

        vm.assume(lockedShares < ethUpperBound);
        vm.assume(claimedEth < ethUpperBound);
        vm.assume(unfinalizedShares < ethUpperBound);
        vm.assume(finalizedEth < ethUpperBound);
        vm.assume(rageQuitExtensionDelay < timeUpperBound);
        vm.assume(rageQuitWithdrawalsTimelock < timeUpperBound);
        vm.assume(rageQuitTimelockStartedAt < timeUpperBound);
    }

    function _escrowInitializeStorage(
        IEscrow _escrow,
        DualGovernance _dualGovernance,
        EscrowState _currentState
    ) internal {
        _escrowStorageSetup(_escrow, _dualGovernance, _currentState);
        _escrowStorageInvariants(Mode.Assume, _escrow);
        _escrowAssumeBounds(_escrow);
    }

    function _signallingEscrowStorageInvariants(Mode mode, IEscrow _signallingEscrow) internal {
        uint32 rageQuitExtensionDelay = _getRageQuitExtensionDelay(_signallingEscrow);
        uint32 rageQuitWithdrawalsTimelock = _getRageQuitWithdrawalsTimelock(_signallingEscrow);
        uint40 rageQuitTimelockStartedAt = _getRageQuitTimelockStartedAt(_signallingEscrow);
        uint8 batchesQueueStatus = _getBatchesQueueStatus(_signallingEscrow);

        _establish(mode, rageQuitExtensionDelay == 0);
        _establish(mode, rageQuitWithdrawalsTimelock == 0);
        _establish(mode, rageQuitTimelockStartedAt == 0);
        _establish(mode, batchesQueueStatus == uint8(WithdrawalsBatchesQueue.Status.Empty));
    }

    function _signallingEscrowInitializeStorage(IEscrow _signallingEscrow, DualGovernance _dualGovernance) internal {
        _escrowInitializeStorage(_signallingEscrow, _dualGovernance, EscrowState.SignallingEscrow);
        _signallingEscrowStorageInvariants(Mode.Assume, _signallingEscrow);
    }

    function _rageQuitEscrowStorageInvariants(Mode mode, IEscrow _rageQuitEscrow) internal {
        uint8 batchesQueueStatus = _getBatchesQueueStatus(_rageQuitEscrow);

        _establish(mode, batchesQueueStatus != uint8(WithdrawalsBatchesQueue.Status.Empty));
    }

    function _rageQuitEscrowInitializeStorage(IEscrow _rageQuitEscrow, DualGovernance _dualGovernance) internal {
        _escrowInitializeStorage(_rageQuitEscrow, _dualGovernance, EscrowState.RageQuitEscrow);
        _rageQuitEscrowStorageInvariants(Mode.Assume, _rageQuitEscrow);
    }
}
