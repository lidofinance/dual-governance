// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Duration} from "../types/Duration.sol";
import {Timestamp, Timestamps} from "../types/Timestamp.sol";

import {ISealable} from "../interfaces/ISealable.sol";

struct TiebreakerConfigState {
    address resealManager;
    address tiebreakerCommittee;
    Duration tiebreakerActivationTimeout;
    address[] potentialDeadlockSealables;
}

interface ITiebreakerConfig {
    function RESEAL_MANAGER() external view returns (address);
    function TIEBREAKER_COMMITTEE() external view returns (address);
    function TIEBREAKER_ACTIVATION_TIMEOUT() external view returns (Duration);
    function getTiebreakerConfig() external view returns (TiebreakerConfigState memory config);
}

uint256 constant MAX_POTENTIAL_DEADLOCK_SELABLES_COUNT = 5;

contract TiebreakerConfig is ITiebreakerConfig {
    error MaxSealablesLimitOverflow(uint256 count, uint256 limit);

    address public immutable RESEAL_MANAGER;
    address public immutable TIEBREAKER_COMMITTEE;
    Duration public immutable TIEBREAKER_ACTIVATION_TIMEOUT;

    /// @dev The below variables may be considered as immutable representation of the dynamic array with
    /// the maximal capacity of five elements
    uint256 private immutable _POTENTIAL_DEADLOCK_SEALABLES_COUNT;
    address private immutable _POTENTIAL_DEADLOCK_SEALABLE_0;
    address private immutable _POTENTIAL_DEADLOCK_SEALABLE_1;
    address private immutable _POTENTIAL_DEADLOCK_SEALABLE_2;
    address private immutable _POTENTIAL_DEADLOCK_SEALABLE_3;
    address private immutable _POTENTIAL_DEADLOCK_SEALABLE_4;

    constructor(TiebreakerConfigState memory input) {
        RESEAL_MANAGER = input.resealManager;
        TIEBREAKER_COMMITTEE = input.tiebreakerCommittee;
        TIEBREAKER_ACTIVATION_TIMEOUT = input.tiebreakerActivationTimeout;

        address[] memory potentialDeadlockSealables = input.potentialDeadlockSealables;

        if (potentialDeadlockSealables.length > MAX_POTENTIAL_DEADLOCK_SELABLES_COUNT) {
            revert MaxSealablesLimitOverflow(potentialDeadlockSealables.length, MAX_POTENTIAL_DEADLOCK_SELABLES_COUNT);
        }

        _POTENTIAL_DEADLOCK_SEALABLES_COUNT = potentialDeadlockSealables.length;
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 0) _POTENTIAL_DEADLOCK_SEALABLE_0 = potentialDeadlockSealables[0];
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 1) _POTENTIAL_DEADLOCK_SEALABLE_1 = potentialDeadlockSealables[1];
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 2) _POTENTIAL_DEADLOCK_SEALABLE_2 = potentialDeadlockSealables[2];
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 3) _POTENTIAL_DEADLOCK_SEALABLE_3 = potentialDeadlockSealables[3];
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 4) _POTENTIAL_DEADLOCK_SEALABLE_4 = potentialDeadlockSealables[4];
    }

    function getTiebreakerConfig() external view returns (TiebreakerConfigState memory res) {
        res.resealManager = RESEAL_MANAGER;
        res.tiebreakerCommittee = TIEBREAKER_COMMITTEE;
        res.tiebreakerActivationTimeout = TIEBREAKER_ACTIVATION_TIMEOUT;

        res.potentialDeadlockSealables = new address[](_POTENTIAL_DEADLOCK_SEALABLES_COUNT);
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 0) res.potentialDeadlockSealables[0] = _POTENTIAL_DEADLOCK_SEALABLE_0;
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 1) res.potentialDeadlockSealables[1] = _POTENTIAL_DEADLOCK_SEALABLE_1;
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 2) res.potentialDeadlockSealables[2] = _POTENTIAL_DEADLOCK_SEALABLE_2;
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 3) res.potentialDeadlockSealables[3] = _POTENTIAL_DEADLOCK_SEALABLE_3;
        if (_POTENTIAL_DEADLOCK_SEALABLES_COUNT > 4) res.potentialDeadlockSealables[4] = _POTENTIAL_DEADLOCK_SEALABLE_4;
    }
}

library TiebreakerConfigUtils {
    function isTiebreakerActivationTimeoutPassed(
        TiebreakerConfigState memory config,
        Timestamp normalOrVetoCooldownExitedAt
    ) internal view returns (bool) {
        return Timestamps.now() >= config.tiebreakerActivationTimeout.addTo(normalOrVetoCooldownExitedAt);
    }

    function isSomeSealableDeadlocked(TiebreakerConfigState memory config) internal view returns (bool) {
        uint256 potentialDeadlockSealablesCount = config.potentialDeadlockSealables.length;
        for (uint256 i = 0; i < potentialDeadlockSealablesCount; ++i) {
            if (ISealable(config.potentialDeadlockSealables[i]).isPaused()) return true;
        }
        return false;
    }
}
