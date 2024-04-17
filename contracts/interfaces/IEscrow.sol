// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IEscrow {
    function initialize(address dualGovernance) external;

    function startRageQuit(uint256 rageQuitExtraTimelock, uint256 rageQuitWithdrawalsTimelock) external;

    function MASTER_COPY() external view returns (address);
    function isRageQuitFinalized() external view returns (bool);
    function getRageQuitSupport() external view returns (uint256 rageQuitSupport);
}
