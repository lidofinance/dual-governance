// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IEscrow {
    function isRageQuitFinalized() external view returns (bool);
    function startRageQuit() external view returns (IEscrow);
    function getSignallingState() external view returns (uint256 totalSupport, uint256 rageQuitSupport);
}
