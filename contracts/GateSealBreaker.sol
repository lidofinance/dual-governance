// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IGateSeal} from "./interfaces/IGateSeal.sol";
import {ISealable} from "./interfaces/ISealable.sol";
import {SealableCalls} from "./libraries/SealableCalls.sol";

interface IDualGovernance {
    function isSchedulingEnabled() external view returns (bool);
}

contract GateSealBreaker is Ownable {
    using SafeCast for uint256;
    using SealableCalls for ISealable;

    struct GateSealState {
        uint40 registeredAt;
        uint40 releaseStartedAt;
        uint40 releaseEnactedAt;
    }

    error GovernanceLocked();
    error ReleaseNotStarted();
    error GateSealNotActivated();
    error ReleaseDelayNotPassed();
    error DualGovernanceIsLocked();
    error GateSealAlreadyReleased();
    error MinSealDurationNotPassed();
    error GateSealIsNotRegistered(IGateSeal gateSeal);
    error GateSealAlreadyRegistered(IGateSeal gateSeal, uint256 registeredAt);

    event ReleaseIsPausedConditionNotMet(ISealable sealable);
    event ReleaseResumeCallFailed(ISealable sealable, bytes lowLevelError);
    event ReleaseIsPausedCheckFailed(ISealable sealable, bytes lowLevelError);

    uint256 public immutable RELEASE_DELAY;
    IDualGovernance public immutable DUAL_GOVERNANCE;

    constructor(uint256 releaseDelay, address owner, address dualGovernance) Ownable(owner) {
        RELEASE_DELAY = releaseDelay;
        DUAL_GOVERNANCE = IDualGovernance(dualGovernance);
    }

    mapping(IGateSeal gateSeal => GateSealState) internal _gateSeals;

    function registerGateSeal(IGateSeal gateSeal) external {
        _checkOwner();
        if (_gateSeals[gateSeal].registeredAt != 0) {
            revert GateSealAlreadyRegistered(gateSeal, _gateSeals[gateSeal].registeredAt);
        }
        _gateSeals[gateSeal].registeredAt = block.timestamp.toUint40();
    }

    function startRelease(IGateSeal gateSeal) external {
        _checkGateSealRegistered(gateSeal);
        _checkGateSealActivated(gateSeal);
        _checkMinSealDurationPassed(gateSeal);
        _checkGateSealNotReleased(gateSeal);
        _checkGovernanceNotLocked();

        _gateSeals[gateSeal].releaseStartedAt = block.timestamp.toUint40();
    }

    function enactRelease(IGateSeal gateSeal) external {
        _checkGateSealRegistered(gateSeal);
        GateSealState memory gateSealState = _gateSeals[gateSeal];
        if (gateSealState.releaseStartedAt == 0) {
            revert ReleaseNotStarted();
        }
        if (block.timestamp <= gateSealState.releaseStartedAt + RELEASE_DELAY) {
            revert ReleaseDelayNotPassed();
        }

        _gateSeals[gateSeal].releaseEnactedAt = block.timestamp.toUint40();

        address[] memory sealed_ = gateSeal.sealed_sealables();

        for (uint256 i = 0; i < sealed_.length; ++i) {
            ISealable sealable = ISealable(sealed_[i]);
            (bool isPausedCallSuccess, bytes memory isPausedLowLevelError, bool isPaused) = sealable.callIsPaused();
            if (!isPausedCallSuccess) {
                emit ReleaseIsPausedCheckFailed(sealable, isPausedLowLevelError);
            }
            if (!isPaused) {
                emit ReleaseIsPausedConditionNotMet(sealable);
                continue;
            }
            (bool resumeCallSuccess, bytes memory lowLevelError) = sealable.callResume();
            if (!resumeCallSuccess) {
                emit ReleaseResumeCallFailed(sealable, lowLevelError);
            }
        }
    }

    function _checkGateSealRegistered(IGateSeal gateSeal) internal view {
        if (_gateSeals[gateSeal].registeredAt == 0) {
            revert GateSealIsNotRegistered(gateSeal);
        }
    }

    function _checkGateSealActivated(IGateSeal gateSeal) internal view {
        address[] memory sealed_ = gateSeal.sealed_sealables();
        if (sealed_.length == 0) {
            revert GateSealNotActivated();
        }
    }

    function _checkMinSealDurationPassed(IGateSeal gateSeal) internal view {
        if (block.timestamp < gateSeal.get_expiry_timestamp() + gateSeal.get_min_seal_duration()) {
            revert MinSealDurationNotPassed();
        }
    }

    function _checkGateSealNotReleased(IGateSeal gateSeal) internal view {
        if (_gateSeals[gateSeal].releaseStartedAt != 0) {
            revert GateSealAlreadyReleased();
        }
    }

    function _checkGovernanceNotLocked() internal view {
        if (!DUAL_GOVERNANCE.isSchedulingEnabled()) {
            revert GovernanceLocked();
        }
    }
}
