pragma solidity 0.8.23;

import "contracts/model/DualGovernanceModel.sol";
import "contracts/model/EmergencyProtectedTimelockModel.sol";
import "contracts/model/EscrowModel.sol";
import "contracts/model/StETHModel.sol";

import "test/kontrol/KontrolTest.sol";

contract StorageSetup is KontrolTest {
    function _stEthStorageSetup(StETHModel _stEth, EscrowModel _escrow) internal {
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

    function _dualGovernanceStorageSetup(
        DualGovernanceModel _dualGovernance,
        EmergencyProtectedTimelockModel _timelock,
        StETHModel _stEth,
        EscrowModel _signallingEscrow,
        EscrowModel _rageQuitEscrow
    ) internal {
        kevm.symbolicStorage(address(_dualGovernance));
        // Slot 0
        _storeAddress(address(_dualGovernance), 0, address(_timelock));
        // Slot 1
        _storeAddress(address(_dualGovernance), 1, address(_signallingEscrow));
        // Slot 2
        _storeAddress(address(_dualGovernance), 2, address(_rageQuitEscrow));
        // Slot 3
        _storeAddress(address(_dualGovernance), 3, address(_stEth));
        // Slot 6
        uint256 lastStateChangeTime = kevm.freshUInt(32);
        vm.assume(lastStateChangeTime <= block.timestamp);
        vm.assume(lastStateChangeTime < timeUpperBound);
        _storeUInt256(address(_dualGovernance), 6, lastStateChangeTime);
        // Slot 7
        uint256 lastSubStateActivationTime = kevm.freshUInt(32);
        vm.assume(lastSubStateActivationTime <= block.timestamp);
        vm.assume(lastSubStateActivationTime < timeUpperBound);
        _storeUInt256(address(_dualGovernance), 7, lastSubStateActivationTime);
        // Slot 8
        uint256 lastStateReactivationTime = kevm.freshUInt(32);
        vm.assume(lastStateReactivationTime <= block.timestamp);
        vm.assume(lastStateReactivationTime < timeUpperBound);
        _storeUInt256(address(_dualGovernance), 8, lastStateReactivationTime);
        // Slot 9
        uint256 lastVetoSignallingTime = kevm.freshUInt(32);
        vm.assume(lastVetoSignallingTime <= block.timestamp);
        vm.assume(lastVetoSignallingTime < timeUpperBound);
        _storeUInt256(address(_dualGovernance), 9, lastVetoSignallingTime);
        // Slot 10
        uint256 rageQuitSequenceNumber = kevm.freshUInt(32);
        vm.assume(rageQuitSequenceNumber < type(uint256).max);
        _storeUInt256(address(_dualGovernance), 10, rageQuitSequenceNumber);
        // Slot 11
        uint256 state = kevm.freshUInt(32);
        vm.assume(state <= 4);
        _storeUInt256(address(_dualGovernance), 11, state);
    }

    function _signallingEscrowStorageSetup(
        EscrowModel _signallingEscrow,
        DualGovernanceModel _dualGovernance,
        StETHModel _stEth
    ) internal {
        _escrowStorageSetup(
            _signallingEscrow,
            _dualGovernance,
            _stEth,
            0 // SignallingEscrow
        );

        vm.assume(_signallingEscrow.rageQuitExtensionDelayPeriodEnd() == 0);
    }

    function _rageQuitEscrowStorageSetup(
        EscrowModel _rageQuitEscrow,
        DualGovernanceModel _dualGovernance,
        StETHModel _stEth
    ) internal {
        _escrowStorageSetup(
            _rageQuitEscrow,
            _dualGovernance,
            _stEth,
            1 // RageQuitEscrow
        );
    }

    function _escrowStorageSetup(
        EscrowModel _escrow,
        DualGovernanceModel _dualGovernance,
        StETHModel _stEth,
        uint8 _currentState
    ) internal {
        kevm.symbolicStorage(address(_escrow));
        // Slot 0: currentState, dualGovernance
        bytes memory slot_0_abi_encoding = abi.encodePacked(uint88(0), address(_dualGovernance), _currentState);
        bytes32 slot_0_for_storage;
        assembly {
            slot_0_for_storage := mload(add(slot_0_abi_encoding, 0x20))
        }
        _storeBytes32(address(_escrow), 0, slot_0_for_storage);
        // Slot 1
        _storeAddress(address(_escrow), 1, address(_stEth));
        // Slot 3
        uint256 totalStakedShares = kevm.freshUInt(32);
        vm.assume(totalStakedShares < ethUpperBound);
        _storeUInt256(address(_escrow), 3, totalStakedShares);
        // Slot 5
        uint256 totalClaimedEthAmount = kevm.freshUInt(32);
        vm.assume(totalClaimedEthAmount <= totalStakedShares);
        _storeUInt256(address(_escrow), 5, totalClaimedEthAmount);
        // Slot 11
        uint256 rageQUitExtensionDelayPeriodEnd = kevm.freshUInt(32);
        _storeUInt256(address(_escrow), 11, rageQUitExtensionDelayPeriodEnd);
    }
}
