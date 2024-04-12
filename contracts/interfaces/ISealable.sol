// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface ISealable {
    function resume() external;
    function pauseFor(uint256 duration) external;
    function isPaused() external view returns (bool);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function revokeRole(bytes32 role, address account) external;
    function PAUSE_ROLE() external pure returns (bytes32);
    function RESUME_ROLE() external pure returns (bytes32);
}
