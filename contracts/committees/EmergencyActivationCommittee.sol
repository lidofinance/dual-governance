// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {HashConsensus} from "./HashConsensus.sol";
import {ITimelock} from "../interfaces/ITimelock.sol";
import {Duration, Durations} from "../types/Duration.sol";
import {Timestamp} from "../types/Timestamp.sol";

/// @title Emergency Activation Committee Contract
/// @notice This contract allows a committee to approve and execute an emergency activation
/// @dev Inherits from HashConsensus to utilize voting and consensus mechanisms
contract EmergencyActivationCommittee is HashConsensus {
    address public immutable EMERGENCY_PROTECTED_TIMELOCK;

    bytes32 private constant EMERGENCY_ACTIVATION_HASH = keccak256("EMERGENCY_ACTIVATE");

    constructor(
        address owner,
        address[] memory committeeMembers,
        uint256 executionQuorum,
        address emergencyProtectedTimelock
    ) HashConsensus(owner, Durations.from(0)) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;

        _addMembers(committeeMembers, executionQuorum);
    }

    /// @notice Approves the emergency activation by casting a vote
    /// @dev Only callable by committee members
    function approveActivateEmergencyMode() public {
        _checkCallerIsMember();
        _vote(EMERGENCY_ACTIVATION_HASH, true);
    }

    /// @notice Gets the current state of the emergency activation vote
    /// @return support The number of votes in support of the activation
    /// @return executionQuorum The required number of votes for execution
    /// @return quorumAt The timestamp when the quorum was reached
    /// @return isExecuted Whether the activation has been executed
    function getActivateEmergencyModeState()
        public
        view
        returns (uint256 support, uint256 executionQuorum, Timestamp quorumAt, bool isExecuted)
    {
        return _getHashState(EMERGENCY_ACTIVATION_HASH);
    }

    /// @notice Executes the emergency activation if the quorum is reached
    /// @dev Calls the emergencyActivate function on the Emergency Protected Timelock contract
    function executeActivateEmergencyMode() external {
        _markUsed(EMERGENCY_ACTIVATION_HASH);
        Address.functionCall(
            EMERGENCY_PROTECTED_TIMELOCK, abi.encodeWithSelector(ITimelock.activateEmergencyMode.selector)
        );
    }
}
