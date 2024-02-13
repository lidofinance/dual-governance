// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

contract Configuration {
    uint256 internal constant DAY = 60 * 60 * 24;
    uint256 internal constant PERCENT = 10 ** 16;

    address public immutable adminProposer;

    uint256 public immutable minProposalExecutionTimelock = 3 * DAY;
    
    uint256 public immutable signallingDeactivationDuration = 5 * DAY;
    uint256 public immutable signallingCooldownDuration = 4 * DAY;
    uint256 public immutable rageQuitEthWithdrawalTimelock = 30 * DAY;

    uint256 public immutable firstSealThreshold = 3 * PERCENT;
    uint256 public immutable secondSealThreshold = 15 * PERCENT;
    uint256 public immutable signallingMinDuration = 3 days;
    uint256 public immutable signallingMaxDuration = 30 days;

    constructor(address adminProposer_) {
        adminProposer = adminProposer_;
    }

    function getSignallingThresholdData() external view returns (uint256, uint256, uint256, uint256) {
        return (firstSealThreshold, secondSealThreshold, signallingMinDuration, signallingMaxDuration);
    }
}
