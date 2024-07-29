// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISealable} from "../interfaces/ISealable.sol";

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Duration.sol";
import {State as DualGovernanceState} from "./DualGovernanceStateMachine.sol";

interface IResealManger {
    function resume(address sealable) external;
}

library Tiebreaker {
    error InvalidTiebreak();
    error TiebreakNotAllowed();
    error InvalidResealManager(address value);
    error InvalidTiebreakerCommittee(address value);
    error InvalidTiebreakerActivationTimeout(Duration value);
    error InvalidSealableWithdrawalBlockersCount(uint256 value);

    event SealableResumed(address sealable);
    event ResealManagerSet(address newResealManager);
    event TiebreakerCommitteeSet(address newTiebreakerCommittee);
    event TiebreakerActivationTimeoutSet(Duration newTiebreakerActivationTimeout);
    event SealableWithdrawalBlockersSet(address[] newSealableWithdrawalBlockers);

    struct Config {
        uint256 maxSealableWithdrawalBlockers;
        Duration minTiebreakerActivationTimeout;
        Duration maxTiebreakerActivationTimeout;
    }

    struct Context {
        address resealManager;
        address tiebreakerCommittee;
        Duration tiebreakerActivationTimeout;
        address[] sealableWithdrawalBlockers;
    }

    function setResealManager(Context storage self, address newResealManager) internal {
        if (newResealManager == address(0)) {
            revert InvalidResealManager(newResealManager);
        }
        if (self.resealManager == newResealManager) {
            return;
        }
        self.resealManager = newResealManager;
        emit ResealManagerSet(newResealManager);
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
        Config memory config,
        Duration newTiebreakerActivationTimeout
    ) internal {
        if (
            newTiebreakerActivationTimeout > config.minTiebreakerActivationTimeout
                || newTiebreakerActivationTimeout < config.minTiebreakerActivationTimeout
        ) {
            revert InvalidTiebreakerActivationTimeout(newTiebreakerActivationTimeout);
        }
        if (self.tiebreakerActivationTimeout == newTiebreakerActivationTimeout) {
            return;
        }
        self.tiebreakerActivationTimeout = newTiebreakerActivationTimeout;
        emit TiebreakerActivationTimeoutSet(newTiebreakerActivationTimeout);
    }

    function setSealableWithdrawalBlockers(
        Context storage self,
        Config memory config,
        address[] memory newSealableWithdrawalBlockers
    ) internal {
        if (newSealableWithdrawalBlockers.length > config.maxSealableWithdrawalBlockers) {
            revert InvalidSealableWithdrawalBlockersCount(newSealableWithdrawalBlockers.length);
        }
        address[] memory oldWithdrawalBlockers = self.sealableWithdrawalBlockers;
        if (keccak256(abi.encode(oldWithdrawalBlockers)) == keccak256(abi.encode(newSealableWithdrawalBlockers))) {
            return;
        }
        self.sealableWithdrawalBlockers = newSealableWithdrawalBlockers;
        emit SealableWithdrawalBlockersSet(newSealableWithdrawalBlockers);
    }

    function resumeSealable(Context memory self, address sealable) internal {
        IResealManger(self.resealManager).resume(sealable);
        emit SealableResumed(sealable);
    }

    function checkTiebreakerCommittee(Context memory self, address account) internal pure {
        if (account != self.tiebreakerCommittee) {
            revert InvalidTiebreakerCommittee(account);
        }
    }

    function checkTie(
        Context memory self,
        DualGovernanceState state,
        Timestamp normalOrVetoCooldownExitedAt
    ) internal view {
        if (!isTie(self, state, normalOrVetoCooldownExitedAt)) {
            revert TiebreakNotAllowed();
        }
    }

    function isTie(
        Context memory self,
        DualGovernanceState state,
        Timestamp normalOrVetoCooldownExitedAt
    ) internal view returns (bool) {
        if (state == DualGovernanceState.Normal || state == DualGovernanceState.VetoCooldown) return false;

        // when the governance is locked for long period of time
        if (Timestamps.now() >= self.tiebreakerActivationTimeout.addTo(normalOrVetoCooldownExitedAt)) {
            return true;
        }

        return state == DualGovernanceState.RageQuit && isSomeSealableDeadlocked(self);
    }

    function isSomeSealableDeadlocked(Context memory self) internal view returns (bool) {
        uint256 potentialDeadlockSealablesCount = self.sealableWithdrawalBlockers.length;
        for (uint256 i = 0; i < potentialDeadlockSealablesCount; ++i) {
            if (ISealable(self.sealableWithdrawalBlockers[i]).isPaused()) return true;
        }
        return false;
    }
}
