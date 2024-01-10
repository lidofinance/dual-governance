// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {TimelockCallSet} from "./TimelockCallSet.sol";


contract Agent {
    using TimelockCallSet for TimelockCallSet.Set;

    error Unauthorized();
    error EmergencyMultisigExpired();

    event GovernanceSet(address indexed governance);
    event TimelockDurationSet(uint256 duration);
    event EmergencyMultisigSet(address indexed emergencyMultisig);
    event EmergencyMultisigExpirationTimeSet(uint256 indexed activeTill);
    event CallExecuted(address indexed target, bytes data);
    event CallScheduled(uint256 indexed callId, uint256 indexed lockedTill, address indexed target, bytes data);
    event ScheduledCallExecuted(uint256 indexed callId);
    event ScheduledCallsCancelled();
    event GovernanceEmergencyResetToDAO();

    address internal immutable DAO_AGENT;

    address internal _governance;
    uint256 internal _timelockDuration;
    TimelockCallSet.Set internal _timelockCallSet;
    address internal _emergencyMultisig;
    uint256 internal _emergencyMultisigActiveTill;

    constructor(address daoAgent, address governance) {
        DAO_AGENT = daoAgent;
        _setGovernance(governance, 0);
    }

    function getGovernance() external view returns (address) {
        return _governance;
    }

    function getEmergencyMultisig() external returns (address emergencyMultisig, uint256 activeTill) {
        return (_emergencyMultisig, _emergencyMultisigActiveTill);
    }

    function setGovernance(address governance, uint256 timelockDuration) external {
        if (msg.sender != address(this)) {
            revert Unauthorized();
        }
        _setGovernance(governance, timelockDuration);
    }

    function setEmergencyMultisig(address emergencyMultisig, uint256 emergencyMultisigActiveFor) external {
        if (msg.sender != address(this)) {
            revert Unauthorized();
        }
        _setEmergencyMultisig(emergencyMultisig, emergencyMultisigActiveFor);
    }

    function emergencyResetGovernanceToDAO() external {
        _assertCalledByEmergencyMultisig();
        _cancelScheduledCalls();
        _setGovernance(DAO_AGENT, 0);
        _setEmergencyMultisig(address(0), 0);
        emit GovernanceEmergencyResetToDAO();
    }

    function emergencyCancelScheduledCalls() external {
        _assertCalledByEmergencyMultisig();
        _cancelScheduledCalls();
    }

    function forwardCall(address target, bytes calldata data) external {
        if (msg.sender != _governance) {
            revert Unauthorized();
        }
        uint256 timelockDuration = _timelockDuration;
        if (timelockDuration == 0) {
            _call(target, data);
        } else {
            uint256 timestamp = _getTime();
            uint256 lockedTill = timestamp + timelockDuration;
            uint256 callId = _timelockCallSet.add(timestamp, lockedTill, target, data);
            emit CallScheduled(callId, lockedTill, target, data);
        }
    }

    function executeScheduledCall(uint256 callId) external {
        TimelockCallSet.Call memory call = _timelockCallSet.removeForExecution(callId, _getTime());
        _call(call.target, call.data);
        emit ScheduledCallExecuted(callId);
    }

    function getExecutableCallIds() external view returns (uint256[] memory) {
        return _timelockCallSet.getExecutableIds(_getTime());
    }

    function getScheduledCall(uint256 callId) external view returns (TimelockCallSet.Call memory) {
        return _timelockCallSet.get(callId);
    }

    function _call(address target, bytes memory data) internal {
        (bool success, bytes memory output) = target.call(data);
        if (!success) {
            assembly {
                revert(output, mload(output))
            }
        }
        emit CallExecuted(target, data);
    }

    function _cancelScheduledCalls() internal {
        _timelockCallSet.cancelCallsTill(_getTime());
        emit ScheduledCallsCancelled();
    }

    function _assertCalledByEmergencyMultisig() internal view {
        if (msg.sender != _emergencyMultisig) {
            revert Unauthorized();
        }
        if (_getTime() >= _emergencyMultisigActiveTill) {
            revert EmergencyMultisigExpired();
        }
    }

    function _setGovernance(address governance, uint256 timelockDuration) internal {
        if (governance != _governance) {
            _governance = governance;
            emit GovernanceSet(governance);
        }
        if (timelockDuration != _timelockDuration) {
            _timelockDuration = timelockDuration;
            emit TimelockDurationSet(timelockDuration);
        }
    }

    function _setEmergencyMultisig(address emergencyMultisig, uint256 emergencyMultisigActiveFor) internal {
        if (_emergencyMultisig != emergencyMultisig) {
            _emergencyMultisig = emergencyMultisig;
            emit EmergencyMultisigSet(emergencyMultisig);
        }
        uint256 emergencyMultisigActiveTill = _getTime() + emergencyMultisigActiveFor;
        if (_emergencyMultisigActiveTill != emergencyMultisigActiveTill) {
            _emergencyMultisigActiveTill = emergencyMultisigActiveTill;
            emit EmergencyMultisigExpirationTimeSet(emergencyMultisigActiveTill);
        }
    }

    function _getTime() internal virtual view returns (uint256) {
        return block.timestamp;
    }
}
