// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HashConsensus} from "./HashConsensus.sol";
import {ProposalsList} from "./ProposalsList.sol";

interface IDualGovernance {
    function reseal(address[] memory sealables) external;
}

contract ResealCommittee is HashConsensus, ProposalsList {
    address public immutable DUAL_GOVERNANCE;

    mapping(bytes32 => uint256) private _resealNonces;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address dualGovernance,
        uint256 timelock
    ) HashConsensus(owner, committeeMembers, executionQuorum, timelock) {
        DUAL_GOVERNANCE = dualGovernance;
    }

    function voteReseal(address[] memory sealables, bool support) public onlyMember {
        (bytes memory proposalData, bytes32 key) = _encodeResealProposal(sealables);
        _vote(key, support);
        _pushProposal(key, 0, proposalData);
    }

    function getResealState(address[] memory sealables)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        (, bytes32 key) = _encodeResealProposal(sealables);
        return _getHashState(key);
    }

    function executeReseal(address[] memory sealables) external {
        (, bytes32 key) = _encodeResealProposal(sealables);
        _markUsed(key);

        Address.functionCall(DUAL_GOVERNANCE, abi.encodeWithSelector(IDualGovernance.reseal.selector, sealables));

        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        _resealNonces[resealNonceHash]++;
    }

    function _encodeResealProposal(address[] memory sealables) internal view returns (bytes memory data, bytes32 key) {
        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        data = abi.encode(sealables, _resealNonces[resealNonceHash]);
        key = keccak256(data);
    }
}
