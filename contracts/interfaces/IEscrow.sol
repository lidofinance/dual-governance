// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IEscrow {
    function startRageQuit() external;
    function initialize(address dualGovernance) external;

    function MASTER_COPY() external view returns (address);
    function isRageQuitFinalized() external view returns (bool);
    function getSignallingState() external view returns (uint256 totalSupport, uint256 rageQuitSupport);
}
