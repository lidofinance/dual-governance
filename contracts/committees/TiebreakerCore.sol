// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutiveCommittee} from "./ExecutiveCommittee.sol";

interface IDualGovernance {
    function tiebreakerApproveProposal(uint256 proposalId) external;
    function tiebreakerApproveSealableResume(address sealable) external;
}

contract TiebreakerCore is ExecutiveCommittee {
    error ResumeSealableNonceMismatch();

    address immutable DUAL_GOVERNANCE;

    mapping(address => uint256) private _sealableResumeNonces;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address dualGovernance
    ) ExecutiveCommittee(owner, committeeMembers, executionQuorum, 0) {
        DUAL_GOVERNANCE = dualGovernance;
    }

    // Approve proposal

    function approveProposal(uint256 proposalId) public onlyMember {
        _vote(_encodeAproveProposalData(proposalId), true);
    }

    function getApproveProposalState(uint256 proposalId)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getVoteState(_encodeAproveProposalData(proposalId));
    }

    function executeApproveProposal(uint256 proposalId) public {
        _markExecuted(_encodeAproveProposalData(proposalId));
        IDualGovernance(DUAL_GOVERNANCE).tiebreakerApproveProposal(proposalId);
    }

    // Resume sealable

    function getSealableResumeNonce(address sealable) public view returns (uint256) {
        return _sealableResumeNonces[sealable];
    }

    function approveSealableResume(address sealable, uint256 nonce) public onlyMember {
        if (nonce != _sealableResumeNonces[sealable]) {
            revert ResumeSealableNonceMismatch();
        }
        _vote(_encodeSealableResumeData(sealable, nonce), true);
    }

    function getSealableResumeState(
        address sealable,
        uint256 nonce
    ) public view returns (uint256 support, uint256 execuitionQuorum, bool isExecuted) {
        return _getVoteState(_encodeSealableResumeData(sealable, nonce));
    }

    function executeSealableResume(address sealable) external {
        _markExecuted(_encodeSealableResumeData(sealable, _sealableResumeNonces[sealable]));
        _sealableResumeNonces[sealable]++;
        IDualGovernance(DUAL_GOVERNANCE).tiebreakerApproveSealableResume(sealable);
    }

    function _encodeAproveProposalData(uint256 proposalId) internal pure returns (bytes memory data) {
        data = abi.encode(proposalId);
    }

    function _encodeSealableResumeData(address sealable, uint256 nonce) internal pure returns (bytes memory data) {
        data = abi.encode(sealable, nonce);
    }
}
