// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

enum State {
    NotInitialized,
    SignallingEscrow,
    RageQuitEscrow
}

library EscrowState {
    error ClaimingIsFinished();
    error InvalidState(State value);
    error InvalidDualGovernance(address value);
    error RageQuitExtraTimelockNotStarted();
    error WithdrawalsTimelockNotPassed();

    event RageQuitTimelockStarted();
    event EscrowStateChanged(State from, State to);
    event RageQuitStarted(Duration rageQuitExtensionDelay, Duration rageQuitWithdrawalsTimelock);
    event MinAssetsLockDurationSet(Duration newAssetsLockDuration);

    struct Context {
        /// @dev slot0: [0..7]
        State state;
        /// @dev slot0: [8..39]
        Duration minAssetsLockDuration;
        /// @dev slot0: [40..71]
        Duration rageQuitExtensionDelay;
        /// @dev slot1: [72..103]
        Duration rageQuitWithdrawalsTimelock;
        /// @dev slot1: [104..144]
        Timestamp rageQuitExtensionDelayStartedAt;
    }

    function initialize(Context storage self, Duration minAssetsLockDuration) internal {
        _checkState(self, State.NotInitialized);
        _setState(self, State.SignallingEscrow);
        _setMinAssetsLockDuration(self, minAssetsLockDuration);
    }

    function startRageQuit(
        Context storage self,
        Duration rageQuitExtensionDelay,
        Duration rageQuitWithdrawalsTimelock
    ) internal {
        _checkState(self, State.SignallingEscrow);
        _setState(self, State.RageQuitEscrow);
        self.rageQuitExtensionDelay = rageQuitExtensionDelay;
        self.rageQuitWithdrawalsTimelock = rageQuitWithdrawalsTimelock;
        emit RageQuitStarted(rageQuitExtensionDelay, rageQuitWithdrawalsTimelock);
    }

    function startRageQuitExtensionDelay(Context storage self) internal {
        self.rageQuitExtensionDelayStartedAt = Timestamps.now();
        emit RageQuitTimelockStarted();
    }

    function setMinAssetsLockDuration(Context storage self, Duration newMinAssetsLockDuration) internal {
        if (self.minAssetsLockDuration == newMinAssetsLockDuration) {
            return;
        }
        _setMinAssetsLockDuration(self, newMinAssetsLockDuration);
    }

    // ---
    // Checks
    // ---

    function checkSignallingEscrow(Context storage self) internal view {
        _checkState(self, State.SignallingEscrow);
    }

    function checkRageQuitEscrow(Context storage self) internal view {
        _checkState(self, State.RageQuitEscrow);
    }

    function checkBatchesClaimInProgress(Context storage self) internal view {
        if (!self.rageQuitExtensionDelayStartedAt.isZero()) {
            revert ClaimingIsFinished();
        }
    }

    function checkWithdrawalsTimelockPassed(Context storage self) internal view {
        if (self.rageQuitExtensionDelayStartedAt.isZero()) {
            revert RageQuitExtraTimelockNotStarted();
        }
        Duration withdrawalsTimelock = self.rageQuitExtensionDelay + self.rageQuitWithdrawalsTimelock;
        if (Timestamps.now() <= withdrawalsTimelock.addTo(self.rageQuitExtensionDelayStartedAt)) {
            revert WithdrawalsTimelockNotPassed();
        }
    }

    // ---
    // Getters
    // ---
    function isWithdrawalsClaimed(Context storage self) internal view returns (bool) {
        return self.rageQuitExtensionDelayStartedAt.isNotZero();
    }

    function isRageQuitExtensionDelayPassed(Context storage self) internal view returns (bool) {
        Timestamp rageQuitExtensionDelayStartedAt = self.rageQuitExtensionDelayStartedAt;
        return rageQuitExtensionDelayStartedAt.isNotZero()
            && Timestamps.now() > self.rageQuitExtensionDelay.addTo(rageQuitExtensionDelayStartedAt);
    }

    function isRageQuitEscrow(Context storage self) internal view returns (bool) {
        return self.state == State.RageQuitEscrow;
    }

    // ---
    // Private Methods
    // ---

    function _checkState(Context storage self, State state) private view {
        if (self.state != state) {
            revert InvalidState(state);
        }
    }

    function _setState(Context storage self, State newState) private {
        State prevState = self.state;
        self.state = newState;
        emit EscrowStateChanged(prevState, newState);
    }

    function _setMinAssetsLockDuration(Context storage self, Duration newMinAssetsLockDuration) private {
        self.minAssetsLockDuration = newMinAssetsLockDuration;
        emit MinAssetsLockDurationSet(newMinAssetsLockDuration);
    }
}
