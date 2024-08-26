// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IStETH as IStETHBase} from "contracts/interfaces/IStETH.sol";

interface IStETH is IStETHBase {
    function getTotalShares() external view returns (uint256);
    function sharesOf(address account) external view returns (uint256);

    function removeStakingLimit() external;
    function getCurrentStakeLimit() external view returns (uint256);
    function getStakeLimitFullInfo()
        external
        view
        returns (
            bool isStakingPaused,
            bool isStakingLimitSet,
            uint256 currentStakeLimit,
            uint256 maxStakeLimit,
            uint256 maxStakeLimitGrowthBlocks,
            uint256 prevStakeLimit,
            uint256 prevStakeBlockNumber
        );
    function STAKING_CONTROL_ROLE() external view returns (bytes32);

    function submit(address referral) external payable returns (uint256);
}
