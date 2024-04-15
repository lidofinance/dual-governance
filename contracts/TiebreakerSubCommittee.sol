// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RestrictedMultisigBase} from "./RestrictedMultisigBase.sol";

contract TiebreakerSubCommittee is RestrictedMultisigBase {
    address immutable TIEBREAKER_CORE;

    constructor(
        address owner,
        address[] memory multisigMembers,
        uint256 executionQuorum,
        address tiebreakerCore
    ) RestrictedMultisigBase(owner, multisigMembers, executionQuorum) {
        TIEBREAKER_CORE = tiebreakerCore;
    }

    function voteApproveProposal(uint256 _proposalId, bool _supports) public onlyMember {
        _vote(_buildApproveProposalAction(_proposalId), _supports);
    }

    function getApproveProposalState(uint256 _proposalId)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return getActionState(_buildApproveProposalAction(_proposalId));
    }

    function executeApproveProposal(uint256 _proposalId) public {
        _execute(_buildApproveProposalAction(_proposalId));
    }

    function _buildApproveProposalAction(uint256 _proposalId) internal view returns (Action memory) {
        return Action(TIEBREAKER_CORE, abi.encodeWithSignature("approveProposal(uint256)", _proposalId));
    }
}
