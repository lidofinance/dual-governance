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

    // Lido
    function getBeaconStat()
        external
        view
        returns (uint256 depositedValidators, uint256 beaconValidators, uint256 beaconBalance);

    /**
     * @notice Updates accounting stats, collects EL rewards and distributes collected rewards
     *         if beacon balance increased, performs withdrawal requests finalization
     * @dev periodically called by the AccountingOracle contract
     *
     * @param _reportTimestamp the moment of the oracle report calculation
     * @param _timeElapsed seconds elapsed since the previous report calculation
     * @param _clValidators number of Lido validators on Consensus Layer
     * @param _clBalance sum of all Lido validators' balances on Consensus Layer
     * @param _withdrawalVaultBalance withdrawal vault balance on Execution Layer at `_reportTimestamp`
     * @param _elRewardsVaultBalance elRewards vault balance on Execution Layer at `_reportTimestamp`
     * @param _sharesRequestedToBurn shares requested to burn through Burner at `_reportTimestamp`
     * @param _withdrawalFinalizationBatches the ascendingly-sorted array of withdrawal request IDs obtained by calling
     * WithdrawalQueue.calculateFinalizationBatches. Empty array means that no withdrawal requests should be finalized
     * @param _simulatedShareRate share rate that was simulated by oracle when the report data created (1e27 precision)
     *
     * NB: `_simulatedShareRate` should be calculated off-chain by calling the method with `eth_call` JSON-RPC API
     * while passing empty `_withdrawalFinalizationBatches` and `_simulatedShareRate` == 0, plugging the returned values
     * to the following formula: `_simulatedShareRate = (postTotalPooledEther * 1e27) / postTotalShares`
     *
     * @return postRebaseAmounts
     *   - [0]: `postTotalPooledEther` amount of ether in the protocol after report
     *   - [1]: `postTotalShares` amount of shares in the protocol after report
     *   - [2]: `withdrawals` withdrawn from the withdrawals vault
     *   - [3]: `elRewards` withdrawn from the execution layer rewards vault
     */
    function handleOracleReport(
        // Oracle timings
        uint256 _reportTimestamp,
        uint256 _timeElapsed,
        // CL values
        uint256 _clValidators,
        uint256 _clBalance,
        // EL values
        uint256 _withdrawalVaultBalance,
        uint256 _elRewardsVaultBalance,
        uint256 _sharesRequestedToBurn,
        // Decision about withdrawals processing
        uint256[] calldata _withdrawalFinalizationBatches,
        uint256 _simulatedShareRate
    ) external returns (uint256[4] memory postRebaseAmounts);

    function getBufferedEther() external view returns (uint256);
    function getTotalPooledEther() external view returns (uint256);
}
