// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {ISealable} from "./interfaces/ISealable.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";
import {IResealManager} from "./interfaces/IResealManager.sol";

/// @title Reseal Manager
/// @notice Allows to extend pause of temporarily paused contracts to permanent pause or resume it.
contract ResealManager is IResealManager {
    // ---
    // Errors
    // ---

    error SealableWrongPauseState();
    error CallerIsNotGovernance(address caller);

    // ---
    // Immutables & Constants
    // ---

    uint256 public constant PAUSE_INFINITELY = type(uint256).max;
    ITimelock public immutable EMERGENCY_PROTECTED_TIMELOCK;

    // ---
    // Constructor
    // ---

    /// @notice Initializes the ResealManager contract.
    /// @param emergencyProtectedTimelock The address of the Timelock contract.
    constructor(ITimelock emergencyProtectedTimelock) {
        EMERGENCY_PROTECTED_TIMELOCK = emergencyProtectedTimelock;
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Extends the pause of the specified sealable contract.
    /// @dev Works only if conditions are met:
    /// - ResealManager has PAUSE_ROLE and RESUME_ROLE for target contract;
    /// - Contract are paused until timestamp after current timestamp and not for infinite time;
    /// - Function is called by the governance contract.
    /// @param sealable The address of the sealable contract.
    function reseal(address sealable) external {
        _checkCallerIsGovernance();

        uint256 sealableResumeSinceTimestamp = ISealable(sealable).getResumeSinceTimestamp();
        if (block.timestamp >= sealableResumeSinceTimestamp || sealableResumeSinceTimestamp == PAUSE_INFINITELY) {
            revert SealableWrongPauseState();
        }
        Address.functionCall(sealable, abi.encodeWithSelector(ISealable.resume.selector));
        Address.functionCall(sealable, abi.encodeWithSelector(ISealable.pauseFor.selector, PAUSE_INFINITELY));
    }

    /// @notice Resumes the specified sealable contract if it is paused.
    /// @dev Works only if conditions are met:
    /// - ResealManager has RESUME_ROLE for target contract;
    /// - Contract are paused until timestamp after current timestamp;
    /// - Function is called by the governance contract.
    /// @param sealable The address of the sealable contract.
    function resume(address sealable) external {
        _checkCallerIsGovernance();

        uint256 sealableResumeSinceTimestamp = ISealable(sealable).getResumeSinceTimestamp();
        if (block.timestamp >= sealableResumeSinceTimestamp) {
            revert SealableWrongPauseState();
        }
        Address.functionCall(sealable, abi.encodeWithSelector(ISealable.resume.selector));
    }

    // ---
    // Internal methods
    // ---

    /// @notice Ensures that the function can only be called by the governance address.
    function _checkCallerIsGovernance() internal view {
        address governance = EMERGENCY_PROTECTED_TIMELOCK.getGovernance();
        if (msg.sender != governance) {
            revert CallerIsNotGovernance(msg.sender);
        }
    }
}
