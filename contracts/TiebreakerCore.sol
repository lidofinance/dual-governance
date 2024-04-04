// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RestrictedMultisigBase} from "./RestrictedMultisigBase.sol";

interface IDualGovernance {
    function tiebreakerApproveProposal(uint256 _proposalId) external;
}

contract TiebreakerCore is RestrictedMultisigBase {
    uint256 public constant APPROVE_PROPOSAL = 1;

    address dualGovernance;

    constructor(
        address _owner,
        address[] memory _members,
        uint256 _quorum,
        address _dualGovernance
    ) RestrictedMultisigBase(_owner, _members, _quorum) {
        dualGovernance = _dualGovernance;
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
            uint256 proposalIdToApprove = abi.decode(_action.data, (uint256));
            IDualGovernance(dualGovernance).tiebreakerApproveProposal(proposalIdToApprove);
        } else {
            assert(false);
        }
    }

    function _buildApproveProposalAction(uint256 _proposalId) internal view returns (Action memory) {
        return Action(APPROVE_PROPOSAL, abi.encode(_proposalId), false, new address[](0));
    }
}
