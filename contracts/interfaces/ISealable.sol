// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ISealable {
    function resume() external;
    function pauseFor(uint256 duration) external;
    function getResumeSinceTimestamp() external view returns (uint256);
}
