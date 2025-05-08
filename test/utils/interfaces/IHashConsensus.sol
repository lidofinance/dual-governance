// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IHashConsensus {
    function getFastLaneMembers()
        external
        view
        returns (address[] memory addresses, uint256[] memory lastReportedRefSlots);

    /// @notice Returns the immutable chain parameters required to calculate epoch and slot
    /// given a timestamp.
    ///
    function getChainConfig()
        external
        view
        returns (uint256 slotsPerEpoch, uint256 secondsPerSlot, uint256 genesisTime);

    function getCurrentFrame() external view returns (uint256 refSlot, uint256 reportProcessingDeadlineSlot);

    function getConsensusState()
        external
        view
        returns (uint256 refSlot, bytes32 consensusReport, bool isReportProcessing);

    function getFrameConfig()
        external
        view
        returns (uint256 initialEpoch, uint256 epochsPerFrame, uint256 fastLaneLengthSlots);

    function submitReport(uint256 slot, bytes32 report, uint256 consensusVersion) external;
}
