pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "contracts/model/DualGovernance.sol";
import "contracts/model/EmergencyProtectedTimelock.sol";
import "contracts/model/Escrow.sol";
import "contracts/model/StETH.sol";

contract DualGovernanceSetUp is Test, KontrolCheats {
    DualGovernance dualGovernance;
    EmergencyProtectedTimelock timelock;
    StETH stEth;
    Escrow signallingEscrow;
    Escrow rageQuitEscrow;

    uint256 constant CURRENT_STATE_SLOT = 3;
    uint256 constant CURRENT_STATE_OFFSET = 160;

    // Note: there are lemmas dependent on `ethUpperBound`
    uint256 constant ethMaxWidth = 96;
    uint256 constant ethUpperBound = 2 ** ethMaxWidth;
    uint256 constant timeUpperBound = 2 ** 40;

    enum Mode {
        Assume,
        Assert
    }

    function _establish(Mode mode, bool condition) internal pure {
        if (mode == Mode.Assume) {
            vm.assume(condition);
        } else {
            assert(condition);
        }
    }

    function setUp() public {
        stEth = new StETH();
        uint256 emergencyProtectionTimelock = 0; // Regular deployment mode
        dualGovernance = new DualGovernance(address(stEth), emergencyProtectionTimelock);
        timelock = dualGovernance.emergencyProtectedTimelock();
        signallingEscrow = dualGovernance.signallingEscrow();
        rageQuitEscrow = new Escrow(address(dualGovernance), address(stEth));

        _stEthStorageSetup();
        _dualGovernanceStorageSetup();
        _signallingEscrowStorageSetup();
        _rageQuitEscrowStorageSetup();
        kevm.symbolicStorage(address(timelock)); // ?STORAGE3
    }

    function _stEthStorageSetup() internal {
        kevm.symbolicStorage(address(stEth)); // ?STORAGE
        // Slot 0
        uint256 totalPooledEther = kevm.freshUInt(32); // ?WORD
        vm.assume(0 < totalPooledEther);
        vm.assume(totalPooledEther < ethUpperBound);
        stEth.setTotalPooledEther(totalPooledEther);
        // Slot 1
        uint256 totalShares = kevm.freshUInt(32); // ?WORD0
        vm.assume(0 < totalShares);
        vm.assume(totalShares < ethUpperBound);
        stEth.setTotalShares(totalShares);
        // Slot 2
        uint256 shares = kevm.freshUInt(32); // ?WORD1
        vm.assume(shares < totalShares);
        stEth.setShares(address(signallingEscrow), shares);
    }

    function _dualGovernanceStorageSetup() internal {
        kevm.symbolicStorage(address(dualGovernance)); // ?STORAGE0
        // Slot 0
        _storeAddress(address(dualGovernance), 0, address(timelock));
        // Slot 1
        _storeAddress(address(dualGovernance), 1, address(signallingEscrow));
        // Slot 2
        _storeAddress(address(dualGovernance), 2, address(rageQuitEscrow));
        // Slot 3
        uint8 state = uint8(kevm.freshUInt(1)); // ?WORD2
        vm.assume(state <= 4);
        bytes memory slot_3_abi_encoding = abi.encodePacked(uint88(0), state, address(stEth));
        bytes32 slot_3_for_storage;
        assembly {
            slot_3_for_storage := mload(add(slot_3_abi_encoding, 0x20))
        }
        _storeBytes32(address(dualGovernance), 3, slot_3_for_storage);
        // Slot 6
        uint256 lastStateChangeTime = kevm.freshUInt(32); // ?WORD3
        vm.assume(lastStateChangeTime <= block.timestamp);
        vm.assume(lastStateChangeTime < timeUpperBound);
        _storeUInt256(address(dualGovernance), 6, lastStateChangeTime);
        // Slot 7
        uint256 lastSubStateActivationTime = kevm.freshUInt(32); // ?WORD4
        vm.assume(lastSubStateActivationTime <= block.timestamp);
        vm.assume(lastSubStateActivationTime < timeUpperBound);
        _storeUInt256(address(dualGovernance), 7, lastSubStateActivationTime);
        // Slot 8
        uint256 lastStateReactivationTime = kevm.freshUInt(32); // ?WORD5
        vm.assume(lastStateReactivationTime <= block.timestamp);
        vm.assume(lastStateReactivationTime < timeUpperBound);
        _storeUInt256(address(dualGovernance), 8, lastStateReactivationTime);
        // Slot 9
        uint256 lastVetoSignallingTime = kevm.freshUInt(32); // ?WORD6
        vm.assume(lastVetoSignallingTime <= block.timestamp);
        vm.assume(lastVetoSignallingTime < timeUpperBound);
        _storeUInt256(address(dualGovernance), 9, lastVetoSignallingTime);
        // Slot 10
        uint256 rageQuitSequenceNumber = kevm.freshUInt(32); // ?WORD7
        vm.assume(rageQuitSequenceNumber < type(uint256).max);
        _storeUInt256(address(dualGovernance), 10, rageQuitSequenceNumber);
    }

    function _signallingEscrowStorageSetup() internal {
        kevm.symbolicStorage(address(signallingEscrow)); // ?STORAGE1
        // Slot 0: currentState == 0 (SignallingEscrow), dualGovernance
        uint8 currentState = 0;
        bytes memory slot_0_abi_encoding = abi.encodePacked(uint88(0), address(dualGovernance), currentState);
        bytes32 slot_0_for_storage;
        assembly {
            slot_0_for_storage := mload(add(slot_0_abi_encoding, 0x20))
        }
        _storeBytes32(address(signallingEscrow), 0, slot_0_for_storage);
        // Slot 1
        _storeAddress(address(signallingEscrow), 1, address(stEth));
        // Slot 3
        uint256 totalStakedShares = kevm.freshUInt(32); // ?WORD8
        vm.assume(totalStakedShares < ethUpperBound);
        _storeUInt256(address(signallingEscrow), 3, totalStakedShares);
        // Slot 5
        uint256 totalClaimedEthAmount = kevm.freshUInt(32); // ?WORD9
        vm.assume(totalClaimedEthAmount <= totalStakedShares);
        _storeUInt256(address(signallingEscrow), 5, totalClaimedEthAmount);
        // Slot 11
        uint256 rageQuitExtensionDelayPeriodEnd = 0; // since SignallingEscrow
        _storeUInt256(address(signallingEscrow), 11, rageQuitExtensionDelayPeriodEnd);
    }

    function _rageQuitEscrowStorageSetup() internal {
        kevm.symbolicStorage(address(rageQuitEscrow)); // ?STORAGE2
        // Slot 0: currentState == 1 (RageQuitEscrow), dualGovernance
        uint8 currentState = 1;
        bytes memory slot_0_abi_encoding = abi.encodePacked(uint88(0), address(dualGovernance), currentState);
        bytes32 slot_0_for_storage;
        assembly {
            slot_0_for_storage := mload(add(slot_0_abi_encoding, 0x20))
        }
        _storeBytes32(address(rageQuitEscrow), 0, slot_0_for_storage);
        // Slot 1
        _storeAddress(address(rageQuitEscrow), 1, address(stEth));
        // Slot 3
        uint256 totalStakedShares = kevm.freshUInt(32); // ?WORD10
        vm.assume(totalStakedShares < ethUpperBound);
        _storeUInt256(address(rageQuitEscrow), 3, totalStakedShares);
        // Slot 5
        uint256 totalClaimedEthAmount = kevm.freshUInt(32); // ?WORD11
        vm.assume(totalClaimedEthAmount <= totalStakedShares);
        _storeUInt256(address(rageQuitEscrow), 5, totalClaimedEthAmount);
        // Slot 11
        uint256 rageQUitExtensionDelayPeriodEnd = kevm.freshUInt(32); // ?WORD12
        _storeUInt256(address(rageQuitEscrow), 11, rageQUitExtensionDelayPeriodEnd);
    }

    function _storeBytes32(address contractAddress, uint256 slot, bytes32 value) internal {
        vm.store(contractAddress, bytes32(slot), value);
    }

    function _storeUInt256(address contractAddress, uint256 slot, uint256 value) internal {
        vm.store(contractAddress, bytes32(slot), bytes32(value));
    }

    function _storeAddress(address contractAddress, uint256 slot, address value) internal {
        vm.store(contractAddress, bytes32(slot), bytes32(uint256(uint160(value))));
    }
}
