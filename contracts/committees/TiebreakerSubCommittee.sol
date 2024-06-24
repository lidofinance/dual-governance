// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutiveCommittee} from "./ExecutiveCommittee.sol";

interface ITiebreakerCore {
    function getSealableResumeNonce(address sealable) external view returns (uint256 nonce);
    function approveProposal(uint256 _proposalId) external;
    function approveSealableResume(address sealable, uint256 nonce) external;
}

contract TiebreakerSubCommittee is ExecutiveCommittee {
    address immutable TIEBREAKER_CORE;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address tiebreakerCore
    ) ExecutiveCommittee(owner, committeeMembers, executionQuorum) {
        TIEBREAKER_CORE = tiebreakerCore;
    }

    // Approve proposal

    function voteApproveProposal(uint256 proposalId, bool support) public onlyMember {
        _vote(_encodeApproveProposalData(proposalId), support);
    }

    function getApproveProposalState(uint256 proposalId)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getVoteState(_encodeApproveProposalData(proposalId));
    }

    function executeApproveProposal(uint256 proposalId) public {
        _markExecuted(_encodeApproveProposalData(proposalId));
        ITiebreakerCore(TIEBREAKER_CORE).approveProposal(proposalId);
    }

    // Approve unpause sealable

    function voteApproveSealableResume(address sealable, bool support) public {
        _vote(_encodeApproveSealableResumeData(sealable), support);
    }

    function getApproveSealableResumeState(address sealable)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getVoteState(_encodeApproveSealableResumeData(sealable));
    }

    function executeApproveSealableResume(address sealable) public {
        _markExecuted(_encodeApproveSealableResumeData(sealable));
        uint256 nonce = ITiebreakerCore(TIEBREAKER_CORE).getSealableResumeNonce(sealable);
        ITiebreakerCore(TIEBREAKER_CORE).approveSealableResume(sealable, nonce);
    }

    function _encodeApproveSealableResumeData(address sealable) internal view returns (bytes memory data) {
        uint256 nonce = ITiebreakerCore(TIEBREAKER_CORE).getSealableResumeNonce(sealable);
        data = abi.encode(sealable, nonce);
    }

    function _encodeApproveProposalData(uint256 proposalId) internal pure returns (bytes memory data) {
        data = abi.encode(proposalId);
    }
}
