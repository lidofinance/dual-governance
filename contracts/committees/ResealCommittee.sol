// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutiveCommittee} from "./ExecutiveCommittee.sol";

contract ResealCommittee is ExecutiveCommittee {
    address public immutable RESEAL_EXECUTOR;

    mapping(bytes32 => uint256) private _resealNonces;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address resealExecutor,
        uint256 timelock
    ) ExecutiveCommittee(owner, committeeMembers, executionQuorum, timelock) {
        RESEAL_EXECUTOR = resealExecutor;
    }

    function voteReseal(address[] memory sealables, bool support) public onlyMember {
        _vote(_encodeResealData(sealables), support);
    }

    function getResealState(address[] memory sealables)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getVoteState(_encodeResealData(sealables));
    }

    function executeReseal(address[] memory sealables) external {
        _markExecuted(_encodeResealData(sealables));
        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        _resealNonces[resealNonceHash]++;
    }

    function _encodeResealData(address[] memory sealables) internal view returns (bytes memory data) {
        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        data = abi.encode(sealables, _resealNonces[resealNonceHash]);
    }
}
