// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStETH is IERC20 {
    function STAKING_CONTROL_ROLE() external view returns (bytes32);
    function removeStakingLimit() external;
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

    function getTotalShares() external view returns (uint256);
    function sharesOf(address account) external view returns (uint256);
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);

    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);

    function transferShares(address to, uint256 amount) external;
    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);
    function submit(address referral) external payable returns (uint256);
}
