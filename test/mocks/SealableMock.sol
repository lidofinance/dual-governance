// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISealable} from "contracts/interfaces/ISealable.sol";

contract SealableMock is ISealable {
    uint256 public constant PAUSE_INFINITELY = type(uint256).max;

    bool private paused;
    bool private shouldRevertPauseFor;
    bool private shouldRevertIsPaused;
    bool private shouldRevertResume;
    uint256 private _resumeSinceTimestamp;

    function getResumeSinceTimestamp() external view override returns (uint256) {
        return _resumeSinceTimestamp;
    }

    function setShouldRevertPauseFor(bool _shouldRevert) external {
        shouldRevertPauseFor = _shouldRevert;
    }

    function setShouldRevertIsPaused(bool _shouldRevert) external {
        shouldRevertIsPaused = _shouldRevert;
    }

    function setShouldRevertResume(bool _shouldRevert) external {
        shouldRevertResume = _shouldRevert;
    }

    function pauseFor(uint256 duration) external override {
        if (shouldRevertPauseFor) {
            revert("pauseFor failed");
        }
        if (duration == PAUSE_INFINITELY) {
            _resumeSinceTimestamp = PAUSE_INFINITELY;
        } else {
            _resumeSinceTimestamp = block.timestamp + duration;
        }
    }

    function resume() external override {
        if (shouldRevertResume) {
            revert("resume failed");
        }
        _resumeSinceTimestamp = block.timestamp;
    }
}
