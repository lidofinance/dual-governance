// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutiveCommittee} from "./ExecutiveCommittee.sol";

contract EmergencyActivationCommittee is ExecutiveCommittee {
    address public immutable EMERGENCY_PROTECTED_TIMELOCK;

    constructor(
        address OWNER,
        address[] memory multisigMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) ExecutiveCommittee(OWNER, multisigMembers, executionQuorum) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;
    }

    function approveEmergencyActivate() public onlyMember {
        _vote(_buildEmergencyActivateAction(), true);
    }

    function getEmergencyActivateState()
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return getActionState(_buildEmergencyActivateAction());
    }

    function executeEmergencyActivate() external {
        _execute(_buildEmergencyActivateAction());
    }

    function _buildEmergencyActivateAction() internal view returns (Action memory) {
        return Action(EMERGENCY_PROTECTED_TIMELOCK, abi.encodeWithSignature("emergencyActivate()"), new bytes(0));
    }
}
