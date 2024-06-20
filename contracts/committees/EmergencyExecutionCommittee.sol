// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ExecutiveCommittee} from "./ExecutiveCommittee.sol";

interface IEmergencyProtectedTimelock {
    function emergencyExecute(uint256 proposalId) external;
    function emergencyReset() external;
}

contract EmergencyExecutionCommittee is ExecutiveCommittee {
    address public immutable EMERGENCY_PROTECTED_TIMELOCK;

    constructor(
        address OWNER,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) ExecutiveCommittee(OWNER, committeeMembers, executionQuorum) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;
    }

    // Emergency Execution

    function voteEmergencyExecute(uint256 _proposalId, bool _supports) public onlyMember {
        _vote(_buildEmergencyExecuteAction(_proposalId), _supports);
    }

    function getEmergencyExecuteState(uint256 _proposalId)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getActionState(_buildEmergencyExecuteAction(_proposalId));
    }

    function executeEmergencyExecute(uint256 _proposalId) public {
        _execute(_buildEmergencyExecuteAction(_proposalId));
    }

    // Governance reset

    function approveEmergencyReset() public onlyMember {
        _vote(_buildEmergencyResetAction(), true);
    }

    function getEmergencyResetState()
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getActionState(_buildEmergencyResetAction());
    }

    function executeEmergencyReset() external {
        _execute(_buildEmergencyResetAction());
    }

    function _buildEmergencyResetAction() internal view returns (Action memory) {
        return Action(EMERGENCY_PROTECTED_TIMELOCK, abi.encodeWithSignature("emergencyReset()"), new bytes(0));
    }

    function _buildEmergencyExecuteAction(uint256 proposalId) internal view returns (Action memory) {
        return Action(
            EMERGENCY_PROTECTED_TIMELOCK, abi.encodeWithSignature("emergencyExecute(uint256)", proposalId), new bytes(0)
        );
    }
}
