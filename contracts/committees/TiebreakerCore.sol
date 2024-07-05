// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HashConsensus} from "./HashConsensus.sol";
import {ProposalsList} from "./ProposalsList.sol";

interface IDualGovernance {
    function tiebreakerScheduleProposal(uint256 proposalId) external;
    function tiebreakerResumeSealable(address sealable) external;
}

enum ProposalType {
    ScheduleProposal,
    ResumeSelable
}

contract TiebreakerCore is HashConsensus, ProposalsList {
    error ResumeSealableNonceMismatch();

    address immutable DUAL_GOVERNANCE;

    mapping(address => uint256) private _sealableResumeNonces;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address dualGovernance,
        uint256 timelock
    ) HashConsensus(owner, committeeMembers, executionQuorum, timelock) {
        DUAL_GOVERNANCE = dualGovernance;
    }

    // Schedule proposal

    function scheduleProposal(uint256 proposalId) public onlyMember {
        (bytes memory proposalData, bytes32 key) = _encodeScheduleProposal(proposalId);
        _vote(key, true);
        _pushProposal(key, uint256(ProposalType.ScheduleProposal), proposalData);
    }

    function getScheduleProposalState(uint256 proposalId)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        (, bytes32 key) = _encodeScheduleProposal(proposalId);
        return _getHashState(key);
    }

    function executeScheduleProposal(uint256 proposalId) public {
        (, bytes32 key) = _encodeScheduleProposal(proposalId);
        _markUsed(key);
        Address.functionCall(
            DUAL_GOVERNANCE, abi.encodeWithSelector(IDualGovernance.tiebreakerScheduleProposal.selector, proposalId)
        );
    }

    function _encodeScheduleProposal(uint256 proposalId) internal pure returns (bytes memory data, bytes32 key) {
        data = abi.encode(ProposalType.ScheduleProposal, proposalId);
        key = keccak256(data);
    }

    // Resume sealable

    function getSealableResumeNonce(address sealable) public view returns (uint256) {
        return _sealableResumeNonces[sealable];
    }

    function sealableResume(address sealable, uint256 nonce) public onlyMember {
        if (nonce != _sealableResumeNonces[sealable]) {
            revert ResumeSealableNonceMismatch();
        }
        (bytes memory proposalData, bytes32 key) = _encodeSealableResume(sealable, nonce);
        _vote(key, true);
        _pushProposal(key, uint256(ProposalType.ResumeSelable), proposalData);
    }

    function getSealableResumeState(
        address sealable,
        uint256 nonce
    ) public view returns (uint256 support, uint256 execuitionQuorum, bool isExecuted) {
        (, bytes32 key) = _encodeSealableResume(sealable, nonce);
        return _getHashState(key);
    }

    function executeSealableResume(address sealable) external {
        (, bytes32 key) = _encodeSealableResume(sealable, _sealableResumeNonces[sealable]);
        _markUsed(key);
        _sealableResumeNonces[sealable]++;
        Address.functionCall(
            DUAL_GOVERNANCE, abi.encodeWithSelector(IDualGovernance.tiebreakerResumeSealable.selector, sealable)
        );
    }

    function _encodeSealableResume(
        address sealable,
        uint256 nonce
    ) private pure returns (bytes memory data, bytes32 key) {
        data = abi.encode(ProposalType.ResumeSelable, sealable, nonce);
        key = keccak256(data);
    }
}
