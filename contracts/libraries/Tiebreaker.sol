// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Duration.sol";
import {ISealable} from "../interfaces/ISealable.sol";
import {SealableCalls} from "./SealableCalls.sol";
import {State as DualGovernanceState} from "./DualGovernanceStateMachine.sol";

/// @title Tiebreaker Library
/// @dev The mechanism design allows for a deadlock where the system is stuck in the RageQuit
/// state while protocol withdrawals are paused or dysfunctional and require a DAO vote to resume,
/// and includes a third-party arbiter Tiebreaker committee for resolving it. Tiebreaker gains
/// the power to execute pending proposals, bypassing the DG dynamic timelock, and unpause any
/// protocol contract under the specific conditions of the deadlock.
library Tiebreaker {
    using SealableCalls for ISealable;
    using EnumerableSet for EnumerableSet.AddressSet;

    error TiebreakNotAllowed();
    error InvalidSealable(address sealable);
    error InvalidTiebreakerCommittee(address account);
    error InvalidTiebreakerActivationTimeout(Duration timeout);
    error CallerIsNotTiebreakerCommittee(address caller);
    error SealableWithdrawalBlockersLimitReached();

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
        (bool isCallSucceed, /* lowLevelError */, /* isPaused */ ) = ISealable(sealableWithdrawalBlocker).callIsPaused();
        if (!isCallSucceed) {
            revert InvalidSealable(sealableWithdrawalBlocker);
        }

        bool isSuccessfullyAdded = self.sealableWithdrawalBlockers.add(sealableWithdrawalBlocker);
        if (isSuccessfullyAdded) {
            emit SealableWithdrawalBlockerAdded(sealableWithdrawalBlocker);
        }
    }

    /// @notice Removes a sealable withdrawal blocker.
    /// @param self The context storage.
    /// @param sealableWithdrawalBlocker The address of the sealable withdrawal blocker to remove.
    function removeSealableWithdrawalBlocker(Context storage self, address sealableWithdrawalBlocker) internal {
        bool isSuccessfullyRemoved = self.sealableWithdrawalBlockers.remove(sealableWithdrawalBlocker);
        if (isSuccessfullyRemoved) {
            emit SealableWithdrawalBlockerRemoved(sealableWithdrawalBlocker);
        }
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

        return state == DualGovernanceState.RageQuit && isSomeSealableWithdrawalBlockerPaused(self);
    }

    /// @notice Checks if any sealable withdrawal blocker is paused.
    /// @param self The context storage.
    /// @return True if any sealable withdrawal blocker is paused, false otherwise.
    function isSomeSealableWithdrawalBlockerPaused(Context storage self) internal view returns (bool) {
        uint256 sealableWithdrawalBlockersCount = self.sealableWithdrawalBlockers.length();
        for (uint256 i = 0; i < sealableWithdrawalBlockersCount; ++i) {
            (bool isCallSucceed, /* lowLevelError */, bool isPaused) =
                ISealable(self.sealableWithdrawalBlockers.at(i)).callIsPaused();

            if (isPaused || !isCallSucceed) return true;
        }
        return false;
    }

    /// @notice Gets the tiebreaker information.
    /// @param self The context storage.
    /// @return tiebreakerCommittee The address of the tiebreaker committee.
    /// @return tiebreakerActivationTimeout The duration of the tiebreaker activation timeout.
    /// @return sealableWithdrawalBlockers The addresses of the sealable withdrawal blockers.
    function getTiebreakerInfo(Context storage self)
        internal
        view
        returns (
            address tiebreakerCommittee,
            Duration tiebreakerActivationTimeout,
            address[] memory sealableWithdrawalBlockers
        )
    {
        tiebreakerCommittee = self.tiebreakerCommittee;
        tiebreakerActivationTimeout = self.tiebreakerActivationTimeout;

        uint256 sealableWithdrawalBlockersCount = self.sealableWithdrawalBlockers.length();
        sealableWithdrawalBlockers = new address[](sealableWithdrawalBlockersCount);

        for (uint256 i = 0; i < sealableWithdrawalBlockersCount; ++i) {
            sealableWithdrawalBlockers[i] = self.sealableWithdrawalBlockers.at(i);
        }
    }
}
