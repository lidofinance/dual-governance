// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RestrictedMultisigBase} from "./RestrictedMultisigBase.sol";

interface IEmergencyProtectedTimelock {
    function emergencyActivate() external;
}

contract EmergencyActivationMultisig is RestrictedMultisigBase {
    uint256 public constant EMERGENCY_ACTIVATE = 1;

    address emergencyProtectedTimelock;

    constructor(
        address _owner,
        address[] memory _members,
        uint256 _quorum,
        address _emergencyProtectedTimelock
    ) RestrictedMultisigBase(_owner, _members, _quorum) {
        emergencyProtectedTimelock = _emergencyProtectedTimelock;
    }

    function voteEmergencyActivate() public onlyMember {
        _vote(_buildEmergencyActivateAction(), true);
    }

    function getEmergencyActivateState() public returns (uint256 support, uint256 ExecutionQuorum, bool isExecuted) {
        return _getState(_buildEmergencyActivateAction());
    }

    function emergencyActivate() external {
        _execute(_buildEmergencyActivateAction());
    }

    function _issueCalls(Action memory _action) internal override {
        if (_action.actionType == EMERGENCY_ACTIVATE) {
            IEmergencyProtectedTimelock(emergencyProtectedTimelock).emergencyActivate();
        } else {
            assert(false);
        }
    }

    function _buildEmergencyActivateAction() internal view returns (Action memory) {
        return Action(EMERGENCY_ACTIVATE, new bytes(0), false, new address[](0));
    }
}
