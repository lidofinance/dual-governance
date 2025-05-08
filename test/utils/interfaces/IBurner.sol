// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IBurner {
    function getSharesRequestedToBurn() external view returns (uint256 coverShares, uint256 nonCoverShares);
}
