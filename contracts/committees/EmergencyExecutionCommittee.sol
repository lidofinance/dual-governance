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
    ) ExecutiveCommittee(OWNER, committeeMembers, executionQuorum, 0) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;
    }

    // Emergency Execution

    function voteEmergencyExecute(uint256 _proposalId, bool _supports) public onlyMember {
        _vote(_encodeEmergencyExecuteData(_proposalId), _supports);
    }

    function getEmergencyExecuteState(uint256 _proposalId)
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getVoteState(_encodeEmergencyExecuteData(_proposalId));
    }

    function executeEmergencyExecute(uint256 _proposalId) public {
        _markExecuted(_encodeEmergencyExecuteData(_proposalId));
        IEmergencyProtectedTimelock(EMERGENCY_PROTECTED_TIMELOCK).emergencyExecute(_proposalId);
    }

    // Governance reset

    function approveEmergencyReset() public onlyMember {
        _vote(_dataEmergencyResetData(), true);
    }

    function getEmergencyResetState()
        public
        view
        returns (uint256 support, uint256 execuitionQuorum, bool isExecuted)
    {
        return _getVoteState(_dataEmergencyResetData());
    }

    function executeEmergencyReset() external {
        _markExecuted(_dataEmergencyResetData());
        IEmergencyProtectedTimelock(EMERGENCY_PROTECTED_TIMELOCK).emergencyReset();
    }

    function _dataEmergencyResetData() internal pure returns (bytes memory data) {
        data = bytes("EMERGENCY_RESET");
    }

    function _encodeEmergencyExecuteData(uint256 proposalId) internal pure returns (bytes memory data) {
        data = abi.encode(proposalId);
    }
}
