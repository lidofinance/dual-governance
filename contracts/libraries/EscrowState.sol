// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

/// @notice The state of Escrow representing the current set of actions allowed to be called
///     on the Escrow instance.
/// @param NotInitialized The default (uninitialized) state of the Escrow contract. Only the master
///     copy of the Escrow contract is expected to be in this state.
/// @param SignallingEscrow In this state, the Escrow contract functions as an on-chain oracle for measuring stakers' disagreement
///     with DAO decisions. Users are allowed to lock and unlock funds in the Escrow contract in this state.
/// @param RageQuitEscrow The final state of the Escrow contract. In this state, the Escrow instance acts as an accumulator
///     for withdrawn funds locked during the SignallingEscrow state.
enum State {
    NotInitialized,
    SignallingEscrow,
    RageQuitEscrow
}

/// @title Escrow State Library
/// @notice Represents the logic to manipulate the state of the Escrow.
library EscrowState {
    // ---
    // Errors
    // ---

    error ClaimingIsFinished();
    error UnexpectedEscrowState(State state);
    error EthWithdrawalsDelayNotPassed();
    error RageQuitExtensionPeriodNotStarted();
    error InvalidMinAssetsLockDuration(Duration newMinAssetsLockDuration);
    error RageQuitExtensionPeriodAlreadyStarted();

    // ---
    // Events
    // ---

    event EscrowStateChanged(State indexed from, State indexed to);
    event RageQuitExtensionPeriodStarted(Timestamp startedAt);
    event MinAssetsLockDurationSet(Duration newAssetsLockDuration);
    event RageQuitStarted(Duration rageQuitExtensionPeriodDuration, Duration rageQuitEthWithdrawalsDelay);

    // ---
    // Data Types
    // ---

    /// @notice Stores the context of the state of the Escrow instance.
    /// @param state The current state of the Escrow instance.
    /// @param minAssetsLockDuration The minimum time required to pass before tokens can be unlocked from the Escrow
    ///     contract instance.
    /// @param rageQuitExtensionPeriodDuration The period of time that starts after all withdrawal batches are formed,
    ///     which delays the exit from the RageQuit state of the DualGovernance. The main purpose of the rage quit
    ///     extension period is to provide enough time for users who locked their unstETH to claim it.
    /// @param rageQuitExtensionPeriodStartedAt The timestamp when the rage quit extension period started.
    /// @param rageQuitEthWithdrawalsDelay The waiting period after the Rage Quit process is finalized before vetoers
    ///     can withdraw ETH from the Escrow.
    struct Context {
        /// @dev slot0: [0..7]
        State state;
        /// @dev slot0: [8..39]
        Duration minAssetsLockDuration;
        /// @dev slot0: [40..71]
        Duration rageQuitExtensionPeriodDuration;
        /// @dev slot0: [72..111]
        Timestamp rageQuitExtensionPeriodStartedAt;
        /// @dev slot0: [112..143]
        Duration rageQuitEthWithdrawalsDelay;
    }

    // ---
    // Main Functionality
    // ---

    /// @notice Initializes the Escrow state to SignallingEscrow.
    /// @param self The context of the Escrow State library.
    /// @param minAssetsLockDuration The initial minimum assets lock duration.
    /// @param maxMinAssetsLockDuration Sanity check upper bound for min assets lock duration.
    function initialize(
        Context storage self,
        Duration minAssetsLockDuration,
        Duration maxMinAssetsLockDuration
    ) internal {
        _checkState(self, State.NotInitialized);
        _setState(self, State.SignallingEscrow);
        setMinAssetsLockDuration(self, minAssetsLockDuration, maxMinAssetsLockDuration);
    }

    /// @notice Starts the rage quit process.
    /// @param self The context of the Escrow State library.
    /// @param rageQuitExtensionPeriodDuration The duration of the period for the rage quit extension.
    /// @param rageQuitEthWithdrawalsDelay The delay for rage quit withdrawals.
    function startRageQuit(
        Context storage self,
        Duration rageQuitExtensionPeriodDuration,
        Duration rageQuitEthWithdrawalsDelay
    ) internal {
        _checkState(self, State.SignallingEscrow);
        _setState(self, State.RageQuitEscrow);
        self.rageQuitExtensionPeriodDuration = rageQuitExtensionPeriodDuration;
        self.rageQuitEthWithdrawalsDelay = rageQuitEthWithdrawalsDelay;
        emit RageQuitStarted(rageQuitExtensionPeriodDuration, rageQuitEthWithdrawalsDelay);
    }

    /// @notice Starts the rage quit extension period.
    /// @param self The context of the Escrow State library.
    function startRageQuitExtensionPeriod(Context storage self) internal {
        if (self.rageQuitExtensionPeriodStartedAt.isNotZero()) {
            revert RageQuitExtensionPeriodAlreadyStarted();
        }
        self.rageQuitExtensionPeriodStartedAt = Timestamps.now();
        emit RageQuitExtensionPeriodStarted(self.rageQuitExtensionPeriodStartedAt);
    }

    /// @notice Sets the minimum assets lock duration.
    /// @param self The context of the Escrow State library.
    /// @param newMinAssetsLockDuration The new minimum assets lock duration.
    /// @param maxMinAssetsLockDuration Sanity check for max assets lock duration.
    function setMinAssetsLockDuration(
        Context storage self,
        Duration newMinAssetsLockDuration,
        Duration maxMinAssetsLockDuration
    ) internal {
        if (
            self.minAssetsLockDuration == newMinAssetsLockDuration
                || newMinAssetsLockDuration > maxMinAssetsLockDuration
        ) {
            revert InvalidMinAssetsLockDuration(newMinAssetsLockDuration);
        }
        self.minAssetsLockDuration = newMinAssetsLockDuration;
        emit MinAssetsLockDurationSet(newMinAssetsLockDuration);
    }

    // ---
    // Checks
    // ---

    /// @notice Checks if the Escrow is in the SignallingEscrow state.
    /// @param self The context of the Escrow State library.
    function checkSignallingEscrow(Context storage self) internal view {
        _checkState(self, State.SignallingEscrow);
    }

    /// @notice Checks if the Escrow is in the RageQuitEscrow state.
    /// @param self The context of the Escrow State library.
    function checkRageQuitEscrow(Context storage self) internal view {
        _checkState(self, State.RageQuitEscrow);
    }

    /// @notice Checks if batch claiming is in progress.
    /// @param self The context of the Escrow State library.
    function checkBatchesClaimingInProgress(Context storage self) internal view {
        if (!self.rageQuitExtensionPeriodStartedAt.isZero()) {
            revert ClaimingIsFinished();
        }
    }

    /// @notice Checks if the withdrawals delay has passed.
    /// @param self The context of the Escrow State library.
    function checkEthWithdrawalsDelayPassed(Context storage self) internal view {
        Timestamp rageQuitExtensionPeriodStartedAt = self.rageQuitExtensionPeriodStartedAt;

        if (rageQuitExtensionPeriodStartedAt.isZero()) {
            revert RageQuitExtensionPeriodNotStarted();
        }
        Duration ethWithdrawalsDelay = self.rageQuitExtensionPeriodDuration + self.rageQuitEthWithdrawalsDelay;
        if (Timestamps.now() <= ethWithdrawalsDelay.addTo(rageQuitExtensionPeriodStartedAt)) {
            revert EthWithdrawalsDelayNotPassed();
        }
    }

    // ---
    // Getters
    // ---

    /// @notice Returns whether the rage quit extension period has started.
    /// @param self The context of the Escrow State library.
    /// @return bool `true` if the rage quit extension period has started, `false` otherwise.
    function isRageQuitExtensionPeriodStarted(Context storage self) internal view returns (bool) {
        return self.rageQuitExtensionPeriodStartedAt.isNotZero();
    }

    /// @notice Returns whether the rage quit extension period has passed.
    /// @param self The context of the Escrow State library.
    /// @return bool `true` if the rage quit extension period has passed, `false` otherwise.
    function isRageQuitExtensionPeriodPassed(Context storage self) internal view returns (bool) {
        Timestamp rageQuitExtensionPeriodStartedAt = self.rageQuitExtensionPeriodStartedAt;
        return rageQuitExtensionPeriodStartedAt.isNotZero()
            && Timestamps.now() > self.rageQuitExtensionPeriodDuration.addTo(rageQuitExtensionPeriodStartedAt);
    }

    /// @notice Returns whether the Escrow is in the RageQuitEscrow state.
    /// @param self The context of the Escrow State library.
    /// @return bool `true` if the Escrow is in the RageQuitEscrow state, `false` otherwise.
    function isRageQuitEscrow(Context storage self) internal view returns (bool) {
        return self.state == State.RageQuitEscrow;
    }

    // ---
    // Private Methods
    // ---

    /// @notice Checks if the Escrow is in the expected state.
    /// @param self The context of the Escrow State library.
    /// @param state The expected state.
    function _checkState(Context storage self, State state) private view {
        if (self.state != state) {
            revert UnexpectedEscrowState(self.state);
        }
    }

    /// @notice Sets the state of the Escrow.
    /// @param self The context of the Escrow State library.
    /// @param newState The new state.
    function _setState(Context storage self, State newState) private {
        State prevState = self.state;
        self.state = newState;
        emit EscrowStateChanged(prevState, newState);
    }
}
