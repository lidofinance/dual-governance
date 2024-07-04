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
        uint256 currentState = kevm.freshUInt(32);
        vm.assume(currentState <= 4);
        _storeUInt256(address(_dualGovernance), 11, currentState);
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
        // Slot 0: dualGovernance
        _storeAddress(address(_escrow), 0, address(_dualGovernance));
        // Slot 1: stEth
        _storeAddress(address(_escrow), 1, address(_stEth));
        // Slot 3: totalSharesLocked
        uint256 totalSharesLocked = kevm.freshUInt(32);
        vm.assume(totalSharesLocked < ethUpperBound);
        _storeUInt256(address(_escrow), 3, totalSharesLocked);
        // Slot 4: totalClaimedEthAmount
        uint256 totalClaimedEthAmount = kevm.freshUInt(32);
        vm.assume(totalClaimedEthAmount <= totalSharesLocked);
        _storeUInt256(address(_escrow), 4, totalClaimedEthAmount);
        // Slot 6: withdrawalRequestCount
        uint256 withdrawalRequestCount = kevm.freshUInt(32);
        vm.assume(withdrawalRequestCount < type(uint256).max);
        _storeUInt256(address(_escrow), 6, withdrawalRequestCount);
        // Slot 7: lastWithdrawalRequestSubmitted
        uint256 lastWithdrawalRequestSubmitted = kevm.freshUInt(32);
        vm.assume(lastWithdrawalRequestSubmitted < 2);
        _storeUInt256(address(_escrow), 7, lastWithdrawalRequestSubmitted);
        // Slot 8: claimedWithdrawalRequests
        uint256 claimedWithdrawalRequests = kevm.freshUInt(32);
        vm.assume(claimedWithdrawalRequests < type(uint256).max);
        _storeUInt256(address(_escrow), 8, claimedWithdrawalRequests);
        // Slot 13: rageQuitExtensionDelayPeriodEnd
        uint256 rageQuitExtensionDelayPeriodEnd = kevm.freshUInt(32);
        _storeUInt256(address(_escrow), 13, rageQuitExtensionDelayPeriodEnd);
        // Slot 15: rageQuitEthClaimTimelockStart
        uint256 rageQuitEthClaimTimelockStart = kevm.freshUInt(32);
        vm.assume(rageQuitEthClaimTimelockStart <= block.timestamp);
        vm.assume(rageQuitEthClaimTimelockStart < timeUpperBound);
        _storeUInt256(address(_escrow), 15, rageQuitEthClaimTimelockStart);
        // Slot 16: currentState
        _storeUInt256(address(_escrow), 16, uint256(_currentState));
    }
}
