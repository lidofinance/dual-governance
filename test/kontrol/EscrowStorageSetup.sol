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

contract EscrowStorageSetup is KontrolTest {
    //
    //  STORAGE CONSTANTS
    //
    uint256 constant ESCROWSTATE_SLOT = EscrowStorageConstants.STORAGE_ESCROWSTATE_STATE_SLOT;
    uint256 constant ESCROWSTATE_OFFSET = EscrowStorageConstants.STORAGE_ESCROWSTATE_STATE_OFFSET;
    uint256 constant ESCROWSTATE_SIZE = EscrowStorageConstants.STORAGE_ESCROWSTATE_STATE_SIZE;
    uint256 constant MINLOCKDURATION_SLOT = EscrowStorageConstants.STORAGE_ESCROWSTATE_MINASSETSLOCKDURATION_SLOT;
    uint256 constant MINLOCKDURATION_OFFSET = EscrowStorageConstants.STORAGE_ESCROWSTATE_MINASSETSLOCKDURATION_OFFSET;
    uint256 constant MINLOCKDURATION_SIZE = EscrowStorageConstants.STORAGE_ESCROWSTATE_MINASSETSLOCKDURATION_SIZE;
    uint256 constant EXTENSIONDURATION_SLOT =
        EscrowStorageConstants.STORAGE_ESCROWSTATE_RAGEQUITEXTENSIONPERIODDURATION_SLOT;
    uint256 constant EXTENSIONDURATION_OFFSET =
        EscrowStorageConstants.STORAGE_ESCROWSTATE_RAGEQUITEXTENSIONPERIODDURATION_OFFSET;
    uint256 constant EXTENSIONDURATION_SIZE =
        EscrowStorageConstants.STORAGE_ESCROWSTATE_RAGEQUITEXTENSIONPERIODDURATION_SIZE;
    uint256 constant EXTENSIONSTARTEDAT_SLOT =
        EscrowStorageConstants.STORAGE_ESCROWSTATE_RAGEQUITEXTENSIONPERIODSTARTEDAT_SLOT;
    uint256 constant EXTENSIONSTARTEDAT_OFFSET =
        EscrowStorageConstants.STORAGE_ESCROWSTATE_RAGEQUITEXTENSIONPERIODSTARTEDAT_OFFSET;
    uint256 constant EXTENSIONSTARTEDAT_SIZE =
        EscrowStorageConstants.STORAGE_ESCROWSTATE_RAGEQUITEXTENSIONPERIODSTARTEDAT_SIZE;
    uint256 constant WITHDRAWALSDELAY_SLOT = EscrowStorageConstants.STORAGE_ESCROWSTATE_RAGEQUITETHWITHDRAWALSDELAY_SLOT;
    uint256 constant WITHDRAWALSDELAY_OFFSET =
        EscrowStorageConstants.STORAGE_ESCROWSTATE_RAGEQUITETHWITHDRAWALSDELAY_OFFSET;
    uint256 constant WITHDRAWALSDELAY_SIZE = EscrowStorageConstants.STORAGE_ESCROWSTATE_RAGEQUITETHWITHDRAWALSDELAY_SIZE;
    uint256 constant LOCKEDSHARES_SLOT = EscrowStorageConstants.STORAGE_ACCOUNTING_STETHTOTALS_LOCKEDSHARES_SLOT;
    uint256 constant LOCKEDSHARES_OFFSET = EscrowStorageConstants.STORAGE_ACCOUNTING_STETHTOTALS_LOCKEDSHARES_OFFSET;
    uint256 constant LOCKEDSHARES_SIZE = EscrowStorageConstants.STORAGE_ACCOUNTING_STETHTOTALS_LOCKEDSHARES_SIZE;
    uint256 constant CLAIMEDETH_SLOT = EscrowStorageConstants.STORAGE_ACCOUNTING_STETHTOTALS_CLAIMEDETH_SLOT;
    uint256 constant CLAIMEDETH_OFFSET = EscrowStorageConstants.STORAGE_ACCOUNTING_STETHTOTALS_CLAIMEDETH_OFFSET;
    uint256 constant CLAIMEDETH_SIZE = EscrowStorageConstants.STORAGE_ACCOUNTING_STETHTOTALS_CLAIMEDETH_SIZE;
    uint256 constant UNFINALIZEDSHARES_SLOT =
        EscrowStorageConstants.STORAGE_ACCOUNTING_UNSTETHTOTALS_UNFINALIZEDSHARES_SLOT;
    uint256 constant UNFINALIZEDSHARES_OFFSET =
        EscrowStorageConstants.STORAGE_ACCOUNTING_UNSTETHTOTALS_UNFINALIZEDSHARES_OFFSET;
    uint256 constant UNFINALIZEDSHARES_SIZE =
        EscrowStorageConstants.STORAGE_ACCOUNTING_UNSTETHTOTALS_UNFINALIZEDSHARES_SIZE;
    uint256 constant FINALIZEDETH_SLOT = EscrowStorageConstants.STORAGE_ACCOUNTING_UNSTETHTOTALS_FINALIZEDETH_SLOT;
    uint256 constant FINALIZEDETH_OFFSET = EscrowStorageConstants.STORAGE_ACCOUNTING_UNSTETHTOTALS_FINALIZEDETH_OFFSET;
    uint256 constant FINALIZEDETH_SIZE = EscrowStorageConstants.STORAGE_ACCOUNTING_UNSTETHTOTALS_FINALIZEDETH_SIZE;
    uint256 constant ASSETS_SLOT = EscrowStorageConstants.STORAGE_ACCOUNTING_ASSETS_SLOT;
    uint256 constant LASTASSETSLOCK_SLOT = EscrowStorageConstants.STRUCT_HOLDERASSETS_LASTASSETSLOCKTIMESTAMP_SLOT;
    uint256 constant LASTASSETSLOCK_OFFSET = EscrowStorageConstants.STRUCT_HOLDERASSETS_LASTASSETSLOCKTIMESTAMP_OFFSET;
    uint256 constant LASTASSETSLOCK_SIZE = EscrowStorageConstants.STRUCT_HOLDERASSETS_LASTASSETSLOCKTIMESTAMP_SIZE;
    uint256 constant STETHSHARES_SLOT = EscrowStorageConstants.STRUCT_HOLDERASSETS_STETHLOCKEDSHARES_SLOT;
    uint256 constant STETHSHARES_OFFSET = EscrowStorageConstants.STRUCT_HOLDERASSETS_STETHLOCKEDSHARES_OFFSET;
    uint256 constant STETHSHARES_SIZE = EscrowStorageConstants.STRUCT_HOLDERASSETS_STETHLOCKEDSHARES_SIZE;
    uint256 constant UNSTETHSHARES_SLOT = EscrowStorageConstants.STRUCT_HOLDERASSETS_UNSTETHLOCKEDSHARES_SLOT;
    uint256 constant UNSTETHSHARES_OFFSET = EscrowStorageConstants.STRUCT_HOLDERASSETS_UNSTETHLOCKEDSHARES_OFFSET;
    uint256 constant UNSTETHSHARES_SIZE = EscrowStorageConstants.STRUCT_HOLDERASSETS_UNSTETHLOCKEDSHARES_SIZE;
    uint256 constant UNSTETHIDSLENGTH_SLOT = EscrowStorageConstants.STRUCT_HOLDERASSETS_UNSTETHIDS_SLOT;
    uint256 constant UNSTETHIDSLENGTH_OFFSET = EscrowStorageConstants.STRUCT_HOLDERASSETS_UNSTETHIDS_OFFSET;
    uint256 constant UNSTETHIDSLENGTH_SIZE = EscrowStorageConstants.STRUCT_HOLDERASSETS_UNSTETHIDS_SIZE;
    uint256 constant BATCHESLENGTH_SLOT = EscrowStorageConstants.STORAGE_BATCHESQUEUE_BATCHES_SLOT;
    uint256 constant BATCHESLENGTH_OFFSET = EscrowStorageConstants.STORAGE_BATCHESQUEUE_BATCHES_OFFSET;
    uint256 constant BATCHESLENGTH_SIZE = EscrowStorageConstants.STORAGE_BATCHESQUEUE_BATCHES_SIZE;
    uint256 constant BATCHESQUEUESTATE_SLOT = EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_STATE_SLOT;
    uint256 constant BATCHESQUEUESTATE_OFFSET = EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_STATE_OFFSET;
    uint256 constant BATCHESQUEUESTATE_SIZE = EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_STATE_SIZE;
    uint256 constant TOTALUNSTETHIDSCOUNT_SLOT =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_TOTALUNSTETHIDSCOUNT_SLOT;
    uint256 constant TOTALUNSTETHIDSCOUNT_OFFSET =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_TOTALUNSTETHIDSCOUNT_OFFSET;
    uint256 constant TOTALUNSTETHIDSCOUNT_SIZE =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_TOTALUNSTETHIDSCOUNT_SIZE;
    uint256 constant TOTALUNSTETHIDSCLAIMED_SLOT =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_TOTALUNSTETHIDSCLAIMED_SLOT;
    uint256 constant TOTALUNSTETHIDSCLAIMED_OFFSET =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_TOTALUNSTETHIDSCLAIMED_OFFSET;
    uint256 constant TOTALUNSTETHIDSCLAIMED_SIZE =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_TOTALUNSTETHIDSCLAIMED_SIZE;
    uint256 constant LASTCLAIMEDBATCHINDEX_SLOT =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_LASTCLAIMEDBATCHINDEX_SLOT;
    uint256 constant LASTCLAIMEDBATCHINDEX_OFFSET =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_LASTCLAIMEDBATCHINDEX_OFFSET;
    uint256 constant LASTCLAIMEDBATCHINDEX_SIZE =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_LASTCLAIMEDBATCHINDEX_SIZE;
    uint256 constant LASTCLAIMEDUNSTETHIDINDEX_SLOT =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_LASTCLAIMEDUNSTETHIDINDEX_SLOT;
    uint256 constant LASTCLAIMEDUNSTETHIDINDEX_OFFSET =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_LASTCLAIMEDUNSTETHIDINDEX_OFFSET;
    uint256 constant LASTCLAIMEDUNSTETHIDINDEX_SIZE =
        EscrowStorageConstants.STORAGE_BATCHESQUEUE_INFO_LASTCLAIMEDUNSTETHIDINDEX_SIZE;
    uint256 constant SEQUENTIALBATCH_SIZE = EscrowStorageConstants.STRUCT_WITHDRAWALSBATCHESQUEUE_SEQUENTIALBATCH_SIZE;
    uint256 constant FIRSTUNSTETHID_SLOT =
        EscrowStorageConstants.STRUCT_WITHDRAWALSBATCHESQUEUE_SEQUENTIALBATCH_FIRSTUNSTETHID_SLOT;
    uint256 constant FIRSTUNSTETHID_OFFSET =
        EscrowStorageConstants.STRUCT_WITHDRAWALSBATCHESQUEUE_SEQUENTIALBATCH_FIRSTUNSTETHID_OFFSET;
    uint256 constant FIRSTUNSTETHID_SIZE =
        EscrowStorageConstants.STRUCT_WITHDRAWALSBATCHESQUEUE_SEQUENTIALBATCH_FIRSTUNSTETHID_SIZE;
    uint256 constant LASTUNSTETHID_SLOT =
        EscrowStorageConstants.STRUCT_WITHDRAWALSBATCHESQUEUE_SEQUENTIALBATCH_LASTUNSTETHID_SLOT;
    uint256 constant LASTUNSTETHID_OFFSET =
        EscrowStorageConstants.STRUCT_WITHDRAWALSBATCHESQUEUE_SEQUENTIALBATCH_LASTUNSTETHID_OFFSET;
    uint256 constant LASTUNSTETHID_SIZE =
        EscrowStorageConstants.STRUCT_WITHDRAWALSBATCHESQUEUE_SEQUENTIALBATCH_LASTUNSTETHID_SIZE;
    uint256 constant UNSTETHRECORDS_SLOT = EscrowStorageConstants.STORAGE_ACCOUNTING_UNSTETHRECORDS_SLOT;
    uint256 constant UNSTETHRECORDSTATUS_SLOT = EscrowStorageConstants.STRUCT_UNSTETHRECORD_STATUS_SLOT;
    uint256 constant UNSTETHRECORDSTATUS_OFFSET = EscrowStorageConstants.STRUCT_UNSTETHRECORD_STATUS_OFFSET;
    uint256 constant UNSTETHRECORDSTATUS_SIZE = EscrowStorageConstants.STRUCT_UNSTETHRECORD_STATUS_SIZE;

    //
    //  GETTERS
    //
    function _getCurrentState(IEscrowBase _escrow) internal view returns (uint8) {
        return uint8(_loadData(address(_escrow), ESCROWSTATE_SLOT, ESCROWSTATE_OFFSET, ESCROWSTATE_SIZE));
    }

    function _getMinAssetsLockDuration(IEscrowBase _escrow) internal view returns (uint32) {
        return uint32(_loadData(address(_escrow), MINLOCKDURATION_SLOT, MINLOCKDURATION_OFFSET, MINLOCKDURATION_SIZE));
    }

    function _getRageQuitExtensionPeriodDuration(IEscrowBase _escrow) internal view returns (uint32) {
        return uint32(
            _loadData(address(_escrow), EXTENSIONDURATION_SLOT, EXTENSIONDURATION_OFFSET, EXTENSIONDURATION_SIZE)
        );
    }

    function _getRageQuitExtensionPeriodStartedAt(IEscrowBase _escrow) internal view returns (uint40) {
        return uint40(
            _loadData(address(_escrow), EXTENSIONSTARTEDAT_SLOT, EXTENSIONSTARTEDAT_OFFSET, EXTENSIONSTARTEDAT_SIZE)
        );
    }

    function _getRageQuitEthWithdrawalsDelay(IEscrowBase _escrow) internal view returns (uint32) {
        return
            uint32(_loadData(address(_escrow), WITHDRAWALSDELAY_SLOT, WITHDRAWALSDELAY_OFFSET, WITHDRAWALSDELAY_SIZE));
    }

    function _getTotalStEthLockedShares(IEscrowBase _escrow) internal view returns (uint128) {
        return uint128(_loadData(address(_escrow), LOCKEDSHARES_SLOT, LOCKEDSHARES_OFFSET, LOCKEDSHARES_SIZE));
    }

    function _getClaimedEth(IEscrowBase _escrow) internal view returns (uint128) {
        return uint128(_loadData(address(_escrow), CLAIMEDETH_SLOT, CLAIMEDETH_OFFSET, CLAIMEDETH_SIZE));
    }

    function _getUnfinalizedShares(IEscrowBase _escrow) internal view returns (uint128) {
        return uint128(
            _loadData(address(_escrow), UNFINALIZEDSHARES_SLOT, UNFINALIZEDSHARES_OFFSET, UNFINALIZEDSHARES_SIZE)
        );
    }

    function _getFinalizedEth(IEscrowBase _escrow) internal view returns (uint128) {
        return uint128(_loadData(address(_escrow), FINALIZEDETH_SLOT, FINALIZEDETH_OFFSET, FINALIZEDETH_SIZE));
    }

    function _getLastAssetsLockTimestamp(IEscrowBase _escrow, address _vetoer) internal view returns (uint40) {
        uint256 key = uint256(uint160(_vetoer));
        return uint40(
            _loadMappingData(
                address(_escrow), ASSETS_SLOT, key, LASTASSETSLOCK_SLOT, LASTASSETSLOCK_OFFSET, LASTASSETSLOCK_SIZE
            )
        );
    }

    function _getStEthLockedShares(IEscrowBase _escrow, address _vetoer) internal view returns (uint128) {
        uint256 key = uint256(uint160(_vetoer));
        return uint128(
            _loadMappingData(address(_escrow), ASSETS_SLOT, key, STETHSHARES_SLOT, STETHSHARES_OFFSET, STETHSHARES_SIZE)
        );
    }

    function _getBatchesQueueStatus(IEscrowBase _escrow) internal view returns (uint8) {
        return
            uint8(_loadData(address(_escrow), BATCHESQUEUESTATE_SLOT, BATCHESQUEUESTATE_OFFSET, BATCHESQUEUESTATE_SIZE));
    }

    function _getBatchesLength(IEscrowBase _escrow) internal view returns (uint256) {
        return _loadData(address(_escrow), BATCHESLENGTH_SLOT, BATCHESLENGTH_OFFSET, BATCHESLENGTH_SIZE);
    }

    function _getLastClaimedBatchSlot(IEscrowBase _escrow) internal view returns (uint256) {
        return _getBatchSlot(_escrow, _getLastClaimedBatchIndex(_escrow));
    }

    function _getLastWithdrawalsBatchSlot(IEscrowBase _escrow) internal view returns (uint256) {
        return _getBatchSlot(_escrow, _getBatchesLength(_escrow) - 1);
    }

    function _getBatchSlot(IEscrowBase _escrow, uint256 _batchIndex) internal view returns (uint256) {
        uint256 batchesDataSlot = uint256(keccak256(abi.encode(BATCHESLENGTH_SLOT)));
        // Divide by 32 to get number of slots SequentialBatch struct occupies
        uint256 batchStructSize = SEQUENTIALBATCH_SIZE / 32;
        return batchesDataSlot + batchStructSize * _batchIndex;
    }

    function _getFirstUnstEthId(IEscrowBase _escrow, uint256 _batchIndex) internal view returns (uint256) {
        uint256 batchSlot = _getBatchSlot(_escrow, _batchIndex);
        return _loadData(address(_escrow), batchSlot + FIRSTUNSTETHID_SLOT, FIRSTUNSTETHID_OFFSET, FIRSTUNSTETHID_SIZE);
    }

    function _getLastUnstEthId(IEscrowBase _escrow, uint256 _batchIndex) internal view returns (uint256) {
        uint256 batchSlot = _getBatchSlot(_escrow, _batchIndex);
        return _loadData(address(_escrow), batchSlot + LASTUNSTETHID_SLOT, LASTUNSTETHID_OFFSET, LASTUNSTETHID_SIZE);
    }

    function _getLastClaimedBatchIndex(IEscrowBase _escrow) internal view returns (uint56) {
        return uint56(
            _loadData(
                address(_escrow), LASTCLAIMEDBATCHINDEX_SLOT, LASTCLAIMEDBATCHINDEX_OFFSET, LASTCLAIMEDBATCHINDEX_SIZE
            )
        );
    }

    function _getLastClaimedUnstEthIdIndex(IEscrowBase _escrow) internal view returns (uint64) {
        return uint64(
            _loadData(
                address(_escrow),
                LASTCLAIMEDUNSTETHIDINDEX_SLOT,
                LASTCLAIMEDUNSTETHIDINDEX_OFFSET,
                LASTCLAIMEDUNSTETHIDINDEX_SIZE
            )
        );
    }

    function _getTotalUnstEthIdsCount(IEscrowBase _escrow) internal view returns (uint64) {
        return uint64(
            _loadData(
                address(_escrow), TOTALUNSTETHIDSCOUNT_SLOT, TOTALUNSTETHIDSCOUNT_OFFSET, TOTALUNSTETHIDSCOUNT_SIZE
            )
        );
    }

    function _getTotalUnstEthIdsClaimed(IEscrowBase _escrow) internal view returns (uint64) {
        return uint64(
            _loadData(
                address(_escrow),
                TOTALUNSTETHIDSCLAIMED_SLOT,
                TOTALUNSTETHIDSCLAIMED_OFFSET,
                TOTALUNSTETHIDSCLAIMED_SIZE
            )
        );
    }

    function _getUnstEthRecordStatus(IEscrowBase _escrow, uint256 _requestId) internal view returns (uint8) {
        return uint8(
            _loadMappingData(
                address(_escrow),
                UNSTETHRECORDS_SLOT,
                _requestId,
                UNSTETHRECORDSTATUS_SLOT,
                UNSTETHRECORDSTATUS_OFFSET,
                UNSTETHRECORDSTATUS_SIZE
            )
        );
    }

    //
    //  ACCOUNTING RECORDS
    //
    struct AccountingRecord {
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

    function saveAccountingRecord(address user, Escrow escrow) external view returns (AccountingRecord memory ar) {
        Escrow.VetoerDetails memory vetoerDetails = escrow.getVetoerDetails(user);
        Escrow.SignallingEscrowDetails memory signallingEscrowDetails = escrow.getSignallingEscrowDetails();
        StETHModel stEth = StETHModel(address(escrow.ST_ETH()));

        ar.allowance = stEth.allowance(user, address(escrow));
        ar.userBalance = stEth.balanceOf(user);
        ar.escrowBalance = stEth.balanceOf(address(escrow));
        ar.userShares = stEth.sharesOf(user);
        ar.escrowShares = stEth.sharesOf(address(escrow));
        ar.userSharesLocked = SharesValue.unwrap(vetoerDetails.stETHLockedShares);
        ar.totalSharesLocked = SharesValue.unwrap(signallingEscrowDetails.totalStETHLockedShares);
        ar.totalEth = stEth.getPooledEthByShares(ar.totalSharesLocked);
        ar.userUnstEthLockedShares = SharesValue.unwrap(vetoerDetails.unstETHLockedShares);
        ar.unfinalizedShares = SharesValue.unwrap(signallingEscrowDetails.totalUnstETHUnfinalizedShares);
        ar.userLastLockedTime = Timestamp.wrap(uint40(_getLastAssetsLockTimestamp(escrow, user)));
    }

    function establishEqualAccountingRecords(
        Mode mode,
        AccountingRecord memory ar1,
        AccountingRecord memory ar2
    ) external view {
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

    //
    //  STORAGE SETUP
    //
    function escrowStorageSetup(IEscrowBase _escrow, EscrowSt _currentState) external {
        kevm.symbolicStorage(address(_escrow));

        _clearSlot(address(_escrow), ESCROWSTATE_SLOT);

        {
            _storeData(address(_escrow), ESCROWSTATE_SLOT, ESCROWSTATE_OFFSET, ESCROWSTATE_SIZE, uint256(_currentState));

            uint256 minAssetsLockDuration = freshUInt256("Escrow_minAssetsLockDuration");
            vm.assume(minAssetsLockDuration < 2 ** 32);
            vm.assume(minAssetsLockDuration <= block.timestamp);
            _storeData(
                address(_escrow),
                MINLOCKDURATION_SLOT,
                MINLOCKDURATION_OFFSET,
                MINLOCKDURATION_SIZE,
                minAssetsLockDuration
            );

            if (_currentState == EscrowSt.RageQuitEscrow) {
                uint256 rageQuitExtensionPeriodDuration = freshUInt256("Escrow_rageQuitExtensionDuration");
                vm.assume(rageQuitExtensionPeriodDuration < 2 ** 32);
                vm.assume(rageQuitExtensionPeriodDuration <= block.timestamp);
                uint256 rageQuitExtensionPeriodStartedAt = freshUInt256("Escrow_rageQuitExtensionStartedAt");
                vm.assume(rageQuitExtensionPeriodStartedAt <= block.timestamp);
                vm.assume(rageQuitExtensionPeriodStartedAt < timeUpperBound);
                uint256 rageQuitEthWithdrawalsDelay = freshUInt256("Escrow_rageQuitWithdrawalsDelay");
                vm.assume(rageQuitEthWithdrawalsDelay < 2 ** 32);
                vm.assume(rageQuitEthWithdrawalsDelay <= block.timestamp);

                _storeData(
                    address(_escrow),
                    EXTENSIONDURATION_SLOT,
                    EXTENSIONDURATION_OFFSET,
                    EXTENSIONDURATION_SIZE,
                    rageQuitExtensionPeriodDuration
                );
                _storeData(
                    address(_escrow),
                    EXTENSIONSTARTEDAT_SLOT,
                    EXTENSIONSTARTEDAT_OFFSET,
                    EXTENSIONSTARTEDAT_SIZE,
                    rageQuitExtensionPeriodStartedAt
                );
                _storeData(
                    address(_escrow),
                    WITHDRAWALSDELAY_SLOT,
                    WITHDRAWALSDELAY_OFFSET,
                    WITHDRAWALSDELAY_SIZE,
                    rageQuitEthWithdrawalsDelay
                );
            } else {
                _storeData(
                    address(_escrow), EXTENSIONDURATION_SLOT, EXTENSIONDURATION_OFFSET, EXTENSIONDURATION_SIZE, 0
                );
                _storeData(
                    address(_escrow), EXTENSIONSTARTEDAT_SLOT, EXTENSIONSTARTEDAT_OFFSET, EXTENSIONSTARTEDAT_SIZE, 0
                );
                _storeData(address(_escrow), WITHDRAWALSDELAY_SLOT, WITHDRAWALSDELAY_OFFSET, WITHDRAWALSDELAY_SIZE, 0);
            }
        }

        {
            uint256 lockedShares = freshUInt256("Escrow_lockedShares");
            vm.assume(lockedShares < ethUpperBound);
            uint256 claimedEth = freshUInt256("Escrow_claimedEth");
            vm.assume(claimedEth < ethUpperBound);

            _storeData(address(_escrow), LOCKEDSHARES_SLOT, LOCKEDSHARES_OFFSET, LOCKEDSHARES_SIZE, lockedShares);
            _storeData(address(_escrow), CLAIMEDETH_SLOT, CLAIMEDETH_OFFSET, CLAIMEDETH_SIZE, claimedEth);
        }

        {
            uint256 unfinalizedShares = freshUInt256("Escrow_unfinalizedShares");
            vm.assume(unfinalizedShares < ethUpperBound);
            uint256 finalizedEth = freshUInt256("Escrow_finalizedEth");
            vm.assume(finalizedEth < ethUpperBound);

            _storeData(
                address(_escrow),
                UNFINALIZEDSHARES_SLOT,
                UNFINALIZEDSHARES_OFFSET,
                UNFINALIZEDSHARES_SIZE,
                unfinalizedShares
            );
            _storeData(address(_escrow), FINALIZEDETH_SLOT, FINALIZEDETH_OFFSET, FINALIZEDETH_SIZE, finalizedEth);
        }

        if (_currentState == EscrowSt.RageQuitEscrow) {
            uint256 batchesQueueStatus = freshUInt256("Escrow_batchesQueueStatus");
            vm.assume(batchesQueueStatus <= 2);
            _storeData(
                address(_escrow),
                BATCHESQUEUESTATE_SLOT,
                BATCHESQUEUESTATE_OFFSET,
                BATCHESQUEUESTATE_SIZE,
                batchesQueueStatus
            );
        } else {
            _storeData(address(_escrow), BATCHESQUEUESTATE_SLOT, BATCHESQUEUESTATE_OFFSET, BATCHESQUEUESTATE_SIZE, 0);
        }

        uint256 lastClaimedBatchIndex = freshUInt56("Escrow_lastClaimedBatchIndex");
        _storeData(
            address(_escrow),
            LASTCLAIMEDBATCHINDEX_SLOT,
            LASTCLAIMEDBATCHINDEX_OFFSET,
            LASTCLAIMEDBATCHINDEX_SIZE,
            lastClaimedBatchIndex
        );

        uint256 lastClaimedUnstEthIdIndex = freshUInt64("Escrow_lastClaimedUnstEthIdIndex");
        _storeData(
            address(_escrow),
            LASTCLAIMEDUNSTETHIDINDEX_SLOT,
            LASTCLAIMEDUNSTETHIDINDEX_OFFSET,
            LASTCLAIMEDUNSTETHIDINDEX_SIZE,
            lastClaimedUnstEthIdIndex
        );

        uint256 totalUnstEthIdsCount = freshUInt64("Escrow_totalUnstEthIdsCount");
        _storeData(
            address(_escrow),
            TOTALUNSTETHIDSCOUNT_SLOT,
            TOTALUNSTETHIDSCOUNT_OFFSET,
            TOTALUNSTETHIDSCOUNT_SIZE,
            totalUnstEthIdsCount
        );

        uint256 totalUnstEthIdsClaimed = freshUInt64("Escrow_totalUnstEthIdsClaimed");
        _storeData(
            address(_escrow),
            TOTALUNSTETHIDSCLAIMED_SLOT,
            TOTALUNSTETHIDSCLAIMED_OFFSET,
            TOTALUNSTETHIDSCLAIMED_SIZE,
            totalUnstEthIdsClaimed
        );

        if (_currentState == EscrowSt.RageQuitEscrow) {
            uint256 batchesQueueLength = freshUInt256("Escrow_batchesQueueLength");
            vm.assume(0 < batchesQueueLength);
            vm.assume(batchesQueueLength < 2 ** 64);
            _storeData(
                address(_escrow), BATCHESLENGTH_SLOT, BATCHESLENGTH_OFFSET, BATCHESLENGTH_SIZE, batchesQueueLength
            );
        } else {
            _storeData(address(_escrow), BATCHESLENGTH_SLOT, BATCHESLENGTH_OFFSET, BATCHESLENGTH_SIZE, 0);
        }
    }

    function _withdrawalsBatchSetup(IEscrowBase _escrow, uint256 _batchIndex) internal {
        uint256 batchSlot = _getBatchSlot(_escrow, _batchIndex);
        uint256 firstUnstEthId = freshUInt256("Escrow_firstUnstEthId");
        _storeData(
            address(_escrow),
            batchSlot + FIRSTUNSTETHID_SLOT,
            FIRSTUNSTETHID_OFFSET,
            FIRSTUNSTETHID_SIZE,
            firstUnstEthId
        );
        uint256 lastUnstEthId = freshUInt256("Escrow_lastUnstEthId");
        _storeData(
            address(_escrow), batchSlot + LASTUNSTETHID_SLOT, LASTUNSTETHID_OFFSET, LASTUNSTETHID_SIZE, lastUnstEthId
        );
    }

    function escrowUserSetup(IEscrowBase _escrow, address _user) external {
        uint256 key = uint256(uint160(_user));
        uint256 lastAssetsLockTimestamp = freshUInt40("Escrow_lastLockTimestamp");
        vm.assume(lastAssetsLockTimestamp <= block.timestamp);
        vm.assume(lastAssetsLockTimestamp < timeUpperBound);
        _storeMappingData(
            address(_escrow),
            ASSETS_SLOT,
            key,
            LASTASSETSLOCK_SLOT,
            LASTASSETSLOCK_OFFSET,
            LASTASSETSLOCK_SIZE,
            lastAssetsLockTimestamp
        );
        uint256 stETHLockedShares = freshUInt128("Escrow_userStEthLockedShares");
        vm.assume(stETHLockedShares < ethUpperBound);
        _storeMappingData(
            address(_escrow),
            ASSETS_SLOT,
            key,
            STETHSHARES_SLOT,
            STETHSHARES_OFFSET,
            STETHSHARES_SIZE,
            stETHLockedShares
        );
        uint256 unstEthLockedShares = freshUInt128("Escrow_userUnstEthLockedShares");
        vm.assume(unstEthLockedShares < ethUpperBound);
        _storeMappingData(
            address(_escrow),
            ASSETS_SLOT,
            key,
            UNSTETHSHARES_SLOT,
            UNSTETHSHARES_OFFSET,
            UNSTETHSHARES_SIZE,
            unstEthLockedShares
        );
        uint256 unstEthIdsLength = freshUInt256("Escrow_userUnstEthIdsLength");
        vm.assume(unstEthIdsLength < type(uint32).max);
        _storeMappingData(
            address(_escrow),
            ASSETS_SLOT,
            key,
            UNSTETHIDSLENGTH_SLOT,
            UNSTETHIDSLENGTH_OFFSET,
            UNSTETHIDSLENGTH_SIZE,
            unstEthIdsLength
        );
    }

    function escrowWithdrawalQueueSetup(IEscrowBase _escrow, WithdrawalQueueModel _withdrawalQueue) external {
        uint256 unstEthRecordStatus = freshUInt256("Escrow_unstEthRecordStatus");
        vm.assume(unstEthRecordStatus < 5);
        _storeMappingData(
            address(_escrow),
            UNSTETHRECORDS_SLOT,
            _withdrawalQueue.getLastRequestId() + 1,
            UNSTETHRECORDSTATUS_SLOT,
            UNSTETHRECORDSTATUS_OFFSET,
            UNSTETHRECORDSTATUS_SIZE,
            unstEthRecordStatus
        );
    }

    function escrowStorageInvariants(Mode mode, IEscrowBase _escrow) external {
        uint8 batchesQueueStatus = _getBatchesQueueStatus(_escrow);
        uint32 rageQuitEthWithdrawalsDelay = _getRageQuitEthWithdrawalsDelay(_escrow);
        uint32 rageQuitExtensionPeriodDuration = _getRageQuitExtensionPeriodDuration(_escrow);
        uint40 rageQuitExtensionPeriodStartedAt = _getRageQuitExtensionPeriodStartedAt(_escrow);

        _establish(mode, batchesQueueStatus <= 2);
        _establish(mode, rageQuitEthWithdrawalsDelay <= block.timestamp);
        _establish(mode, rageQuitExtensionPeriodDuration <= block.timestamp);
        _establish(mode, rageQuitExtensionPeriodStartedAt <= block.timestamp);
    }

    function escrowAssumeBounds(IEscrowBase _escrow, EscrowSt _currentState) external {
        if (_currentState == EscrowSt.SignallingEscrow) {
            // Assume getRageQuitSupport() doesn´t overflow
            uint256 finalizedEth = _getFinalizedEth(_escrow);
            uint256 unfinalizedShares = _getUnfinalizedShares(_escrow) + _getTotalStEthLockedShares(_escrow);
            IStETH stEth = Escrow(payable(address(_escrow))).ST_ETH();
            uint256 numerator = stEth.getPooledEthByShares(unfinalizedShares) + finalizedEth;
            uint256 denominator = stEth.totalSupply() + finalizedEth;
            vm.assume(1e18 * numerator / denominator <= type(uint128).max);
        }
    }

    function escrowInitializeStorage(IEscrowBase _escrow, EscrowSt _currentState) external {
        this.escrowStorageSetup(_escrow, _currentState);
        this.escrowStorageInvariants(Mode.Assume, _escrow);
        this.escrowAssumeBounds(_escrow, _currentState);
    }

    function signallingEscrowStorageInvariants(Mode mode, IEscrowBase _signallingEscrow) external {
        uint32 rageQuitEthWithdrawalsDelay = _getRageQuitEthWithdrawalsDelay(_signallingEscrow);
        uint32 rageQuitExtensionPeriodDuration = _getRageQuitExtensionPeriodDuration(_signallingEscrow);
        uint40 rageQuitExtensionPeriodStartedAt = _getRageQuitExtensionPeriodStartedAt(_signallingEscrow);
        uint8 batchesQueueStatus = _getBatchesQueueStatus(_signallingEscrow);

        _establish(mode, rageQuitEthWithdrawalsDelay == 0);
        _establish(mode, rageQuitExtensionPeriodDuration == 0);
        _establish(mode, rageQuitExtensionPeriodStartedAt == 0);
        _establish(mode, batchesQueueStatus == uint8(WithdrawalsBatchesQueueState.NotInitialized));
    }

    function signallingEscrowInitializeStorage(IEscrowBase _signallingEscrow) external {
        this.escrowInitializeStorage(_signallingEscrow, EscrowSt.SignallingEscrow);
        this.signallingEscrowStorageInvariants(Mode.Assume, _signallingEscrow);
    }

    function rageQuitEscrowStorageInvariants(Mode mode, IEscrowBase _rageQuitEscrow) external {
        uint8 batchesQueueStatus = _getBatchesQueueStatus(_rageQuitEscrow);

        _establish(mode, batchesQueueStatus != uint8(WithdrawalsBatchesQueueState.NotInitialized));
    }

    function rageQuitEscrowInitializeStorage(IEscrowBase _rageQuitEscrow) external {
        this.escrowInitializeStorage(_rageQuitEscrow, EscrowSt.RageQuitEscrow);
        this.rageQuitEscrowStorageInvariants(Mode.Assume, _rageQuitEscrow);
    }
}
