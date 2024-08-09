pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/Configuration.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";

import {Status, Proposal} from "contracts/libraries/Proposals.sol";
import {State} from "contracts/libraries/DualGovernanceState.sol";
import {addTo, Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";

import {DualGovernanceSetUp} from "test/kontrol/DualGovernanceSetUp.sol";

contract ProposalOperationsSetup is DualGovernanceSetUp {
    DualGovernance auxDualGovernance;
    EmergencyProtectedTimelock auxTimelock;
    Escrow auxSignallingEscrow;
    Escrow auxRageQuitEscrow;

    function _initializeAuxDualGovernance() public {
        address adminProposer = address(uint160(uint256(keccak256("adminProposer"))));
        auxTimelock = new EmergencyProtectedTimelock(address(config));
        kevm.symbolicStorage(address(auxTimelock));

        auxDualGovernance =
            new DualGovernance(address(config), address(timelock), address(escrowMasterCopy), adminProposer);
        kevm.copyStorage(address(dualGovernance), address(auxDualGovernance));

        auxSignallingEscrow = Escrow(payable(Clones.clone(dualGovernance.getVetoSignallingEscrow())));
        auxRageQuitEscrow = Escrow(payable(Clones.clone(dualGovernance.getRageQuitEscrow())));
        kevm.copyStorage(dualGovernance.getVetoSignallingEscrow(), address(auxSignallingEscrow));
        kevm.copyStorage(dualGovernance.getRageQuitEscrow(), address(auxRageQuitEscrow));

        uint256 signallingEscrowSlot = _loadUInt256(address(auxDualGovernance), 5);
        uint256 rageQuitEscrowSlot = _loadUInt256(address(auxDualGovernance), 6);

        uint256 signallingEscrowMask = type(uint256).max ^ ((2 ** 160 - 1) << 88);
        uint256 rageQuitEscrowMask = type(uint256).max ^ ((2 ** 160 - 1) << 80);

        signallingEscrowSlot =
            (uint256(uint160(address(auxSignallingEscrow))) * (2 ** 88)) | (signallingEscrowMask & signallingEscrowSlot);
        rageQuitEscrowSlot =
            (uint256(uint160(address(auxRageQuitEscrow))) * (2 ** 80)) | (rageQuitEscrowMask & rageQuitEscrowSlot);

        _storeUInt256(address(auxDualGovernance), 5, signallingEscrowSlot);
        _storeUInt256(address(auxDualGovernance), 6, rageQuitEscrowSlot);

        uint256 dualGovernanceMask = type(uint256).max ^ ((2 ** 160 - 1) << 8);

        uint256 dualGovernanceSlotSE = _loadUInt256(address(auxSignallingEscrow), 0);
        uint256 dualGovernanceSlotRE = _loadUInt256(address(auxRageQuitEscrow), 0);

        dualGovernanceSlotSE =
            (uint256(uint160(address(auxDualGovernance))) * (2 ** 8)) | (dualGovernanceMask & dualGovernanceSlotSE);
        dualGovernanceSlotRE =
            (uint256(uint160(address(auxDualGovernance))) * (2 ** 8)) | (dualGovernanceMask & dualGovernanceSlotRE);

        _storeUInt256(address(auxSignallingEscrow), 0, dualGovernanceSlotSE);
        _storeUInt256(address(auxRageQuitEscrow), 0, dualGovernanceSlotRE);
    }

    // ?STORAGE3
    // ?WORD21: lastCancelledProposalId
    // ?WORD22: proposalsLength
    // ?WORD23: protectedTill
    // ?WORD24: emergencyModeEndsAfter
    function _timelockStorageSetup(DualGovernance _dualGovernance, EmergencyProtectedTimelock _timelock) public {
        // Slot 0
        _storeAddress(address(_timelock), 0, address(_dualGovernance));
        // Slot 1
        uint256 lastCancelledProposalId = kevm.freshUInt(32);
        vm.assume(lastCancelledProposalId < type(uint256).max);
        _storeUInt256(address(timelock), 1, lastCancelledProposalId);
        // Slot 2
        uint256 proposalsLength = kevm.freshUInt(32);
        vm.assume(proposalsLength < type(uint64).max);
        vm.assume(lastCancelledProposalId <= proposalsLength);
        _storeUInt256(address(_timelock), 2, proposalsLength);
        // Slot 3
        {
            address activationCommittee = address(uint160(uint256(keccak256("activationCommittee"))));
            uint40 protectedTill = uint40(kevm.freshUInt(5));
            vm.assume(protectedTill < timeUpperBound);
            vm.assume(protectedTill <= block.timestamp);
            bytes memory slot3Abi = abi.encodePacked(uint56(0), uint40(protectedTill), uint160(activationCommittee));
            bytes32 slot3;
            assembly {
                slot3 := mload(add(slot3Abi, 0x20))
            }
            _storeBytes32(address(_timelock), 3, slot3);
        }
        // Slot 4
        uint40 emergencyModeEndsAfter = uint40(kevm.freshUInt(5));
        vm.assume(emergencyModeEndsAfter < timeUpperBound);
        vm.assume(emergencyModeEndsAfter <= block.timestamp);
        _storeUInt256(address(_timelock), 4, emergencyModeEndsAfter);
    }

    // Set up the storage for a proposal.
    // ?WORD25: submittedAt
    // ?WORD26: scheduledAt
    // ?WORD27: executedAt
    // ?WORD28: numCalls
    function _proposalStorageSetup(EmergencyProtectedTimelock _timelock, uint256 _proposalId) public {
        uint256 baseSlot = _getProposalsSlot(_proposalId);
        // slot 1
        {
            address executor = address(uint160(uint256(keccak256("executor"))));
            uint40 submittedAt = uint40(kevm.freshUInt(5));
            vm.assume(submittedAt < timeUpperBound);
            vm.assume(submittedAt <= block.timestamp);
            uint40 scheduledAt = uint40(kevm.freshUInt(5));
            vm.assume(scheduledAt < timeUpperBound);
            vm.assume(scheduledAt <= block.timestamp);
            bytes memory slot1Abi =
                abi.encodePacked(uint16(0), uint40(scheduledAt), uint40(submittedAt), uint160(executor));
            bytes32 slot1;
            assembly {
                slot1 := mload(add(slot1Abi, 0x20))
            }
            _storeBytes32(address(_timelock), baseSlot, slot1);
        }
        // slot 2
        {
            uint40 executedAt = uint40(kevm.freshUInt(5));
            vm.assume(executedAt < timeUpperBound);
            vm.assume(executedAt <= block.timestamp);
            _storeUInt256(address(_timelock), baseSlot + 1, executedAt);
        }
        // slot 3
        {
            uint256 numCalls = kevm.freshUInt(32);
            vm.assume(numCalls < type(uint256).max);
            vm.assume(numCalls > 0);
            _storeUInt256(address(_timelock), baseSlot + 2, numCalls);
        }
    }

    function _storeExecutorCalls(EmergencyProtectedTimelock _timelock, uint256 _proposalId) public {
        uint256 baseSlot = _getProposalsSlot(_proposalId);
        uint256 numCalls = _getCallsCount(_timelock, _proposalId);
        uint256 callsSlot = uint256(keccak256(abi.encodePacked(baseSlot + 2)));

        for (uint256 j = 0; j < numCalls; j++) {
            uint256 callSlot = callsSlot + j * 3;
            vm.assume(callSlot < type(uint256).max);
            address target = address(uint160(uint256(keccak256(abi.encodePacked(j, "target")))));
            _storeAddress(address(_timelock), callSlot, target);
            uint96 value = uint96(kevm.freshUInt(12));
            vm.assume(value != 0);
            _storeUInt256(address(_timelock), callSlot + 1, uint256(value));
            bytes memory payload = abi.encodePacked(j, "payload");
            _storeBytes32(address(_timelock), callSlot + 2, keccak256(payload));
        }
    }

    function _proposalIdAssumeBound(uint256 _proposalId) internal view {
        vm.assume(_proposalId > 0);
        vm.assume(_proposalId < _getProposalsCount(timelock));
        uint256 slot2 = uint256(keccak256(abi.encodePacked(uint256(2))));
        vm.assume((_proposalId - 1) <= ((type(uint256).max - 3 - slot2) / 3));
    }

    function _getProposalsSlot(uint256 _proposalId) internal returns (uint256 baseSlot) {
        uint256 startSlot = uint256(keccak256(abi.encodePacked(uint256(2))));
        uint256 offset = 3 * (_proposalId - 1);
        baseSlot = startSlot + offset;
    }

    function _getProtectedTill(EmergencyProtectedTimelock _timelock) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_timelock), 3) >> 160);
    }

    function _getLastCancelledProposalId(EmergencyProtectedTimelock _timelock) internal view returns (uint256) {
        return _loadUInt256(address(_timelock), 1);
    }

    function _getProposalsCount(EmergencyProtectedTimelock _timelock) internal view returns (uint256) {
        return _loadUInt256(address(_timelock), 2);
    }

    function _getEmergencyModeEndsAfter(EmergencyProtectedTimelock _timelock) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_timelock), 4));
    }

    function _getSubmittedAt(EmergencyProtectedTimelock _timelock, uint256 baseSlot) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_timelock), baseSlot) >> 160);
    }

    function _getScheduledAt(EmergencyProtectedTimelock _timelock, uint256 baseSlot) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_timelock), baseSlot) >> 200);
    }

    function _getExecutedAt(EmergencyProtectedTimelock _timelock, uint256 baseSlot) internal view returns (uint40) {
        return uint40(_loadUInt256(address(_timelock), baseSlot + 1));
    }

    function _getCallsCount(EmergencyProtectedTimelock _timelock, uint256 baseSlot) internal view returns (uint256) {
        return _loadUInt256(address(_timelock), baseSlot + 2);
    }
}
