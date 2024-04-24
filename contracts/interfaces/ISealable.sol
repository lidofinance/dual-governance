// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface ISealable {
    function resume() external;
    function pauseFor(uint256 duration) external;
    function isPaused() external view returns (bool);
    function getResumeSinceTimestamp() external view returns (uint256);
}
