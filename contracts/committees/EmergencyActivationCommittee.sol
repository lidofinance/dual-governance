// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ExecutiveCommittee} from "./ExecutiveCommittee.sol";

interface IEmergencyProtectedTimelock {
    function emergencyActivate() external;
}

contract EmergencyActivationCommittee is ExecutiveCommittee {
    address public immutable EMERGENCY_PROTECTED_TIMELOCK;

    constructor(
        address OWNER,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) ExecutiveCommittee(OWNER, committeeMembers, executionQuorum, 0) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;
    }

    function approveEmergencyActivate() public onlyMember {
        _vote(_encodeEmergencyActivateData(), true);
    }

    function getEmergencyActivateState()
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getVoteState(_encodeEmergencyActivateData());
    }

    function executeEmergencyActivate() external {
        _markExecuted(_encodeEmergencyActivateData());
        Address.functionCall(
            EMERGENCY_PROTECTED_TIMELOCK, abi.encodeWithSelector(IEmergencyProtectedTimelock.emergencyActivate.selector)
        );
    }

    function _encodeEmergencyActivateData() internal pure returns (bytes memory data) {
        data = bytes("EMERGENCY_ACTIVATE");
    }
}
