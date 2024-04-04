// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RestrictedMultisigBase} from "./RestrictedMultisigBase.sol";

interface ITiebreakerCore {
    function voteApproveProposal(uint256 _proposalId, bool _supports) external;
}

contract TiebreakerSubDAO is RestrictedMultisigBase {
    uint256 public constant APPROVE_PROPOSAL = 1;

    address tiebreakerCore;

    constructor(
        address _owner,
        address[] memory _members,
        uint256 _quorum,
        address _tiebreakerCore
    ) RestrictedMultisigBase(_owner, _members, _quorum) {
        tiebreakerCore = _tiebreakerCore;
    }

    function voteApproveProposal(uint256 _proposalId, bool _supports) public onlyMember {
        _vote(_buildApproveProposalAction(_proposalId), _supports);
    }

    function getApproveProposalState(uint256 _proposalId)
        public
        returns (uint256 support, uint256 ExecutionQuorum, bool isExecuted)
    {
        return _getState(_buildApproveProposalAction(_proposalId));
    }

    function approveProposal(uint256 _proposalId) public {
        _execute(_buildApproveProposalAction(_proposalId));
    }

    function _issueCalls(Action memory _action) internal override {
        if (_action.actionType == APPROVE_PROPOSAL) {
            uint256 proposalIdToExecute = abi.decode(_action.data, (uint256));
            ITiebreakerCore(tiebreakerCore).voteApproveProposal(proposalIdToExecute, true);
        } else {
            assert(false);
        }
    }

    function _buildApproveProposalAction(uint256 proposalId) internal view returns (Action memory) {
        return Action(APPROVE_PROPOSAL, abi.encode(proposalId), false, new address[](0));
    }
}
