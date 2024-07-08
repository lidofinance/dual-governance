pragma solidity 0.8.23;

import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";
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

    function _getEnteredAt(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_dualGovernance), 4) >> 8);
    }

    function _getVetoSignallingActivationTime(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_dualGovernance), 5) >> 48);
    }

    function _getVetoSignallingReactivationTime(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_dualGovernance), 5));
    }

    function _dualGovernanceStorageSetup(
        DualGovernance _dualGovernance,
        EmergencyProtectedTimelock _timelock,
        StETHModel _stEth,
        IEscrow _signallingEscrow,
        IEscrow _rageQuitEscrow
    ) internal {
        kevm.symbolicStorage(address(_dualGovernance));
        // Slot 4 + 0 = 4
        uint256 currentState = kevm.freshUInt(32);
        vm.assume(currentState <= 4);
        uint256 enteredAt = kevm.freshUInt(32);
        vm.assume(enteredAt <= block.timestamp);
        vm.assume(enteredAt < timeUpperBound);
        uint256 vetoSignallingActivationTime = kevm.freshUInt(32);
        vm.assume(vetoSignallingActivationTime <= block.timestamp);
        vm.assume(vetoSignallingActivationTime < timeUpperBound);
        bytes memory slot4Abi = abi.encodePacked(
            uint8(0),
            uint160(address(_signallingEscrow)),
            uint40(vetoSignallingActivationTime),
            uint40(enteredAt),
            uint8(currentState)
        );
        bytes32 slot4;
        assembly {
            slot4 := mload(add(slot4Abi, 0x20))
        }
        _storeBytes32(address(_dualGovernance), 4, slot4);
        // Slot 4 + 1 = 5
        uint256 vetoSignallingReactivationTime = kevm.freshUInt(32);
        vm.assume(vetoSignallingReactivationTime <= block.timestamp);
        vm.assume(vetoSignallingReactivationTime < timeUpperBound);
        uint256 lastAdoptableStateExitedAt = kevm.freshUInt(32);
        vm.assume(lastAdoptableStateExitedAt <= block.timestamp);
        vm.assume(lastAdoptableStateExitedAt < timeUpperBound);
        uint256 rageQuitRound = kevm.freshUInt(32);
        vm.assume(rageQuitRound < type(uint8).max);
        bytes memory slot5Abi = abi.encodePacked(
            uint8(0),
            uint8(rageQuitRound),
            uint160(address(_rageQuitEscrow)),
            uint40(lastAdoptableStateExitedAt),
            uint40(vetoSignallingReactivationTime)
        );
        bytes32 slot5;
        assembly {
            slot5 := mload(add(slot5Abi, 0x20))
        }
        _storeBytes32(address(_dualGovernance), 5, slot5);
    }

    function _signallingEscrowStorageSetup(
        IEscrow _signallingEscrow,
        DualGovernance _dualGovernance,
        StETHModel _stEth
    ) internal {
        _escrowStorageSetup(_signallingEscrow, _dualGovernance, _stEth, EscrowState.SignallingEscrow);

        uint256 rageQuitTimelockStartedAt = _loadUInt256(address(_signallingEscrow), 12);
        vm.assume(rageQuitTimelockStartedAt == 0);
    }

    function _rageQuitEscrowStorageSetup(
        IEscrow _rageQuitEscrow,
        DualGovernance _dualGovernance,
        StETHModel _stEth
    ) internal {
        _escrowStorageSetup(_rageQuitEscrow, _dualGovernance, _stEth, EscrowState.RageQuitEscrow);
    }

    function _getCurrentState(Escrow _escrow) internal view returns (EscrowState) {
        return EscrowState(uint8(uint256(vm.load(address(_escrow), 0))));
    }

    function _getLastAssetsLockTimestamp(Escrow _escrow, address _vetoer) internal view returns (uint40) {
        uint256 assetsSlot = 3;
        uint256 vetoerAddressPadded = uint256(uint160(_vetoer));
        bytes32 vetoerAssetsSlot = keccak256(abi.encodePacked(vetoerAddressPadded, assetsSlot));
        bytes32 lastAssetsLockTimestampSlot = bytes32(uint256(vetoerAssetsSlot) + 2);
        uint256 offset = 128;
        return uint40(uint256(vm.load(address(_escrow), lastAssetsLockTimestampSlot)) >> offset);
    }

    function _escrowStorageSetup(
        IEscrow _escrow,
        DualGovernance _dualGovernance,
        StETHModel _stEth,
        EscrowState _currentState
    ) internal {
        kevm.symbolicStorage(address(_escrow));
        // Slot 0
        {
            bytes memory slot0Abi = abi.encodePacked(uint88(0), uint160(address(_dualGovernance)), uint8(_currentState));
            bytes32 slot0;
            assembly {
                slot0 := mload(add(slot0Abi, 0x20))
            }
            _storeBytes32(address(_escrow), 0, slot0);
            // Slot 1 + 0 + 0 = 1
            uint256 shares = kevm.freshUInt(32);
            vm.assume(shares < ethUpperBound);
            uint256 sharesFinalized = kevm.freshUInt(32);
            vm.assume(sharesFinalized < ethUpperBound);
            bytes memory slot1Abi = abi.encodePacked(uint128(sharesFinalized), uint128(shares));
            bytes32 slot1;
            assembly {
                slot1 := mload(add(slot1Abi, 0x20))
            }
            _storeBytes32(address(_escrow), 1, slot1);
        }
        // Slot 1 + 0 + 1 = 2
        {
            uint256 amountFinalized = kevm.freshUInt(32);
            vm.assume(amountFinalized < ethUpperBound);
            uint256 amountClaimed = kevm.freshUInt(32);
            vm.assume(amountClaimed < ethUpperBound);
            bytes memory slot2Abi = abi.encodePacked(uint128(amountClaimed), uint128(amountFinalized));
            bytes32 slot2;
            assembly {
                slot2 := mload(add(slot2Abi, 0x20))
            }
            _storeBytes32(address(_escrow), 2, slot2);
        }
        // Slot 10
        {
            uint256 rageQuitExtraTimelock = kevm.freshUInt(32);
            vm.assume(rageQuitExtraTimelock <= block.timestamp);
            vm.assume(rageQuitExtraTimelock < timeUpperBound);
            _storeUInt256(address(_escrow), 10, rageQuitExtraTimelock);
        }
        // Slot 11
        {
            uint256 rageQuitWithdrawalsTimelock = kevm.freshUInt(32);
            vm.assume(rageQuitWithdrawalsTimelock <= block.timestamp);
            vm.assume(rageQuitWithdrawalsTimelock < timeUpperBound);
            _storeUInt256(address(_escrow), 11, rageQuitWithdrawalsTimelock);
        }
        // Slot 12
        {
            uint256 rageQuitTimelockStartedAt = kevm.freshUInt(32);
            vm.assume(rageQuitTimelockStartedAt <= block.timestamp);
            vm.assume(rageQuitTimelockStartedAt < timeUpperBound);
            _storeUInt256(address(_escrow), 12, rageQuitTimelockStartedAt);
        }
    }
}
