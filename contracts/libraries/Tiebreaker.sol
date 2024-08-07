// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Duration.sol";

import {ISealable} from "../interfaces/ISealable.sol";

import {SealableCalls} from "./SealableCalls.sol";
import {State as DualGovernanceState} from "./DualGovernanceStateMachine.sol";

library Tiebreaker {
    using SealableCalls for ISealable;
    using EnumerableSet for EnumerableSet.AddressSet;

    error TiebreakDisallowed();
    error InvalidSealable(address value);
    error InvalidTiebreakerCommittee(address value);
    error InvalidTiebreakerActivationTimeout(Duration value);
    error SealableWithdrawalBlockersLimitReached();

    event SealableWithdrawalBlockerAdded(address sealable);
    event SealableWithdrawalBlockerRemoved(address sealable);
    event TiebreakerCommitteeSet(address newTiebreakerCommittee);
    event TiebreakerActivationTimeoutSet(Duration newTiebreakerActivationTimeout);

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

    function removeSealableWithdrawalBlocker(Context storage self, address sealableWithdrawalBlocker) internal {
        bool isSuccessfullyRemoved = self.sealableWithdrawalBlockers.remove(sealableWithdrawalBlocker);
        if (isSuccessfullyRemoved) {
            emit SealableWithdrawalBlockerRemoved(sealableWithdrawalBlocker);
        }
    }

    function setTiebreakerCommittee(Context storage self, address newTiebreakerCommittee) internal {
        if (newTiebreakerCommittee == address(0)) {
            revert InvalidTiebreakerCommittee(newTiebreakerCommittee);
        }
        if (self.tiebreakerCommittee == newTiebreakerCommittee) {
            return;
        }
        self.tiebreakerCommittee = newTiebreakerCommittee;
        emit TiebreakerCommitteeSet(newTiebreakerCommittee);
    }

    function setTiebreakerActivationTimeout(
        Context storage self,
        Duration minTiebreakerActivationTimeout,
        Duration newTiebreakerActivationTimeout,
        Duration maxTiebreakerActivationTimeout
    ) internal {
        if (
            newTiebreakerActivationTimeout < minTiebreakerActivationTimeout
                || newTiebreakerActivationTimeout > maxTiebreakerActivationTimeout
        ) {
            revert InvalidTiebreakerActivationTimeout(newTiebreakerActivationTimeout);
        }

        if (self.tiebreakerActivationTimeout == newTiebreakerActivationTimeout) {
            return;
        }
        self.tiebreakerActivationTimeout = newTiebreakerActivationTimeout;
        emit TiebreakerActivationTimeoutSet(newTiebreakerActivationTimeout);
    }

    // ---
    // Checks
    // ---

    function checkSenderIsTiebreakerCommittee(Context storage self) internal view {
        if (msg.sender != self.tiebreakerCommittee) {
            revert InvalidTiebreakerCommittee(msg.sender);
        }
    }

    function checkTie(
        Context storage self,
        DualGovernanceState state,
        Timestamp normalOrVetoCooldownExitedAt
    ) internal view {
        if (!isTie(self, state, normalOrVetoCooldownExitedAt)) {
            revert TiebreakDisallowed();
        }
    }

    // ---
    // Getters
    // ---

    function isTie(
        Context storage self,
        DualGovernanceState state,
        Timestamp normalOrVetoCooldownExitedAt
    ) internal view returns (bool) {
        if (state == DualGovernanceState.Normal || state == DualGovernanceState.VetoCooldown) return false;

        // when the governance is locked for long period of time
        if (Timestamps.now() >= self.tiebreakerActivationTimeout.addTo(normalOrVetoCooldownExitedAt)) {
            return true;
        }

        return state == DualGovernanceState.RageQuit && isSomeSealableWithdrawalBlockerPaused(self);
    }

    function isSomeSealableWithdrawalBlockerPaused(Context storage self) internal view returns (bool) {
        uint256 sealableWithdrawalBlockersCount = self.sealableWithdrawalBlockers.length();
        for (uint256 i = 0; i < sealableWithdrawalBlockersCount; ++i) {
            (bool isCallSucceed, /* lowLevelError */, bool isPaused) =
                ISealable(self.sealableWithdrawalBlockers.at(i)).callIsPaused();

            // in normal condition this call must never fail, so if some sealable withdrawal blocker
            // started behave unexpectedly tiebreaker action may be the last hope for the protocol saving
            if (isPaused || !isCallSucceed) return true;
        }
        return false;
    }

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
