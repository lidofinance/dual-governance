// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RestrictedMultisigBase} from "./RestrictedMultisigBase.sol";

contract TiebreakerCore is RestrictedMultisigBase {
    error ResumeSealableNonceMismatch();

    address immutable DUAL_GOVERNANCE;

    mapping(address => uint256) public _sealableResumeNonces;

    constructor(
        address owner,
        address[] memory multisigMembers,
        uint256 executionQuorum,
        address dualGovernance
    ) RestrictedMultisigBase(owner, multisigMembers, executionQuorum) {
        DUAL_GOVERNANCE = dualGovernance;
    }

    // Approve proposal

    function approveProposal(uint256 _proposalId) public onlyMember {
        _vote(_buildApproveProposalAction(_proposalId), true);
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

    // Resume sealable

    function getSealableResumeNonce(address sealable) public view returns (uint256) {
        return _sealableResumeNonces[sealable];
    }

    function approveSealableResume(address sealable, uint256 nonce) public {
        if (nonce != _sealableResumeNonces[sealable]) {
            revert ResumeSealableNonceMismatch();
        }
        _vote(_buildSealableResumeAction(sealable, nonce), true);
    }

    function getSealableResumeState(
        address sealable,
        uint256 nonce
    ) public view returns (uint256 support, uint256 execuitionQuorum, bool isExecuted) {
        return getActionState(_buildSealableResumeAction(sealable, nonce));
    }

    function executeSealableResume(address sealable, uint256 nonce) external {
        if (nonce != _sealableResumeNonces[sealable]) {
            revert ResumeSealableNonceMismatch();
        }
        _execute(_buildSealableResumeAction(sealable, nonce));
        _sealableResumeNonces[sealable]++;
    }

    function _buildApproveProposalAction(uint256 _proposalId) internal view returns (Action memory) {
        return Action(
            DUAL_GOVERNANCE, abi.encodeWithSignature("tiebreakerApproveProposal(uint256)", _proposalId), new bytes(0)
        );
    }

    function _buildSealableResumeAction(address sealable, uint256 nonce) internal view returns (Action memory) {
        return Action(
            DUAL_GOVERNANCE,
            abi.encodeWithSignature("tiebreakerApproveSealableResume(uint256)", sealable),
            abi.encode(nonce)
        );
    }
}
