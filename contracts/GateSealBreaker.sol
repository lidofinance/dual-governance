// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IGovernanceState {
    enum State {
        Normal,
        VetoSignalling,
        VetoSignallingDeactivation,
        VetoCooldown,
        RageQuit
    }

    function currentState() external view returns (State);
}

interface ISealable {
    function resume() external;
    function pauseFor(uint256 duration) external;
    function isPaused() external view returns (bool);
}

struct SealFailure {
    address sealable;
    bytes lowLevelError;
}

library SealableCalls {
    function callPauseFor(
        ISealable sealable,
        uint256 sealDuration
    ) internal returns (bool success, bytes memory lowLevelError) {
        try sealable.pauseFor(sealDuration) {
            (bool isPausedCallSuccess, bytes memory isPausedLowLevelError, bool isPaused) = callIsPaused(sealable);
            success = isPausedCallSuccess && isPaused;
            lowLevelError = isPausedLowLevelError;
        } catch (bytes memory pauseForLowLevelError) {
            success = false;
            lowLevelError = pauseForLowLevelError;
        }
    }

    function callIsPaused(ISealable sealable)
        internal
        view
        returns (bool success, bytes memory lowLevelError, bool isPaused)
    {
        try sealable.isPaused() returns (bool isPausedResult) {
            success = true;
            isPaused = isPausedResult;
        } catch (bytes memory isPausedLowLevelError) {
            success = false;
            lowLevelError = isPausedLowLevelError;
        }
    }

    function callResume(ISealable sealable) internal returns (bool success, bytes memory lowLevelError) {
        try sealable.resume() {
            (bool isPausedCallSuccess, bytes memory isPausedLowLevelError, bool isPaused) = callIsPaused(sealable);
            success = isPausedCallSuccess && isPaused;
            lowLevelError = isPausedLowLevelError;
        } catch (bytes memory resumeLowLevelError) {
            success = false;
            lowLevelError = resumeLowLevelError;
        }
    }
}

interface IGateSeal {
    function get_min_seal_duration() external view returns (uint256);
    function get_expiry_timestamp() external view returns (uint256);
    function sealed_sealables() external view returns (address[] memory);
    function seal(address[] calldata sealables) external;
}

interface IDualGovernance {
    function isExecutionEnabled() external view returns (bool);
}

abstract contract GateSealBreaker is Ownable {
    using SafeCast for uint256;
    using SealableCalls for ISealable;

    struct GateSealState {
        uint40 registeredAt;
        uint40 releaseStartedAt;
        uint40 releaseEnactedAt;
    }

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

    constructor(uint256 releaseDelay, address owner) Ownable(owner) {
        RELEASE_DELAY = releaseDelay;
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
        _checkReleaseStartAllowed(gateSeal);

        _gateSeals[gateSeal].releaseStartedAt = block.timestamp.toUint40();
    }

    function enactRelease(IGateSeal gateSeal) external {
        _checkGateSealRegistered(gateSeal);
        GateSealState memory gateSealState = _gateSeals[gateSeal];
        if (gateSealState.releaseStartedAt == 0) {
            revert ReleaseNotStarted();
        }
        if (block.timestamp < gateSealState.releaseStartedAt + RELEASE_DELAY) {
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

    function _checkReleaseStartAllowed(IGateSeal gateSeal) internal virtual;
}

contract GateSealBreakerDualGovernance is GateSealBreaker {
    IDualGovernance public immutable DUAL_GOVERNANCE;

    error GovernanceIsLocked();

    constructor(uint256 releaseDelay, address owner, address dualGovernance) GateSealBreaker(releaseDelay, owner) {
        DUAL_GOVERNANCE = IDualGovernance(dualGovernance);
    }

    function _checkReleaseStartAllowed(IGateSeal /* gateSeal */ ) internal view override {
        if (!DUAL_GOVERNANCE.isExecutionEnabled()) {
            revert GovernanceIsLocked();
        }
    }
}
