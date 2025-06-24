// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IStakingRouter {
    function getStakingFeeAggregateDistribution()
        external
        view
        returns (uint256 modulesFee, uint256 treasuryFee, uint256 basePrecision);
}
