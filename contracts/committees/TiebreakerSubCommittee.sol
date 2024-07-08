// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HashConsensus} from "./HashConsensus.sol";
import {ProposalsList} from "./ProposalsList.sol";

interface ITiebreakerCore {
    function getSealableResumeNonce(address sealable) external view returns (uint256 nonce);
    function scheduleProposal(uint256 _proposalId) external;
    function sealableResume(address sealable, uint256 nonce) external;
}

enum ProposalType {
    ScheduleProposal,
    ResumeSelable
}

contract TiebreakerSubCommittee is HashConsensus, ProposalsList {
    address immutable TIEBREAKER_CORE;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address tiebreakerCore
    ) HashConsensus(owner, committeeMembers, executionQuorum, 0) {
        TIEBREAKER_CORE = tiebreakerCore;
    }

    // Schedule proposal

    function scheduleProposal(uint256 proposalId) public onlyMember {
        (bytes memory proposalData, bytes32 key) = _encodeAproveProposal(proposalId);
        _vote(key, true);
        _pushProposal(key, uint256(ProposalType.ScheduleProposal), proposalData);
    }

    function getScheduleProposalState(uint256 proposalId)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        (, bytes32 key) = _encodeAproveProposal(proposalId);
        return _getHashState(key);
    }

    function executeScheduleProposal(uint256 proposalId) public {
        (, bytes32 key) = _encodeAproveProposal(proposalId);
        _markUsed(key);
        Address.functionCall(
            TIEBREAKER_CORE, abi.encodeWithSelector(ITiebreakerCore.scheduleProposal.selector, proposalId)
        );
    }

    function _encodeAproveProposal(uint256 proposalId) internal pure returns (bytes memory data, bytes32 key) {
        data = abi.encode(ProposalType.ScheduleProposal, data);
        key = keccak256(data);
    }

    // Sealable resume

    function sealableResume(address sealable) public {
        (bytes memory proposalData, bytes32 key,) = _encodeSealableResume(sealable);
        _vote(key, true);
        _pushProposal(key, uint256(ProposalType.ResumeSelable), proposalData);
    }

    function getSealableResumeState(address sealable)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        (, bytes32 key,) = _encodeSealableResume(sealable);
        return _getHashState(key);
    }

    function executeSealableResume(address sealable) public {
        (, bytes32 key, uint256 nonce) = _encodeSealableResume(sealable);
        _markUsed(key);
        Address.functionCall(
            TIEBREAKER_CORE, abi.encodeWithSelector(ITiebreakerCore.sealableResume.selector, sealable, nonce)
        );
    }

    function _encodeSealableResume(address sealable)
        internal
        view
        returns (bytes memory data, bytes32 key, uint256 nonce)
    {
        nonce = ITiebreakerCore(TIEBREAKER_CORE).getSealableResumeNonce(sealable);
        data = abi.encode(sealable, nonce);
        key = keccak256(data);
    }
}
