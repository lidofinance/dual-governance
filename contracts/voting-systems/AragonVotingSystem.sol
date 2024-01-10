// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IVotingSystem} from "./IVotingSystem.sol";


interface IAragonVoting {
    function voteTime() external view returns (uint64);
    function newVote(bytes calldata executionScript, string calldata metadata) external returns (uint256);
    function executeVote(uint256 voteId) external;
}


contract AragonVotingSystem is IVotingSystem {
    error InsufficientLdoBalanceToSubmitProposal();

    address internal immutable VOTING;
    address internal immutable LDO_TOKEN;

    constructor(address voting, address ldoToken) {
        VOTING = voting;
        LDO_TOKEN = ldoToken;
    }

    function submitProposal(bytes calldata data, address submitter) external returns (uint256 id, uint256 decidedAt) {
        if (!_isAllowedToSubmitProposal(submitter)) {
            revert InsufficientLdoBalanceToSubmitProposal();
        }
        uint256 voteId = IAragonVoting(VOTING).newVote(data, "");
        uint256 voteDuration = IAragonVoting(VOTING).voteTime();
        return (voteId, _getTime() + voteDuration);
    }

    function _isAllowedToSubmitProposal(address submitter) internal returns (bool) {
        // TODO: check submitter is allowed to start a vote (check min LDO balance)
        return true;
    }

    function getProposalExecData(uint256 id) external view returns (address target, bytes memory data) {
        target = VOTING;
        data = abi.encodeWithSelector(IAragonVoting.executeVote.selector, id);
    }

    function isValidExecutionForwarder(address addr) external view returns (bool) {
        return addr == VOTING;
    }

    function _getTime() internal vitrual view returns (uint256) {
        return block.timestamp;
    }
}
