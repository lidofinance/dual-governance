// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutiveCommittee} from "./ExecutiveCommittee.sol";

interface ITiebreakerCore {
    function getSealableResumeNonce(address sealable) external view returns (uint256 nonce);
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
        _vote(_buildApproveProposalAction(proposalId), support);
    }

    function getApproveProposalState(uint256 proposalId)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return getActionState(_buildApproveProposalAction(proposalId));
    }

    function executeApproveProposal(uint256 proposalId) public {
        _execute(_buildApproveProposalAction(proposalId));
    }

    // Approve unpause sealable

    function voteApproveSealableResume(address sealable, bool support) public {
        _vote(_buildApproveSealableResumeAction(sealable), support);
    }

    function getApproveSealableResumeState(address sealable)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return getActionState(_buildApproveSealableResumeAction(sealable));
    }

    function executeApproveSealableResume(address sealable) public {
        _execute(_buildApproveSealableResumeAction(sealable));
    }

    function _buildApproveSealableResumeAction(address sealable) internal view returns (Action memory) {
        uint256 nonce = ITiebreakerCore(TIEBREAKER_CORE).getSealableResumeNonce(sealable);
        return Action(
            TIEBREAKER_CORE,
            abi.encodeWithSignature("approveSealableResume(address,uint256)", sealable, nonce),
            new bytes(0)
        );
    }

    function _buildApproveProposalAction(uint256 proposalId) internal view returns (Action memory) {
        return Action(TIEBREAKER_CORE, abi.encodeWithSignature("approveProposal(uint256)", proposalId), new bytes(0));
    }
}
