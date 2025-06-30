pragma solidity 0.8.26;

import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import {Escrow} from "contracts/Escrow.sol";

import {SharesValue} from "contracts/types/SharesValue.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";
import {State as WithdrawalsBatchesQueueState} from "contracts/libraries/WithdrawalsBatchesQueue.sol";
import {State as EscrowSt} from "contracts/libraries/EscrowState.sol";

import "test/kontrol/model/StETHModel.sol";
import "test/kontrol/model/WithdrawalQueueModel.sol";
import "test/kontrol/model/WstETHAdapted.sol";

import "test/kontrol/KontrolTest.sol";
import "test/kontrol/storage/DualGovernanceStorageConstants.sol";
import "test/kontrol/storage/EscrowStorageConstants.sol";
import "test/kontrol/storage/WithdrawalQueueStorageConstants.sol";

contract DualGovernanceStorageSetup is KontrolTest {
    //
    //  STORAGE CONSTANTS
    //
    uint256 constant STATE_SLOT = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_STATE_SLOT;
    uint256 constant STATE_OFFSET = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_STATE_OFFSET;
    uint256 constant STATE_SIZE = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_STATE_SIZE;
    uint256 constant ENTEREDAT_SLOT = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_ENTEREDAT_SLOT;
    uint256 constant ENTEREDAT_OFFSET = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_ENTEREDAT_OFFSET;
    uint256 constant ENTEREDAT_SIZE = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_ENTEREDAT_SIZE;
    uint256 constant ACTIVATEDAT_SLOT =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_VETOSIGNALLINGACTIVATEDAT_SLOT;
    uint256 constant ACTIVATEDAT_OFFSET =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_VETOSIGNALLINGACTIVATEDAT_OFFSET;
    uint256 constant ACTIVATEDAT_SIZE =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_VETOSIGNALLINGACTIVATEDAT_SIZE;
    uint256 constant RAGEQUITROUND_SLOT = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_RAGEQUITROUND_SLOT;
    uint256 constant RAGEQUITROUND_OFFSET = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_RAGEQUITROUND_OFFSET;
    uint256 constant RAGEQUITROUND_SIZE = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_RAGEQUITROUND_SIZE;
    uint256 constant REACTIVATIONTIME_SLOT =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_VETOSIGNALLINGREACTIVATIONTIME_SLOT;
    uint256 constant REACTIVATIONTIME_OFFSET =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_VETOSIGNALLINGREACTIVATIONTIME_OFFSET;
    uint256 constant REACTIVATIONTIME_SIZE =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_VETOSIGNALLINGREACTIVATIONTIME_SIZE;
    uint256 constant EXITEDAT_SLOT =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_NORMALORVETOCOOLDOWNEXITEDAT_SLOT;
    uint256 constant EXITEDAT_OFFSET =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_NORMALORVETOCOOLDOWNEXITEDAT_OFFSET;
    uint256 constant EXITEDAT_SIZE =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_NORMALORVETOCOOLDOWNEXITEDAT_SIZE;
    uint256 constant SIGNALLINGESCROW_SLOT = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_SIGNALLINGESCROW_SLOT;
    uint256 constant SIGNALLINGESCROW_OFFSET =
        DualGovernanceStorageConstants.STORAGE_STATEMACHINE_SIGNALLINGESCROW_OFFSET;
    uint256 constant SIGNALLINGESCROW_SIZE = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_SIGNALLINGESCROW_SIZE;
    uint256 constant RAGEQUITESCROW_SLOT = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_RAGEQUITESCROW_SLOT;
    uint256 constant RAGEQUITESCROW_OFFSET = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_RAGEQUITESCROW_OFFSET;
    uint256 constant RAGEQUITESCROW_SIZE = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_RAGEQUITESCROW_SIZE;
    uint256 constant CONFIGPROVIDER_SLOT = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_CONFIGPROVIDER_SLOT;
    uint256 constant CONFIGPROVIDER_OFFSET = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_CONFIGPROVIDER_OFFSET;
    uint256 constant CONFIGPROVIDER_SIZE = DualGovernanceStorageConstants.STORAGE_STATEMACHINE_CONFIGPROVIDER_SIZE;
    uint256 constant PROPOSALSCANCELLER_SLOT = DualGovernanceStorageConstants.STORAGE_PROPOSALSCANCELLER_SLOT;
    uint256 constant PROPOSALSCANCELLER_OFFSET = DualGovernanceStorageConstants.STORAGE_PROPOSALSCANCELLER_OFFSET;
    uint256 constant PROPOSALSCANCELLER_SIZE = DualGovernanceStorageConstants.STORAGE_PROPOSALSCANCELLER_SIZE;

    //
    //  GETTERS
    //
    function _getCurrentState(DualGovernance _dualGovernance) internal view returns (uint8) {
        return uint8(_loadData(address(_dualGovernance), STATE_SLOT, STATE_OFFSET, STATE_SIZE));
    }

    function _getEnteredAt(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadData(address(_dualGovernance), ENTEREDAT_SLOT, ENTEREDAT_OFFSET, ENTEREDAT_SIZE));
    }

    function _getVetoSignallingActivationTime(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadData(address(_dualGovernance), ACTIVATEDAT_SLOT, ACTIVATEDAT_OFFSET, ACTIVATEDAT_SIZE));
    }

    function _getRageQuitRound(DualGovernance _dualGovernance) internal view returns (uint8) {
        return uint8(_loadData(address(_dualGovernance), RAGEQUITROUND_SLOT, RAGEQUITROUND_OFFSET, RAGEQUITROUND_SIZE));
    }

    function _getVetoSignallingReactivationTime(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(
            _loadData(address(_dualGovernance), REACTIVATIONTIME_SLOT, REACTIVATIONTIME_OFFSET, REACTIVATIONTIME_SIZE)
        );
    }

    function _getNormalOrVetoCooldownExitedAt(DualGovernance _dualGovernance) internal view returns (uint40) {
        return uint40(_loadData(address(_dualGovernance), EXITEDAT_SLOT, EXITEDAT_OFFSET, EXITEDAT_SIZE));
    }

    //
    //  STORAGE SETUP
    //
    function dualGovernanceStorageSetup(
        DualGovernance _dualGovernance,
        IEscrowBase _signallingEscrow,
        IEscrowBase _rageQuitEscrow,
        IDualGovernanceConfigProvider _config
    ) external {
        kevm.symbolicStorage(address(_dualGovernance));

        _clearSlot(address(_dualGovernance), STATE_SLOT);
        _clearSlot(address(_dualGovernance), REACTIVATIONTIME_SLOT);
        _clearSlot(address(_dualGovernance), CONFIGPROVIDER_SLOT);

        uint256 currentState = freshUInt256("DG_state");
        vm.assume(currentState != 0); // Cannot be Unset as dual governance was initialised
        vm.assume(currentState <= 5);
        uint256 enteredAt = freshUInt256("DG_enteredAt");
        vm.assume(enteredAt <= block.timestamp);
        vm.assume(enteredAt < timeUpperBound);
        uint256 vetoSignallingActivationTime = freshUInt256("DG_vsActivationTime");
        vm.assume(vetoSignallingActivationTime <= block.timestamp);
        vm.assume(vetoSignallingActivationTime < timeUpperBound);
        uint256 rageQuitRound = freshUInt256("DG_rageQuitRound");
        vm.assume(rageQuitRound < type(uint8).max);

        _storeData(address(_dualGovernance), STATE_SLOT, STATE_OFFSET, STATE_SIZE, currentState);
        _storeData(address(_dualGovernance), ENTEREDAT_SLOT, ENTEREDAT_OFFSET, ENTEREDAT_SIZE, enteredAt);
        _storeData(
            address(_dualGovernance),
            ACTIVATEDAT_SLOT,
            ACTIVATEDAT_OFFSET,
            ACTIVATEDAT_SIZE,
            vetoSignallingActivationTime
        );
        _storeData(
            address(_dualGovernance),
            SIGNALLINGESCROW_SLOT,
            SIGNALLINGESCROW_OFFSET,
            SIGNALLINGESCROW_SIZE,
            uint256(uint160(address(_signallingEscrow)))
        );
        _storeData(
            address(_dualGovernance), RAGEQUITROUND_SLOT, RAGEQUITROUND_OFFSET, RAGEQUITROUND_SIZE, rageQuitRound
        );

        uint256 vetoSignallingReactivationTime = freshUInt256("DG_vsReactivationTime");
        vm.assume(vetoSignallingReactivationTime <= block.timestamp);
        vm.assume(vetoSignallingReactivationTime < timeUpperBound);
        uint256 normalOrVetoCooldownExitedAt = freshUInt256("DG_normalOrVCExitedAt");
        vm.assume(normalOrVetoCooldownExitedAt <= block.timestamp);
        vm.assume(normalOrVetoCooldownExitedAt < timeUpperBound);

        _storeData(
            address(_dualGovernance),
            REACTIVATIONTIME_SLOT,
            REACTIVATIONTIME_OFFSET,
            REACTIVATIONTIME_SIZE,
            vetoSignallingReactivationTime
        );
        _storeData(
            address(_dualGovernance), EXITEDAT_SLOT, EXITEDAT_OFFSET, EXITEDAT_SIZE, normalOrVetoCooldownExitedAt
        );
        _storeData(
            address(_dualGovernance),
            RAGEQUITESCROW_SLOT,
            RAGEQUITESCROW_OFFSET,
            RAGEQUITESCROW_SIZE,
            uint256(uint160(address(_rageQuitEscrow)))
        );

        _storeData(
            address(_dualGovernance),
            CONFIGPROVIDER_SLOT,
            CONFIGPROVIDER_OFFSET,
            CONFIGPROVIDER_SIZE,
            uint256(uint160(address(_config)))
        );

        address proposalsCanceller = kevm.freshAddress("DG_PROPOSALSCANCELER");
        _storeData(
            address(_dualGovernance),
            PROPOSALSCANCELLER_SLOT,
            PROPOSALSCANCELLER_OFFSET,
            PROPOSALSCANCELLER_SIZE,
            uint256(uint160(proposalsCanceller))
        );
    }

    function dualGovernanceStorageInvariants(Mode mode, DualGovernance _dualGovernance) external {
        uint8 currentState = _getCurrentState(_dualGovernance);
        uint40 enteredAt = _getEnteredAt(_dualGovernance);
        uint40 vetoSignallingActivationTime = _getVetoSignallingActivationTime(_dualGovernance);
        uint40 vetoSignallingReactivationTime = _getVetoSignallingReactivationTime(_dualGovernance);
        uint40 normalOrVetoCooldownExitedAt = _getNormalOrVetoCooldownExitedAt(_dualGovernance);
        uint8 rageQuitRound = _getRageQuitRound(_dualGovernance);

        _establish(mode, currentState <= 5);
        _establish(mode, enteredAt <= block.timestamp);
        _establish(mode, vetoSignallingActivationTime <= block.timestamp);
        _establish(mode, vetoSignallingReactivationTime <= block.timestamp);
        _establish(mode, normalOrVetoCooldownExitedAt <= block.timestamp);
    }

    function dualGovernanceAssumeBounds(DualGovernance _dualGovernance) external {
        uint40 enteredAt = _getEnteredAt(_dualGovernance);
        uint40 vetoSignallingActivationTime = _getVetoSignallingActivationTime(_dualGovernance);
        uint40 vetoSignallingReactivationTime = _getVetoSignallingReactivationTime(_dualGovernance);
        uint40 normalOrVetoCooldownExitedAt = _getNormalOrVetoCooldownExitedAt(_dualGovernance);
        uint8 rageQuitRound = _getRageQuitRound(_dualGovernance);

        vm.assume(enteredAt < timeUpperBound);
        vm.assume(vetoSignallingActivationTime < timeUpperBound);
        vm.assume(vetoSignallingReactivationTime < timeUpperBound);
        vm.assume(normalOrVetoCooldownExitedAt < timeUpperBound);
        vm.assume(rageQuitRound < type(uint8).max);
    }

    function dualGovernanceInitializeStorage(
        DualGovernance _dualGovernance,
        IEscrowBase _signallingEscrow,
        IEscrowBase _rageQuitEscrow,
        IDualGovernanceConfigProvider _config
    ) external {
        this.dualGovernanceStorageSetup(_dualGovernance, _signallingEscrow, _rageQuitEscrow, _config);
        this.dualGovernanceStorageInvariants(Mode.Assume, _dualGovernance);
        this.dualGovernanceAssumeBounds(_dualGovernance);
    }
}
