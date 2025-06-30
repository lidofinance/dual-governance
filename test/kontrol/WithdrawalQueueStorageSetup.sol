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

contract WithdrawalQueueStorageSetup is KontrolTest {
    //
    //  STORAGE CONSTANTS
    //
    uint256 constant LASTREQUESTID_SLOT = WithdrawalQueueStorageConstants.STORAGE_LASTREQUESTID_SLOT;
    uint256 constant LASTREQUESTID_OFFSET = WithdrawalQueueStorageConstants.STORAGE_LASTREQUESTID_OFFSET;
    uint256 constant LASTREQUESTID_SIZE = WithdrawalQueueStorageConstants.STORAGE_LASTREQUESTID_SIZE;
    uint256 constant LASTFINALIZEDREQUESTID_SLOT = WithdrawalQueueStorageConstants.STORAGE_LASTFINALIZEDREQUESTID_SLOT;
    uint256 constant LASTFINALIZEDREQUESTID_OFFSET =
        WithdrawalQueueStorageConstants.STORAGE_LASTFINALIZEDREQUESTID_OFFSET;
    uint256 constant LASTFINALIZEDREQUESTID_SIZE = WithdrawalQueueStorageConstants.STORAGE_LASTFINALIZEDREQUESTID_SIZE;
    uint256 constant LOCKEDETHERAMOUNT_SLOT = WithdrawalQueueStorageConstants.STORAGE_LOCKEDETHERAMOUNT_SLOT;
    uint256 constant LOCKEDETHERAMOUNT_OFFSET = WithdrawalQueueStorageConstants.STORAGE_LOCKEDETHERAMOUNT_OFFSET;
    uint256 constant LOCKEDETHERAMOUNT_SIZE = WithdrawalQueueStorageConstants.STORAGE_LOCKEDETHERAMOUNT_SIZE;
    uint256 constant REQUESTS_SLOT = WithdrawalQueueStorageConstants.STORAGE_REQUESTS_SLOT;
    uint256 constant ISCLAIMED_SLOT =
        WithdrawalQueueStorageConstants.STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_ISCLAIMED_SLOT;
    uint256 constant ISCLAIMED_OFFSET =
        WithdrawalQueueStorageConstants.STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_ISCLAIMED_OFFSET;
    uint256 constant ISCLAIMED_SIZE =
        WithdrawalQueueStorageConstants.STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_ISCLAIMED_SIZE;
    uint256 constant OWNER_SLOT =
        WithdrawalQueueStorageConstants.STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_OWNER_SLOT;
    uint256 constant OWNER_OFFSET =
        WithdrawalQueueStorageConstants.STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_OWNER_OFFSET;
    uint256 constant OWNER_SIZE =
        WithdrawalQueueStorageConstants.STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_OWNER_SIZE;

    //
    //  GETTERS
    //
    function _getLastRequestId(WithdrawalQueueModel _withdrawalQueue) internal view returns (uint256) {
        return _loadData(address(_withdrawalQueue), LASTREQUESTID_SLOT, LASTREQUESTID_OFFSET, LASTREQUESTID_SIZE);
    }

    function _getLastFinalizedRequestId(WithdrawalQueueModel _withdrawalQueue) internal view returns (uint256) {
        return _loadData(
            address(_withdrawalQueue),
            LASTFINALIZEDREQUESTID_SLOT,
            LASTFINALIZEDREQUESTID_OFFSET,
            LASTFINALIZEDREQUESTID_SIZE
        );
    }

    function _getRequestIsClaimed(WithdrawalQueueModel _withdrawalQueue, uint256 _requestId) internal returns (bool) {
        return 0
            != _loadMappingData(
                address(_withdrawalQueue), REQUESTS_SLOT, _requestId, ISCLAIMED_SLOT, ISCLAIMED_OFFSET, ISCLAIMED_SIZE
            );
    }

    function _getRequestOwner(WithdrawalQueueModel _withdrawalQueue, uint256 _requestId) internal returns (address) {
        return address(
            uint160(
                _loadMappingData(
                    address(_withdrawalQueue), REQUESTS_SLOT, _requestId, OWNER_SLOT, OWNER_OFFSET, OWNER_SIZE
                )
            )
        );
    }

    //
    //  STORAGE SETUP
    //
    function withdrawalQueueStorageSetup(
        WithdrawalQueueModel _withdrawalQueue,
        IStETH _stEth,
        IEscrowBase _escrow
    ) external {
        kevm.symbolicStorage(address(_withdrawalQueue));

        uint256 lastRequestId = freshUInt256("WQ_lastRequestId");
        // If we assume that request IDs increase sequentially, it's unlikely tha they will reach this high
        vm.assume(lastRequestId < 2 ** 64);

        _storeData(
            address(_withdrawalQueue), LASTREQUESTID_SLOT, LASTREQUESTID_OFFSET, LASTREQUESTID_SIZE, lastRequestId
        );

        uint256 lastFinalizedRequestId = freshUInt256("WQ_lastFinalizedRequestId");
        _storeData(
            address(_withdrawalQueue),
            LASTFINALIZEDREQUESTID_SLOT,
            LASTFINALIZEDREQUESTID_OFFSET,
            LASTFINALIZEDREQUESTID_SIZE,
            lastFinalizedRequestId
        );

        uint256 lockedEtherAmount = freshUInt256("WQ_lockedEtherAmount");
        _storeData(
            address(_withdrawalQueue),
            LOCKEDETHERAMOUNT_SLOT,
            LOCKEDETHERAMOUNT_OFFSET,
            LOCKEDETHERAMOUNT_SIZE,
            lockedEtherAmount
        );
        vm.deal(address(_withdrawalQueue), lockedEtherAmount);
    }

    function withdrawalQueueRequestSetup(WithdrawalQueueModel _withdrawalQueue, uint256 _requestId) external {
        uint256 isClaimed = freshUInt8("WQ_isClaimed");
        _storeMappingData(
            address(_withdrawalQueue),
            REQUESTS_SLOT,
            _requestId,
            ISCLAIMED_SLOT,
            ISCLAIMED_OFFSET,
            ISCLAIMED_SIZE,
            isClaimed
        );

        uint256 owner = freshUInt160("WQ_requestOwner");
        _storeMappingData(
            address(_withdrawalQueue), REQUESTS_SLOT, _requestId, OWNER_SLOT, OWNER_OFFSET, OWNER_SIZE, owner
        );
    }
}
