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
        address resealExecutor
    ) ExecutiveCommittee(owner, committeeMembers, executionQuorum) {
        RESEAL_EXECUTOR = resealExecutor;
    }

    function voteReseal(address[] memory sealables, bool support) public onlyMember {
        _vote(_buildResealAction(sealables), support);
    }

    function getResealState(address[] memory sealables)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return getActionState(_buildResealAction(sealables));
    }

    function executeReseal(address[] memory sealables) external {
        _execute(_buildResealAction(sealables));
        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        _resealNonces[resealNonceHash]++;
    }

    function _buildResealAction(address[] memory sealables) internal view returns (Action memory) {
        bytes32 resealNonceHash = keccak256(abi.encode(sealables));
        return Action(
            RESEAL_EXECUTOR,
            abi.encodeWithSignature("reseal(address[])", sealables),
            abi.encode(_resealNonces[resealNonceHash])
        );
    }
}
