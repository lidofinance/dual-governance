// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAccounting {
    struct ReportValues {
        uint256 timestamp;
        uint256 timeElapsed;
        uint256 clValidatorsBalance;
        uint256 clPendingBalance;
        uint256 withdrawalVaultBalance;
        uint256 elRewardsVaultBalance;
        uint256 sharesRequestedToBurn;
        uint256[] withdrawalFinalizationBatches;
        uint256 simulatedShareRate;
    }

    struct CalculatedValues {
        uint256 withdrawalsVaultTransfer;
        uint256 elRewardsVaultTransfer;
        uint256 etherToFinalizeWQ;
        uint256 sharesToFinalizeWQ;
        uint256 sharesToBurnForWithdrawals;
        uint256 totalSharesToBurn;
        uint256 sharesToMintAsFees;
        FeeDistribution feeDistribution;
        uint256 principalClBalance;
        uint256 preTotalShares;
        uint256 preTotalPooledEther;
        uint256 postInternalShares;
        uint256 postInternalEther;
        uint256 postTotalShares;
        uint256 postTotalPooledEther;
    }

    struct FeeDistribution {
        address[] moduleFeeRecipients;
        uint256[] moduleIds;
        uint256[] moduleSharesToMint;
        uint256 treasurySharesToMint;
    }

    function handleOracleReport(ReportValues memory _report) external;
    function simulateOracleReport(ReportValues calldata _report) external view returns (CalculatedValues memory update);
}
