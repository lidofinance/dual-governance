// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HashConsensus} from "./HashConsensus.sol";
import {ProposalsList} from "./ProposalsList.sol";

interface IEmergencyProtectedTimelock {
    function emergencyExecute(uint256 proposalId) external;
    function emergencyReset() external;
}

enum ProposalType {
    EmergencyExecute,
    EmergencyReset
}

contract EmergencyExecutionCommittee is HashConsensus, ProposalsList {
    address public immutable EMERGENCY_PROTECTED_TIMELOCK;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) HashConsensus(owner, committeeMembers, executionQuorum, 0) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;
    }

    // Emergency Execution

    function voteEmergencyExecute(uint256 proposalId, bool _supports) public onlyMember {
        (bytes memory proposalData, bytes32 key) = _encodeEmergencyExecute(proposalId);
        _vote(key, _supports);
        _pushProposal(key, uint256(ProposalType.EmergencyExecute), proposalData);
    }

    function getEmergencyExecuteState(uint256 proposalId)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        (, bytes32 key) = _encodeEmergencyExecute(proposalId);
        return _getHashState(key);
    }

    function executeEmergencyExecute(uint256 proposalId) public {
        (, bytes32 key) = _encodeEmergencyExecute(proposalId);
        _markUsed(key);
        Address.functionCall(
            EMERGENCY_PROTECTED_TIMELOCK,
            abi.encodeWithSelector(IEmergencyProtectedTimelock.emergencyExecute.selector, proposalId)
        );
    }

    function _encodeEmergencyExecute(uint256 proposalId)
        private
        pure
        returns (bytes memory proposalData, bytes32 key)
    {
        proposalData = abi.encode(ProposalType.EmergencyExecute, proposalId);
        key = keccak256(proposalData);
    }

    // Governance reset

    function approveEmergencyReset() public onlyMember {
        bytes32 proposalKey = _encodeEmergencyResetProposalKey();
        _vote(proposalKey, true);
        _pushProposal(proposalKey, uint256(ProposalType.EmergencyReset), bytes(""));
    }

    function getEmergencyResetState()
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        bytes32 proposalKey = _encodeEmergencyResetProposalKey();
        return _getHashState(proposalKey);
    }

    function executeEmergencyReset() external {
        bytes32 proposalKey = _encodeEmergencyResetProposalKey();
        _markUsed(proposalKey);
        Address.functionCall(
            EMERGENCY_PROTECTED_TIMELOCK, abi.encodeWithSelector(IEmergencyProtectedTimelock.emergencyReset.selector)
        );
    }

    function _encodeEmergencyResetProposalKey() internal pure returns (bytes32) {
        return keccak256(abi.encode(ProposalType.EmergencyReset, bytes32(0)));
    }
}
