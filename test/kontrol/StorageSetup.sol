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

    function _loadTimestamp(address contractAddress, uint256 slot) internal view returns (Timestamp) {
        return Timestamp.wrap(uint40(_loadUInt256(contractAddress, slot)));
    }

    function _loadTimestamp(address contractAddress, uint256 slot, uint256 offset) internal view returns (Timestamp) {
        return Timestamp.wrap(uint40(_loadUInt256(contractAddress, slot) >> offset));
    }

    function _getEnteredAt(DualGovernance _dualGovernance) internal view returns (Timestamp) {
        return _loadTimestamp(address(_dualGovernance), 5, 8);
    }

    function _getVetoSignallingActivationTime(DualGovernance _dualGovernance) internal view returns (Timestamp) {
        return _loadTimestamp(address(_dualGovernance), 5, 48);
    }

    function _getVetoSignallingReactivationTime(DualGovernance _dualGovernance) internal view returns (Timestamp) {
        return _loadTimestamp(address(_dualGovernance), 6);
    }

    function _dualGovernanceStorageSetup(
        DualGovernance _dualGovernance,
        IEscrow _signallingEscrow,
        IEscrow _rageQuitEscrow
    ) internal {
        kevm.symbolicStorage(address(_dualGovernance));
        // Slot 5 + 0 = 5
        uint256 currentState = kevm.freshUInt(32);
        vm.assume(currentState <= 4);
        uint256 enteredAt = kevm.freshUInt(32);
        vm.assume(enteredAt <= block.timestamp);
        vm.assume(enteredAt < timeUpperBound);
        uint256 vetoSignallingActivationTime = kevm.freshUInt(32);
        vm.assume(vetoSignallingActivationTime <= block.timestamp);
        vm.assume(vetoSignallingActivationTime < timeUpperBound);
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
        uint256 vetoSignallingReactivationTime = kevm.freshUInt(32);
        vm.assume(vetoSignallingReactivationTime <= block.timestamp);
        vm.assume(vetoSignallingReactivationTime < timeUpperBound);
        uint256 lastAdoptableStateExitedAt = kevm.freshUInt(32);
        vm.assume(lastAdoptableStateExitedAt <= block.timestamp);
        vm.assume(lastAdoptableStateExitedAt < timeUpperBound);
        uint256 rageQuitRound = kevm.freshUInt(32);
        vm.assume(rageQuitRound < type(uint8).max);
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

    function _signallingEscrowStorageSetup(IEscrow _signallingEscrow, DualGovernance _dualGovernance) internal {
        _escrowStorageSetup(_signallingEscrow, _dualGovernance, EscrowState.SignallingEscrow);

        vm.assume(_getRageQuitExtensionDelay(_signallingEscrow) == 0);
        vm.assume(_getRageQuitWithdrawalsTimelock(_signallingEscrow) == 0);
        vm.assume(_getRageQuitTimelockStartedAt(_signallingEscrow) == 0);
        vm.assume(_getBatchesQueue(_signallingEscrow) == WithdrawalsBatchesQueue.Status.Empty);
    }

    function _rageQuitEscrowStorageSetup(IEscrow _rageQuitEscrow, DualGovernance _dualGovernance) internal {
        _escrowStorageSetup(_rageQuitEscrow, _dualGovernance, EscrowState.RageQuitEscrow);
        vm.assume(_getBatchesQueue(_rageQuitEscrow) != WithdrawalsBatchesQueue.Status.Empty);
    }

    function _getCurrentState(IEscrow _escrow) internal view returns (EscrowState) {
        return EscrowState(uint8(uint256(vm.load(address(_escrow), 0))));
    }

    function _getLastAssetsLockTimestamp(IEscrow _escrow, address _vetoer) internal view returns (uint256) {
        uint256 assetsSlot = 3;
        uint256 vetoerAddressPadded = uint256(uint160(_vetoer));
        bytes32 vetoerAssetsSlot = keccak256(abi.encodePacked(vetoerAddressPadded, assetsSlot));
        uint256 lastAssetsLockTimestampSlot = uint256(vetoerAssetsSlot) + 1;
        return _loadUInt256(address(_escrow), lastAssetsLockTimestampSlot);
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

    function _getBatchesQueue(IEscrow _escrow) internal view returns (WithdrawalsBatchesQueue.Status) {
        return WithdrawalsBatchesQueue.Status(uint8(_loadUInt256(address(_escrow), 5)));
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
            vm.assume(lockedShares < ethUpperBound);
            uint128 claimedETH = uint128(kevm.freshUInt(16));
            vm.assume(claimedETH < ethUpperBound);
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
            vm.assume(unfinalizedShares < ethUpperBound);
            uint128 finalizedETH = uint128(kevm.freshUInt(16));
            vm.assume(finalizedETH < ethUpperBound);
            bytes memory slot2Abi = abi.encodePacked(uint128(finalizedETH), uint128(unfinalizedShares));
            bytes32 slot2;
            assembly {
                slot2 := mload(add(slot2Abi, 0x20))
            }
            _storeBytes32(address(_escrow), 2, slot2);
        }
        // Slot 5
        {
            uint256 batchesQueue = kevm.freshUInt(32);
            vm.assume(batchesQueue < 3);
            _storeUInt256(address(_escrow), 5, batchesQueue);
        }
        // Slot 9
        {
            uint32 rageQuitExtensionDelay = uint32(kevm.freshUInt(4));
            vm.assume(rageQuitExtensionDelay <= block.timestamp);
            vm.assume(rageQuitExtensionDelay < timeUpperBound);
            uint32 rageQuitWithdrawalsTimelock = uint32(kevm.freshUInt(4));
            vm.assume(rageQuitWithdrawalsTimelock <= block.timestamp);
            vm.assume(rageQuitWithdrawalsTimelock < timeUpperBound);
            uint40 rageQuitTimelockStartedAt = uint40(kevm.freshUInt(5));
            vm.assume(rageQuitTimelockStartedAt <= block.timestamp);
            vm.assume(rageQuitTimelockStartedAt < timeUpperBound);
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
}
