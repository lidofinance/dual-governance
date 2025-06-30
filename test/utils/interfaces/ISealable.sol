// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISealable as ISealableBase} from "contracts/interfaces/ISealable.sol";

interface ISealable is ISealableBase {
    function PAUSE_ROLE() external view returns (bytes32);
    function RESUME_ROLE() external view returns (bytes32);

    function PAUSE_INFINITELY() external view returns (uint256);

    function isPaused() external returns (bool);
    function pauseFor(uint256 duration) external;

    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
}
