// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IResealManager} from "../interfaces/IResealManager.sol";

/// @title Resealer Library
/// @dev Library for managing sealing operations for critical components of Lido protocol.
library Resealer {
    // ---
    // Errors
    // ---
    error InvalidResealManager(IResealManager resealManager);
    error InvalidResealCommittee(address resealCommittee);
    error CallerIsNotResealCommittee(address caller);

    // ---
    // Events
    // ---
    event ResealCommitteeSet(address resealCommittee);
    event ResealManagerSet(IResealManager resealManager);

    // ---
    // Data Types
    // ---

    /// @dev Struct to hold the context of the reseal operations.
    /// @param resealManager The address of the Reseal Manager.
    /// @param resealCommittee The address of the Reseal Committee which is allowed to "reseal" sealables paused for a limited
    /// period of time when the Dual Governance proposal adoption is blocked.
    struct Context {
        IResealManager resealManager;
        address resealCommittee;
    }

    /// @dev Sets a new Reseal Manager contract address.
    /// @param self The context struct containing the current state.
    /// @param newResealManager The address of the new Reseal Manager.
    function setResealManager(Context storage self, IResealManager newResealManager) internal {
        if (newResealManager == self.resealManager || address(newResealManager) == address(0)) {
            revert InvalidResealManager(newResealManager);
        }
        self.resealManager = newResealManager;
        emit ResealManagerSet(newResealManager);
    }

    /// @dev Sets a new reseal committee address.
    /// @param self The context struct containing the current state.
    /// @param newResealCommittee The address of the new reseal committee.
    function setResealCommittee(Context storage self, address newResealCommittee) internal {
        if (newResealCommittee == self.resealCommittee) {
            revert InvalidResealCommittee(newResealCommittee);
        }
        self.resealCommittee = newResealCommittee;
        emit ResealCommitteeSet(newResealCommittee);
    }

    /// @dev Checks if the caller is the reseal committee.
    /// @param self The context struct containing the current state.
    function checkCallerIsResealCommittee(Context storage self) internal view {
        if (msg.sender != self.resealCommittee) {
            revert CallerIsNotResealCommittee(msg.sender);
        }
    }
}
