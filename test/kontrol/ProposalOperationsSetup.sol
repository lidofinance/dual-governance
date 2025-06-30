pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/ImmutableDualGovernanceConfigProvider.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import {Escrow} from "contracts/Escrow.sol";

import {Status, ExecutableProposals as Proposals} from "contracts/libraries/ExecutableProposals.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {KontrolTest} from "test/kontrol/KontrolTest.sol";
import "test/kontrol/storage/EmergencyProtectedTimelockStorageConstants.sol";

contract ProposalOperationsSetup is KontrolTest {
    //
    //  STORAGE CONSTANTS
    //
    uint256 constant GOVERNANCE_SLOT = EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_GOVERNANCE_SLOT;
    uint256 constant GOVERNANCE_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_GOVERNANCE_OFFSET;
    uint256 constant GOVERNANCE_SIZE = EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_GOVERNANCE_SIZE;
    uint256 constant ADMINEXECUTOR_SLOT =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_ADMINEXECUTOR_SLOT;
    uint256 constant ADMINEXECUTOR_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_ADMINEXECUTOR_OFFSET;
    uint256 constant ADMINEXECUTOR_SIZE =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_ADMINEXECUTOR_SIZE;
    uint256 constant AFTERSUBMITDELAY_SLOT =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_AFTERSUBMITDELAY_SLOT;
    uint256 constant AFTERSUBMITDELAY_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_AFTERSUBMITDELAY_OFFSET;
    uint256 constant AFTERSUBMITDELAY_SIZE =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_AFTERSUBMITDELAY_SIZE;
    uint256 constant AFTERSCHEDULEDELAY_SLOT =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_AFTERSCHEDULEDELAY_SLOT;
    uint256 constant AFTERSCHEDULEDELAY_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_AFTERSCHEDULEDELAY_OFFSET;
    uint256 constant AFTERSCHEDULEDELAY_SIZE =
        EmergencyProtectedTimelockStorageConstants.STORAGE_TIMELOCKSTATE_AFTERSCHEDULEDELAY_SIZE;
    uint256 constant PROPOSALSCOUNT_SLOT =
        EmergencyProtectedTimelockStorageConstants.STORAGE_PROPOSALS_PROPOSALSCOUNT_SLOT;
    uint256 constant PROPOSALSCOUNT_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_PROPOSALS_PROPOSALSCOUNT_OFFSET;
    uint256 constant PROPOSALSCOUNT_SIZE =
        EmergencyProtectedTimelockStorageConstants.STORAGE_PROPOSALS_PROPOSALSCOUNT_SIZE;
    uint256 constant LASTCANCELLEDPROPOSALID_SLOT =
        EmergencyProtectedTimelockStorageConstants.STORAGE_PROPOSALS_LASTCANCELLEDPROPOSALID_SLOT;
    uint256 constant LASTCANCELLEDPROPOSALID_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_PROPOSALS_LASTCANCELLEDPROPOSALID_OFFSET;
    uint256 constant LASTCANCELLEDPROPOSALID_SIZE =
        EmergencyProtectedTimelockStorageConstants.STORAGE_PROPOSALS_LASTCANCELLEDPROPOSALID_SIZE;
    uint256 constant ACTIVATIONCOMMITTEE_SLOT =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYACTIVATIONCOMMITTEE_SLOT;
    uint256 constant ACTIVATIONCOMMITTEE_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYACTIVATIONCOMMITTEE_OFFSET;
    uint256 constant ACTIVATIONCOMMITTEE_SIZE =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYACTIVATIONCOMMITTEE_SIZE;
    uint256 constant EXECUTIONCOMMITTEE_SLOT =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYEXECUTIONCOMMITTEE_SLOT;
    uint256 constant EXECUTIONCOMMITTEE_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYEXECUTIONCOMMITTEE_OFFSET;
    uint256 constant EXECUTIONCOMMITTEE_SIZE =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYEXECUTIONCOMMITTEE_SIZE;
    uint256 constant PROTECTIONENDSAFTER_SLOT =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYPROTECTIONENDSAFTER_SLOT;
    uint256 constant PROTECTIONENDSAFTER_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYPROTECTIONENDSAFTER_OFFSET;
    uint256 constant PROTECTIONENDSAFTER_SIZE =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYPROTECTIONENDSAFTER_SIZE;
    uint256 constant EMERGENCYMODEENDSAFTER_SLOT =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYMODEENDSAFTER_SLOT;
    uint256 constant EMERGENCYMODEENDSAFTER_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYMODEENDSAFTER_OFFSET;
    uint256 constant EMERGENCYMODEENDSAFTER_SIZE =
        EmergencyProtectedTimelockStorageConstants.STORAGE_EMERGENCYPROTECTION_EMERGENCYMODEENDSAFTER_SIZE;
    uint256 constant PROPOSALS_SLOT = EmergencyProtectedTimelockStorageConstants.STORAGE_PROPOSALS_PROPOSALS_SLOT;
    uint256 constant STATUS_SLOT =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_STATUS_SLOT;
    uint256 constant STATUS_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_STATUS_OFFSET;
    uint256 constant STATUS_SIZE =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_STATUS_SIZE;
    uint256 constant EXECUTOR_SLOT =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_EXECUTOR_SLOT;
    uint256 constant EXECUTOR_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_EXECUTOR_OFFSET;
    uint256 constant EXECUTOR_SIZE =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_EXECUTOR_SIZE;
    uint256 constant SUBMITTEDAT_SLOT =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_SUBMITTEDAT_SLOT;
    uint256 constant SUBMITTEDAT_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_SUBMITTEDAT_OFFSET;
    uint256 constant SUBMITTEDAT_SIZE =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_SUBMITTEDAT_SIZE;
    uint256 constant SCHEDULEDAT_SLOT =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_SCHEDULEDAT_SLOT;
    uint256 constant SCHEDULEDAT_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_SCHEDULEDAT_OFFSET;
    uint256 constant SCHEDULEDAT_SIZE =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_DATA_SCHEDULEDAT_SIZE;
    uint256 constant TARGET_SLOT = EmergencyProtectedTimelockStorageConstants.STRUCT_EXTERNALCALL_TARGET_SLOT;
    uint256 constant TARGET_OFFSET = EmergencyProtectedTimelockStorageConstants.STRUCT_EXTERNALCALL_TARGET_OFFSET;
    uint256 constant TARGET_SIZE = EmergencyProtectedTimelockStorageConstants.STRUCT_EXTERNALCALL_TARGET_SIZE;
    uint256 constant VALUE_SLOT = EmergencyProtectedTimelockStorageConstants.STRUCT_EXTERNALCALL_VALUE_SLOT;
    uint256 constant VALUE_OFFSET = EmergencyProtectedTimelockStorageConstants.STRUCT_EXTERNALCALL_VALUE_OFFSET;
    uint256 constant VALUE_SIZE = EmergencyProtectedTimelockStorageConstants.STRUCT_EXTERNALCALL_VALUE_SIZE;
    uint256 constant PAYLOAD_SLOT = EmergencyProtectedTimelockStorageConstants.STRUCT_EXTERNALCALL_PAYLOAD_SLOT;
    uint256 constant PAYLOAD_OFFSET = EmergencyProtectedTimelockStorageConstants.STRUCT_EXTERNALCALL_PAYLOAD_OFFSET;
    uint256 constant PAYLOAD_SIZE = EmergencyProtectedTimelockStorageConstants.STRUCT_EXTERNALCALL_PAYLOAD_SIZE;
    uint256 constant CALLS_SLOT =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_CALLS_SLOT;
    uint256 constant CALLS_OFFSET =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_CALLS_OFFSET;
    uint256 constant CALLS_SIZE =
        EmergencyProtectedTimelockStorageConstants.STRUCT_EXECUTABLEPROPOSALS_PROPOSAL_CALLS_SIZE;

    //
    //  GETTERS
    //
    function _getAfterSubmitDelay(address _timelock) internal returns (Duration) {
        return Duration.wrap(
            uint32(_loadData(_timelock, AFTERSUBMITDELAY_SLOT, AFTERSUBMITDELAY_OFFSET, AFTERSUBMITDELAY_SIZE))
        );
    }

    function _getAfterScheduleDelay(address _timelock) internal returns (Duration) {
        return Duration.wrap(
            uint32(_loadData(_timelock, AFTERSCHEDULEDELAY_SLOT, AFTERSCHEDULEDELAY_OFFSET, AFTERSCHEDULEDELAY_SIZE))
        );
    }

    function _getProposalsSlot(uint256 _proposalId) internal returns (uint256 baseSlot) {
        return uint256(keccak256(abi.encodePacked(_proposalId, PROPOSALS_SLOT)));
    }

    function _getCallsSlot(uint256 _proposalId) internal returns (uint256) {
        uint256 proposalsSlot = _getProposalsSlot(_proposalId);
        return uint256(keccak256(abi.encodePacked(proposalsSlot + CALLS_SLOT)));
    }

    function _getLastCancelledProposalId(EmergencyProtectedTimelock _timelock) internal view returns (uint256) {
        return _loadData(
            address(_timelock),
            LASTCANCELLEDPROPOSALID_SLOT,
            LASTCANCELLEDPROPOSALID_OFFSET,
            LASTCANCELLEDPROPOSALID_SIZE
        );
    }

    function _getProposalsCount(EmergencyProtectedTimelock _timelock) internal view returns (uint256) {
        return _loadData(address(_timelock), PROPOSALSCOUNT_SLOT, PROPOSALSCOUNT_OFFSET, PROPOSALSCOUNT_SIZE);
    }

    function _getEmergencyModeEndsAfter(EmergencyProtectedTimelock _timelock) internal view returns (uint40) {
        return uint40(
            _loadData(
                address(_timelock),
                EMERGENCYMODEENDSAFTER_SLOT,
                EMERGENCYMODEENDSAFTER_OFFSET,
                EMERGENCYMODEENDSAFTER_SIZE
            )
        );
    }

    function _getSubmittedAt(EmergencyProtectedTimelock _timelock, uint256 baseSlot) internal view returns (uint40) {
        return uint40(_loadData(address(_timelock), baseSlot + SUBMITTEDAT_SLOT, SUBMITTEDAT_OFFSET, SUBMITTEDAT_SIZE));
    }

    function _getScheduledAt(EmergencyProtectedTimelock _timelock, uint256 baseSlot) internal view returns (uint40) {
        return uint40(_loadData(address(_timelock), baseSlot + SCHEDULEDAT_SLOT, SCHEDULEDAT_OFFSET, SCHEDULEDAT_SIZE));
    }

    function _getProposalStatus(
        EmergencyProtectedTimelock _timelock,
        uint256 _proposalId
    ) internal view returns (Status) {
        return Status(
            _loadMappingData(address(_timelock), PROPOSALS_SLOT, _proposalId, STATUS_SLOT, STATUS_OFFSET, STATUS_SIZE)
        );
    }

    function _getCallsCount(
        EmergencyProtectedTimelock _timelock,
        uint256 _proposalId
    ) internal view returns (uint256) {
        return _loadMappingData(address(_timelock), PROPOSALS_SLOT, _proposalId, CALLS_SLOT, CALLS_OFFSET, CALLS_SIZE);
    }

    function _setCallsCount(EmergencyProtectedTimelock _timelock, uint256 _proposalId, uint256 value) internal {
        _storeMappingData(address(_timelock), PROPOSALS_SLOT, _proposalId, CALLS_SLOT, CALLS_OFFSET, CALLS_SIZE, value);
    }

    //
    //  STORAGE SETUP
    //
    function timelockStorageSetup(DualGovernance _dualGovernance, EmergencyProtectedTimelock _timelock) external {
        kevm.symbolicStorage(address(_timelock));

        _clearSlot(address(_timelock), GOVERNANCE_SLOT);
        _clearSlot(address(_timelock), PROPOSALSCOUNT_SLOT);
        _clearSlot(address(_timelock), EMERGENCYMODEENDSAFTER_SLOT);
        _clearSlot(address(_timelock), EXECUTIONCOMMITTEE_SLOT);

        uint160 adminExecutor = uint160(uint256(keccak256("adminExecutor")));
        _storeData(
            address(_timelock), ADMINEXECUTOR_SLOT, ADMINEXECUTOR_OFFSET, ADMINEXECUTOR_SIZE, uint256(adminExecutor)
        );

        uint256 governance = uint256(uint160(address(_dualGovernance)));
        _storeData(address(_timelock), GOVERNANCE_SLOT, GOVERNANCE_OFFSET, GOVERNANCE_SIZE, governance);

        uint256 afterSubmitDelay = freshUInt256("ETL_afterSubmitDelay");
        vm.assume(afterSubmitDelay < 2 ** 32);
        _storeData(
            address(_timelock), AFTERSUBMITDELAY_SLOT, AFTERSUBMITDELAY_OFFSET, AFTERSUBMITDELAY_SIZE, afterSubmitDelay
        );

        uint256 afterScheduleDelay = freshUInt256("ETL_afterScheduleDelay");
        vm.assume(afterScheduleDelay < 2 ** 32);
        _storeData(
            address(_timelock),
            AFTERSCHEDULEDELAY_SLOT,
            AFTERSCHEDULEDELAY_OFFSET,
            AFTERSCHEDULEDELAY_SIZE,
            afterScheduleDelay
        );

        uint256 proposalsCount = freshUInt256("ETL_proposalsCount");
        // To allow submit another proposal without reverting due to overflow
        vm.assume(proposalsCount < type(uint64).max - 1);
        _storeData(address(_timelock), PROPOSALSCOUNT_SLOT, PROPOSALSCOUNT_OFFSET, PROPOSALSCOUNT_SIZE, proposalsCount);

        uint256 lastCancelledProposalId = freshUInt256("ETL_lastCancelledProposalId");
        vm.assume(lastCancelledProposalId <= proposalsCount);
        _storeData(
            address(_timelock),
            LASTCANCELLEDPROPOSALID_SLOT,
            LASTCANCELLEDPROPOSALID_OFFSET,
            LASTCANCELLEDPROPOSALID_SIZE,
            lastCancelledProposalId
        );

        {
            uint160 activationCommittee = uint160(uint256(keccak256("activationCommittee")));
            uint256 protectionEndsAfter = freshUInt256("ETL_protectionEndsAfter");
            vm.assume(protectionEndsAfter < timeUpperBound);
            vm.assume(protectionEndsAfter <= block.timestamp);
            _storeData(
                address(_timelock),
                ACTIVATIONCOMMITTEE_SLOT,
                ACTIVATIONCOMMITTEE_OFFSET,
                ACTIVATIONCOMMITTEE_SIZE,
                uint256(activationCommittee)
            );
            _storeData(
                address(_timelock),
                PROTECTIONENDSAFTER_SLOT,
                PROTECTIONENDSAFTER_OFFSET,
                PROTECTIONENDSAFTER_SIZE,
                protectionEndsAfter
            );
        }

        {
            uint160 executionCommittee = uint160(uint256(keccak256("executionCommittee")));
            _storeData(
                address(_timelock),
                EXECUTIONCOMMITTEE_SLOT,
                EXECUTIONCOMMITTEE_OFFSET,
                EXECUTIONCOMMITTEE_SIZE,
                uint256(executionCommittee)
            );
        }

        uint256 emergencyModeEndsAfter = freshUInt256("ETL_emergencyModeEndsAfter");
        vm.assume(emergencyModeEndsAfter < timeUpperBound);
        vm.assume(emergencyModeEndsAfter <= block.timestamp);
        _storeData(
            address(_timelock),
            EMERGENCYMODEENDSAFTER_SLOT,
            EMERGENCYMODEENDSAFTER_OFFSET,
            EMERGENCYMODEENDSAFTER_SIZE,
            emergencyModeEndsAfter
        );
    }

    // Set up the storage for a proposal.
    function _proposalStorageSetup(
        EmergencyProtectedTimelock _timelock,
        uint256 _proposalId,
        address executor,
        Status _proposalStatus
    ) internal {
        {
            _clearMappingSlot(address(_timelock), PROPOSALS_SLOT, _proposalId, STATUS_SLOT);

            uint256 status = uint256(_proposalStatus);
            if (status == 0) {
                status = freshUInt256("ETL_status");
                vm.assume(status != 0);
                vm.assume(status <= 4);
            }
            _storeMappingData(
                address(_timelock), PROPOSALS_SLOT, _proposalId, STATUS_SLOT, STATUS_OFFSET, STATUS_SIZE, status
            );
            _storeMappingData(
                address(_timelock),
                PROPOSALS_SLOT,
                _proposalId,
                EXECUTOR_SLOT,
                EXECUTOR_OFFSET,
                EXECUTOR_SIZE,
                uint256(uint160(executor))
            );
            uint256 submittedAt = freshUInt256("ETL_submittedAt");
            vm.assume(submittedAt < timeUpperBound);
            vm.assume(submittedAt <= block.timestamp);
            _storeMappingData(
                address(_timelock),
                PROPOSALS_SLOT,
                _proposalId,
                SUBMITTEDAT_SLOT,
                SUBMITTEDAT_OFFSET,
                SUBMITTEDAT_SIZE,
                submittedAt
            );
            uint256 scheduledAt = freshUInt256("ETH_scheduledAt");
            vm.assume(scheduledAt < timeUpperBound);
            vm.assume(scheduledAt <= block.timestamp);
            _storeMappingData(
                address(_timelock),
                PROPOSALS_SLOT,
                _proposalId,
                SCHEDULEDAT_SLOT,
                SCHEDULEDAT_OFFSET,
                SCHEDULEDAT_SIZE,
                scheduledAt
            );
        }
    }

    function _proposalStorageSetup(
        EmergencyProtectedTimelock _timelock,
        uint256 _proposalId,
        address executor
    ) internal {
        _proposalStorageSetup(_timelock, _proposalId, executor, Status.NotExist);
    }

    function _proposalStorageSetup(
        EmergencyProtectedTimelock _timelock,
        uint256 _proposalId,
        Status _proposalStatus
    ) internal {
        address executor = address(uint160(uint256(keccak256("executor"))));
        _proposalStorageSetup(_timelock, _proposalId, executor, _proposalStatus);
    }

    function _proposalStorageSetup(EmergencyProtectedTimelock _timelock, uint256 _proposalId) internal {
        address executor = address(uint160(uint256(keccak256("executor"))));
        _proposalStorageSetup(_timelock, _proposalId, executor);
    }

    function _storeExecutorCalls(EmergencyProtectedTimelock _timelock, uint256 _proposalId) internal {
        uint256 numCalls = _getCallsCount(_timelock, _proposalId);
        uint256 callsSlot = _getCallsSlot(_proposalId);

        for (uint256 j = 0; j < numCalls; j++) {
            uint256 callSlot = callsSlot + j * 2;
            uint256 target = uint256(uint160(uint256(keccak256(abi.encodePacked(j, "target")))));
            _storeData(address(_timelock), callSlot + TARGET_SLOT, TARGET_OFFSET, TARGET_SIZE, target);
            uint256 value = kevm.freshUInt(12);
            vm.assume(value != 0);
            _storeData(address(_timelock), callSlot + VALUE_SLOT, VALUE_OFFSET, VALUE_SIZE, value);
        }
    }

    function _proposalIdAssumeBound(EmergencyProtectedTimelock _timelock, uint256 _proposalId) internal view {
        vm.assume(_proposalId > 0);
        vm.assume(_proposalId < _getProposalsCount(_timelock));
        uint256 slot2 = uint256(keccak256(abi.encodePacked(uint256(2))));
        vm.assume((_proposalId - 1) <= ((type(uint256).max - 3 - slot2) / 3));
    }
}
