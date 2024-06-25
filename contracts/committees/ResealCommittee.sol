// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ExecutiveCommittee} from "./ExecutiveCommittee.sol";

interface IDualGovernance {
    function reseal(address[] memory sealables) external;
}

contract ResealCommittee is ExecutiveCommittee {
    address public immutable DUAL_GOVERNANCE;

    mapping(bytes32 => uint256) private _resealNonces;

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address dualGovernance,
        uint256 timelock
    ) ExecutiveCommittee(owner, committeeMembers, executionQuorum, timelock) {
        DUAL_GOVERNANCE = dualGovernance;
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

        Address.functionCall(DUAL_GOVERNANCE, abi.encodeWithSelector(IDualGovernance.reseal.selector, sealables));

        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        _resealNonces[resealNonceHash]++;
    }

    function _encodeResealData(address[] memory sealables) internal view returns (bytes memory data) {
        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        data = abi.encode(sealables, _resealNonces[resealNonceHash]);
    }
}
