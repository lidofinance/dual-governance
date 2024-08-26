// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISealable} from "contracts/interfaces/ISealable.sol";

contract SealableMock is ISealable {
    bool private paused;
    bool private shouldRevertPauseFor;
    bool private shouldRevertIsPaused;
    bool private shouldRevertResume;

    function getResumeSinceTimestamp() external view override returns (uint256) {
        revert("Not implemented");
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

    function pauseFor(uint256) external override {
        if (shouldRevertPauseFor) {
            revert("pauseFor failed");
        }
        paused = true;
    }

    function isPaused() external view override returns (bool) {
        if (shouldRevertIsPaused) {
            revert("isPaused failed");
        }
        return paused;
    }

    function resume() external override {
        if (shouldRevertResume) {
            revert("resume failed");
        }
        paused = false;
    }
}
