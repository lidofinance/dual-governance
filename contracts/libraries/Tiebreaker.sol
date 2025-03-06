// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Duration.sol";

import {ITiebreaker} from "../interfaces/ITiebreaker.sol";
import {IDualGovernance} from "../interfaces/IDualGovernance.sol";

import {SealableCalls} from "../libraries/SealableCalls.sol";

import {State as DualGovernanceState} from "./DualGovernanceStateMachine.sol";

/// @title Tiebreaker Library
/// @notice Provides mechanisms for resolving deadlocks in Dual Governance, especially in cases where protocol
///     components essential for finalizing withdrawal requests are paused or dysfunctional, while Dual Governance
///     remains stuck in the Rage Quit state, preventing the DAO from taking necessary actions to resolve the issue.
///     This library includes functions for managing a standalone tiebreaker committee, which can resolve such deadlocks
///     by executing pending proposals or unpausing protocol contracts, but only under specific deadlock conditions.
library Tiebreaker {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ---
    // Errors
    // ---

    error TiebreakNotAllowed();
    error InvalidSealable(address sealable);
    error InvalidTiebreakerCommittee(address account);
    error InvalidTiebreakerActivationTimeout(Duration timeout);
    error CallerIsNotTiebreakerCommittee(address caller);
    error SealableWithdrawalBlockersLimitReached();
    error SealableWithdrawalBlockerNotFound(address sealable);
    error SealableWithdrawalBlockerAlreadyAdded(address sealable);

    // ---
    // Events
    // ---

    event SealableWithdrawalBlockerAdded(address sealable);
    event SealableWithdrawalBlockerRemoved(address sealable);
    event TiebreakerCommitteeSet(address newTiebreakerCommittee);
    event TiebreakerActivationTimeoutSet(Duration newTiebreakerActivationTimeout);

    // ---
    // Data Types
    // ---

    /// @notice The context of the Tiebreaker library.
    /// @param tiebreakerCommittee The address of the tiebreaker committee, authorized to resolve deadlocks.
    /// @param tiebreakerActivationTimeout The duration Dual Governance must remain outside the Normal or VetoCooldown
    ///     states before the tiebreaker committee is allowed to act, provided that all registered sealable withdrawal
    ///     blockers are unpaused.
    /// @param sealableWithdrawalBlockers A set of addresses representing potential withdrawal blockers,
    ///     each implementing the `ISealable` interface.
    struct Context {
        /// @dev slot0 [0..159]
        address tiebreakerCommittee;
        /// @dev slot0 [160..191]
        Duration tiebreakerActivationTimeout;
        /// @dev slot1..slotN - slots for the `AddressSet` library state.
        EnumerableSet.AddressSet sealableWithdrawalBlockers;
    }

    // ---
    // Setup Functionality
    // ---

    /// @notice Adds a sealable withdrawal blocker.
    /// @param self The context of the Tiebreaker library.
    /// @param sealableWithdrawalBlocker The address of the sealable withdrawal blocker to add.
    /// @param maxSealableWithdrawalBlockersCount The maximum number of sealable withdrawal blockers allowed.
    function addSealableWithdrawalBlocker(
        Context storage self,
        address sealableWithdrawalBlocker,
        uint256 maxSealableWithdrawalBlockersCount
    ) internal {
        uint256 sealableWithdrawalBlockersCount = self.sealableWithdrawalBlockers.length();
        if (sealableWithdrawalBlockersCount == maxSealableWithdrawalBlockersCount) {
            revert SealableWithdrawalBlockersLimitReached();
        }

        (bool isCallSucceed, uint256 resumeSinceTimestamp) =
            SealableCalls.callGetResumeSinceTimestamp(sealableWithdrawalBlocker);

        /// @dev Prevents addition of paused or misbehaving sealables.
        ///     According to the current PausableUntil implementation, a contract is paused if `block.timestamp < resumeSinceTimestamp`.
        ///     Reference: https://github.com/lidofinance/core/blob/60bc9b77b036eec22b2ab8a3a1d49c6b6614c600/contracts/0.8.9/utils/PausableUntil.sol#L52
        if (!isCallSucceed || block.timestamp < resumeSinceTimestamp) {
            revert InvalidSealable(sealableWithdrawalBlocker);
        }

        if (!self.sealableWithdrawalBlockers.add(sealableWithdrawalBlocker)) {
            revert SealableWithdrawalBlockerAlreadyAdded(sealableWithdrawalBlocker);
        }
        emit SealableWithdrawalBlockerAdded(sealableWithdrawalBlocker);
    }

    /// @notice Removes a sealable withdrawal blocker.
    /// @param self The context of the Tiebreaker library.
    /// @param sealableWithdrawalBlocker The address of the sealable withdrawal blocker to remove.
    function removeSealableWithdrawalBlocker(Context storage self, address sealableWithdrawalBlocker) internal {
        if (!self.sealableWithdrawalBlockers.remove(sealableWithdrawalBlocker)) {
            revert SealableWithdrawalBlockerNotFound(sealableWithdrawalBlocker);
        }
        emit SealableWithdrawalBlockerRemoved(sealableWithdrawalBlocker);
    }

    /// @notice Sets the tiebreaker committee.
    /// @param self The context of the Tiebreaker library.
    /// @param newTiebreakerCommittee The address of the new tiebreaker committee.
    function setTiebreakerCommittee(Context storage self, address newTiebreakerCommittee) internal {
        if (newTiebreakerCommittee == address(0) || newTiebreakerCommittee == self.tiebreakerCommittee) {
            revert InvalidTiebreakerCommittee(newTiebreakerCommittee);
        }
        self.tiebreakerCommittee = newTiebreakerCommittee;
        emit TiebreakerCommitteeSet(newTiebreakerCommittee);
    }

    /// @notice Sets the tiebreaker activation timeout.
    /// @param self The context of the Tiebreaker library.
    /// @param minTiebreakerActivationTimeout The minimum allowed tiebreaker activation timeout.
    /// @param newTiebreakerActivationTimeout The new tiebreaker activation timeout.
    /// @param maxTiebreakerActivationTimeout The maximum allowed tiebreaker activation timeout.
    function setTiebreakerActivationTimeout(
        Context storage self,
        Duration minTiebreakerActivationTimeout,
        Duration newTiebreakerActivationTimeout,
        Duration maxTiebreakerActivationTimeout
    ) internal {
        if (
            newTiebreakerActivationTimeout < minTiebreakerActivationTimeout
                || newTiebreakerActivationTimeout > maxTiebreakerActivationTimeout
                || newTiebreakerActivationTimeout == self.tiebreakerActivationTimeout
        ) {
            revert InvalidTiebreakerActivationTimeout(newTiebreakerActivationTimeout);
        }
        self.tiebreakerActivationTimeout = newTiebreakerActivationTimeout;
        emit TiebreakerActivationTimeoutSet(newTiebreakerActivationTimeout);
    }

    // ---
    // Checks
    // ---

    /// @notice Checks if the caller is the tiebreaker committee.
    /// @param self The context of the Tiebreaker library.
    function checkCallerIsTiebreakerCommittee(Context storage self) internal view {
        if (msg.sender != self.tiebreakerCommittee) {
            revert CallerIsNotTiebreakerCommittee(msg.sender);
        }
    }

    /// @notice Checks if a tie exists.
    /// @param self The context of the Tiebreaker library.
    /// @param state The current state of dual governance.
    /// @param normalOrVetoCooldownExitedAt The timestamp when normal or veto cooldown exited.
    function checkTie(
        Context storage self,
        DualGovernanceState state,
        Timestamp normalOrVetoCooldownExitedAt
    ) internal view {
        if (!isTie(self, state, normalOrVetoCooldownExitedAt)) {
            revert TiebreakNotAllowed();
        }
    }

    // ---
    // Getters
    // ---

    /// @notice Determines if a tie exists.
    /// @param self The context of the Tiebreaker library.
    /// @param state The current state of dual governance.
    /// @param normalOrVetoCooldownExitedAt The timestamp when normal or veto cooldown exited.
    /// @return bool `true` if a tie exists, false otherwise.
    function isTie(
        Context storage self,
        DualGovernanceState state,
        Timestamp normalOrVetoCooldownExitedAt
    ) internal view returns (bool) {
        if (state == DualGovernanceState.Normal || state == DualGovernanceState.VetoCooldown) return false;

        if (Timestamps.now() >= self.tiebreakerActivationTimeout.addTo(normalOrVetoCooldownExitedAt)) {
            return true;
        }

        return state == DualGovernanceState.RageQuit && isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty(self);
    }

    /// @notice Determines whether any sealable withdrawal blocker has been paused for a duration exceeding
    ///     `tiebreakerActivationTimeout`, or if it is functioning improperly.
    /// @param self The context containing the sealable withdrawal blockers.
    /// @return True if any sealable withdrawal blocker is paused for a duration exceeding `tiebreakerActivationTimeout`
    ///     or is functioning incorrectly, false otherwise.
    function isSomeSealableWithdrawalBlockerPausedForLongTermOrFaulty(Context storage self)
        internal
        view
        returns (bool)
    {
        uint256 sealableWithdrawalBlockersCount = self.sealableWithdrawalBlockers.length();

        /// @dev If a sealable has been paused for less than or equal to the `tiebreakerActivationTimeout` duration,
        ///     counting from the current `block.timestamp`, it is not considered paused for the "long term", and the
        ///     tiebreaker committee is not permitted to unpause it.
        uint256 tiebreakAllowedAfterTimestampInSeconds =
            self.tiebreakerActivationTimeout.addTo(Timestamps.now()).toSeconds();

        for (uint256 i = 0; i < sealableWithdrawalBlockersCount; ++i) {
            (bool isCallSucceed, uint256 sealableResumeSinceTimestampInSeconds) =
                SealableCalls.callGetResumeSinceTimestamp(self.sealableWithdrawalBlockers.at(i));

            if (!isCallSucceed || sealableResumeSinceTimestampInSeconds > tiebreakAllowedAfterTimestampInSeconds) {
                return true;
            }
        }
        return false;
    }

    /// @dev Retrieves the tiebreaker context from the storage.
    /// @param self The context of the Tiebreaker library.
    /// @param stateDetails A struct containing detailed information about the current state of the Dual Governance system
    /// @return context The tiebreaker context, including whether a tie exists, the tiebreaker committee, tiebreaker activation timeout,
    ///     and sealable withdrawal blockers.
    function getTiebreakerDetails(
        Context storage self,
        IDualGovernance.StateDetails memory stateDetails
    ) internal view returns (ITiebreaker.TiebreakerDetails memory context) {
        context.tiebreakerCommittee = self.tiebreakerCommittee;
        context.tiebreakerActivationTimeout = self.tiebreakerActivationTimeout;

        DualGovernanceState persistedState = stateDetails.persistedState;
        DualGovernanceState effectiveState = stateDetails.effectiveState;
        Timestamp normalOrVetoCooldownExitedAt = stateDetails.normalOrVetoCooldownExitedAt;

        if (effectiveState != persistedState) {
            if (persistedState == DualGovernanceState.Normal || persistedState == DualGovernanceState.VetoCooldown) {
                /// @dev When a pending state change is expected from the `Normal` or `VetoCooldown` state,
                ///     the `normalOrVetoCooldownExitedAt` timestamp should be set to the current timestamp to reflect
                ///     the behavior of the `DualGovernanceStateMachine.activateNextState()` method.
                normalOrVetoCooldownExitedAt = Timestamps.now();
            }
        }

        context.isTie = isTie(self, effectiveState, normalOrVetoCooldownExitedAt);

        uint256 sealableWithdrawalBlockersCount = self.sealableWithdrawalBlockers.length();
        context.sealableWithdrawalBlockers = new address[](sealableWithdrawalBlockersCount);

        for (uint256 i = 0; i < sealableWithdrawalBlockersCount; ++i) {
            context.sealableWithdrawalBlockers[i] = self.sealableWithdrawalBlockers.at(i);
        }
    }
}
