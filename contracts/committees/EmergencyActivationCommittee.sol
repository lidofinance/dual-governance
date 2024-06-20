// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

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
    ) ExecutiveCommittee(OWNER, committeeMembers, executionQuorum) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;
    }

    function approveEmergencyActivate() public onlyMember {
        _vote(_hashEmergencyActivateAction(), true);
    }

    function getEmergencyActivateState()
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getActionState(_hashEmergencyActivateAction());
    }

    function executeEmergencyActivate() external {
        _markExecute(_hashEmergencyActivateAction());
        IEmergencyProtectedTimelock(EMERGENCY_PROTECTED_TIMELOCK).emergencyActivate();
    }

    function _hashEmergencyActivateAction() internal view returns (Action memory) {
        return keccak256("EMERGENCY_ACTIVATE");
    }
}
