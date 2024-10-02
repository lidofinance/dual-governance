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
/// @dev The mechanism design allows for a deadlock where the system is stuck in the RageQuit
/// state while protocol withdrawals are paused or dysfunctional and require a DAO vote to resume,
/// and includes a third-party arbiter Tiebreaker committee for resolving it. Tiebreaker gains
/// the power to execute pending proposals, bypassing the DG dynamic timelock, and unpause any
/// protocol contract under the specific conditions of the deadlock.
library Tiebreaker {
    using EnumerableSet for EnumerableSet.AddressSet;

    error TiebreakNotAllowed();
    error InvalidSealable(address sealable);
    error InvalidTiebreakerCommittee(address account);
    error InvalidTiebreakerActivationTimeout(Duration timeout);
    error CallerIsNotTiebreakerCommittee(address caller);
    error SealableWithdrawalBlockersLimitReached();
    error SealableWithdrawalBlockerNotFound(address sealable);
    error SealableWithdrawalBlockerAlreadyAdded(address sealable);

    event SealableWithdrawalBlockerAdded(address sealable);
    event SealableWithdrawalBlockerRemoved(address sealable);
    event TiebreakerCommitteeSet(address newTiebreakerCommittee);
    event TiebreakerActivationTimeoutSet(Duration newTiebreakerActivationTimeout);

    /// @dev Context struct to store tiebreaker-related data.
    /// @param tiebreakerCommittee Address of the tiebreaker committee.
    /// @param tiebreakerActivationTimeout Duration for tiebreaker activation timeout.
    /// @param sealableWithdrawalBlockers Set of addresses that are sealable withdrawal blockers.
    struct Context {
        /// @dev slot0 [0..159]
        address tiebreakerCommittee;
        /// @dev slot0 [160..191]
        Duration tiebreakerActivationTimeout;
        /// @dev slot1 [0..255]
        EnumerableSet.AddressSet sealableWithdrawalBlockers;
    }

    // ---
    // Setup functionality
    // ---

    /// @notice Adds a sealable withdrawal blocker.
    /// @dev Reverts if the maximum number of sealable withdrawal blockers is reached or if the sealable is invalid.
    /// @param self The context storage.
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
        (bool isCallSucceed, /* isPaused */ ) = SealableCalls.callIsPaused(sealableWithdrawalBlocker);
        if (!isCallSucceed) {
            revert InvalidSealable(sealableWithdrawalBlocker);
        }

        if (!self.sealableWithdrawalBlockers.add(sealableWithdrawalBlocker)) {
            revert SealableWithdrawalBlockerAlreadyAdded(sealableWithdrawalBlocker);
        }
        emit SealableWithdrawalBlockerAdded(sealableWithdrawalBlocker);
    }

    /// @notice Removes a sealable withdrawal blocker.
    /// @param self The context storage.
    /// @param sealableWithdrawalBlocker The address of the sealable withdrawal blocker to remove.
    function removeSealableWithdrawalBlocker(Context storage self, address sealableWithdrawalBlocker) internal {
        if (!self.sealableWithdrawalBlockers.remove(sealableWithdrawalBlocker)) {
            revert SealableWithdrawalBlockerNotFound(sealableWithdrawalBlocker);
        }
        emit SealableWithdrawalBlockerRemoved(sealableWithdrawalBlocker);
    }

    /// @notice Sets the tiebreaker committee.
    /// @dev Reverts if the new tiebreaker committee address is invalid.
    /// @param self The context storage.
    /// @param newTiebreakerCommittee The address of the new tiebreaker committee.
    function setTiebreakerCommittee(Context storage self, address newTiebreakerCommittee) internal {
        if (newTiebreakerCommittee == address(0) || newTiebreakerCommittee == self.tiebreakerCommittee) {
            revert InvalidTiebreakerCommittee(newTiebreakerCommittee);
        }
        self.tiebreakerCommittee = newTiebreakerCommittee;
        emit TiebreakerCommitteeSet(newTiebreakerCommittee);
    }

    /// @notice Sets the tiebreaker activation timeout.
    /// @dev Reverts if the new timeout is outside the allowed range.
    /// @param self The context storage.
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
    /// @dev Reverts if the caller is not the tiebreaker committee.
    /// @param self The context storage.
    function checkCallerIsTiebreakerCommittee(Context storage self) internal view {
        if (msg.sender != self.tiebreakerCommittee) {
            revert CallerIsNotTiebreakerCommittee(msg.sender);
        }
    }

    /// @notice Checks if a tie exists.
    /// @dev Reverts if no tie exists.
    /// @param self The context storage.
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
    /// @param self The context storage.
    /// @param state The current state of dual governance.
    /// @param normalOrVetoCooldownExitedAt The timestamp when normal or veto cooldown exited.
    /// @return True if a tie exists, false otherwise.
    function isTie(
        Context storage self,
        DualGovernanceState state,
        Timestamp normalOrVetoCooldownExitedAt
    ) internal view returns (bool) {
        if (state == DualGovernanceState.Normal || state == DualGovernanceState.VetoCooldown) return false;

        if (Timestamps.now() >= self.tiebreakerActivationTimeout.addTo(normalOrVetoCooldownExitedAt)) {
            return true;
        }

        return state == DualGovernanceState.RageQuit && isSomeSealableWithdrawalBlockerPausedOrFaulty(self);
    }

    /// @notice Checks if any sealable withdrawal blocker is paused or functioning improperly.
    /// @param self The context containing the sealable withdrawal blockers.
    /// @return True if any sealable withdrawal blocker is paused or functioning incorrectly, false otherwise.
    function isSomeSealableWithdrawalBlockerPausedOrFaulty(Context storage self) internal view returns (bool) {
        uint256 sealableWithdrawalBlockersCount = self.sealableWithdrawalBlockers.length();
        for (uint256 i = 0; i < sealableWithdrawalBlockersCount; ++i) {
            (bool isCallSucceed, bool isPaused) = SealableCalls.callIsPaused(self.sealableWithdrawalBlockers.at(i));
            if (isPaused || !isCallSucceed) return true;
        }
        return false;
    }

    /// @dev Retrieves the tiebreaker context from the storage.
    /// @param self The storage context.
    /// @param stateDetails A struct containing detailed information about the current state of the Dual Governance system
    /// @return context The tiebreaker context containing the tiebreaker committee, tiebreaker activation timeout, and sealable withdrawal blockers.
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
