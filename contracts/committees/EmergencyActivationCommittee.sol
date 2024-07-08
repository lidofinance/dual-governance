// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HashConsensus} from "./HashConsensus.sol";

interface IEmergencyProtectedTimelock {
    function emergencyActivate() external;
}

contract EmergencyActivationCommittee is HashConsensus {
    address public immutable EMERGENCY_PROTECTED_TIMELOCK;

    bytes32 private constant EMERGENCY_ACTIVATION_HASH = keccak256("EMERGENCY_ACTIVATE");

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) HashConsensus(owner, committeeMembers, executionQuorum, 0) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;
    }

    function approveEmergencyActivate() public onlyMember {
        _vote(EMERGENCY_ACTIVATION_HASH, true);
    }

    function getEmergencyActivateState()
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getHashState(EMERGENCY_ACTIVATION_HASH);
    }

    function executeEmergencyActivate() external {
        _markUsed(EMERGENCY_ACTIVATION_HASH);
        Address.functionCall(
            EMERGENCY_PROTECTED_TIMELOCK, abi.encodeWithSelector(IEmergencyProtectedTimelock.emergencyActivate.selector)
        );
    }
}
