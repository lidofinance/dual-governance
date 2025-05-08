// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAccountingOracle {
    struct ReportData {
        ///
        /// Oracle consensus info
        ///

        /// @dev Version of the oracle consensus rules. Current version expected
        /// by the oracle can be obtained by calling getConsensusVersion().
        uint256 consensusVersion;
        /// @dev Reference slot for which the report was calculated. If the slot
        /// contains a block, the state being reported should include all state
        /// changes resulting from that block. The epoch containing the slot
        /// should be finalized prior to calculating the report.
        uint256 refSlot;
        ///
        /// CL values
        ///

        /// @dev The number of validators on consensus layer that were ever deposited
        /// via Lido as observed at the reference slot.
        uint256 numValidators;
        /// @dev Cumulative balance of all Lido validators on the consensus layer
        /// as observed at the reference slot.
        uint256 clBalanceGwei;
        /// @dev Ids of staking modules that have more exited validators than the number
        /// stored in the respective staking module contract as observed at the reference
        /// slot.
        uint256[] stakingModuleIdsWithNewlyExitedValidators;
        /// @dev Number of ever exited validators for each of the staking modules from
        /// the stakingModuleIdsWithNewlyExitedValidators array as observed at the
        /// reference slot.
        uint256[] numExitedValidatorsByStakingModule;
        ///
        /// EL values
        ///

        /// @dev The ETH balance of the Lido withdrawal vault as observed at the reference slot.
        uint256 withdrawalVaultBalance;
        /// @dev The ETH balance of the Lido execution layer rewards vault as observed
        /// at the reference slot.
        uint256 elRewardsVaultBalance;
        /// @dev The shares amount requested to burn through Burner as observed
        /// at the reference slot. The value can be obtained in the following way:
        /// `(coverSharesToBurn, nonCoverSharesToBurn) = IBurner(burner).getSharesRequestedToBurn()
        /// sharesRequestedToBurn = coverSharesToBurn + nonCoverSharesToBurn`
        uint256 sharesRequestedToBurn;
        ///
        /// Decision
        ///

        /// @dev The ascendingly-sorted array of withdrawal request IDs obtained by calling
        /// WithdrawalQueue.calculateFinalizationBatches. Empty array means that no withdrawal
        /// requests should be finalized.
        uint256[] withdrawalFinalizationBatches;
        /// @dev The share/ETH rate with the 10^27 precision (i.e. the price of one stETH share
        /// in ETH where one ETH is denominated as 10^27) that would be effective as the result of
        /// applying this oracle report at the reference slot, with withdrawalFinalizationBatches
        /// set to empty array and simulatedShareRate set to 0.
        uint256 simulatedShareRate;
        /// @dev Whether, based on the state observed at the reference slot, the protocol should
        /// be in the bunker mode.
        bool isBunkerMode;
        ///
        /// Extra data — the oracle information that allows asynchronous processing in
        /// chunks, after the main data is processed. The oracle doesn't enforce that extra data
        /// attached to some data report is processed in full before the processing deadline expires
        /// or a new data report starts being processed, but enforces that no processing of extra
        /// data for a report is possible after its processing deadline passes or a new data report
        /// arrives.
        ///
        /// Depending on the size of the extra data, the processing might need to be split into
        /// multiple transactions. Each transaction contains a chunk of report data (an array of items)
        /// and the hash of the next transaction. The last transaction will contain ZERO_HASH
        /// as the next transaction hash.
        ///
        /// | 32 bytes |    array of items
        /// | nextHash |         ...
        ///
        /// Each item being encoded as follows:
        ///
        ///    3 bytes    2 bytes      X bytes
        /// | itemIndex | itemType | itemPayload |
        ///
        /// itemIndex is a 0-based index into the extra data array;
        /// itemType is the type of extra data item;
        /// itemPayload is the item's data which interpretation depends on the item's type.
        ///
        /// Items should be sorted ascendingly by the (itemType, ...itemSortingKey) compound key
        /// where `itemSortingKey` calculation depends on the item's type (see below).
        ///
        /// ----------------------------------------------------------------------------------------
        ///
        /// itemType=0 (EXTRA_DATA_TYPE_STUCK_VALIDATORS): stuck validators by node operators.
        /// itemPayload format:
        ///
        /// | 3 bytes  |   8 bytes    |  nodeOpsCount * 8 bytes  |  nodeOpsCount * 16 bytes  |
        /// | moduleId | nodeOpsCount |      nodeOperatorIds     |   stuckValidatorsCounts   |
        ///
        /// moduleId is the staking module for which exited keys counts are being reported.
        ///
        /// nodeOperatorIds contains an array of ids of node operators that have total stuck
        /// validators counts changed compared to the staking module smart contract storage as
        /// observed at the reference slot. Each id is a 8-byte uint, ids are packed tightly.
        ///
        /// nodeOpsCount contains the number of node operator ids contained in the nodeOperatorIds
        /// array. Thus, nodeOpsCount = byteLength(nodeOperatorIds) / 8.
        ///
        /// stuckValidatorsCounts contains an array of stuck validators total counts, as observed at
        /// the reference slot, for the node operators from the nodeOperatorIds array, in the same
        /// order. Each count is a 16-byte uint, counts are packed tightly. Thus,
        /// byteLength(stuckValidatorsCounts) = nodeOpsCount * 16.
        ///
        /// nodeOpsCount must not be greater than maxNodeOperatorsPerExtraDataItem specified
        /// in OracleReportSanityChecker contract. If a staking module has more node operators
        /// with total stuck validators counts changed compared to the staking module smart contract
        /// storage (as observed at the reference slot), reporting for that module should be split
        /// into multiple items.
        ///
        /// Item sorting key is a compound key consisting of the module id and the first reported
        /// node operator's id:
        ///
        /// itemSortingKey = (moduleId, nodeOperatorIds[0:8])
        ///
        /// ----------------------------------------------------------------------------------------
        ///
        /// itemType=1 (EXTRA_DATA_TYPE_EXITED_VALIDATORS): exited validators by node operators.
        ///
        /// The payload format is exactly the same as for itemType=EXTRA_DATA_TYPE_STUCK_VALIDATORS,
        /// except that, instead of stuck validators counts, exited validators counts are reported.
        /// The `itemSortingKey` is calculated identically.
        ///
        /// ----------------------------------------------------------------------------------------
        ///
        /// The oracle daemon should report exited/stuck validators counts ONLY for those
        /// (moduleId, nodeOperatorId) pairs that contain outdated counts in the staking
        /// module smart contract as observed at the reference slot.
        ///
        /// Extra data array can be passed in different formats, see below.
        ///

        /// @dev Format of the extra data.
        ///
        /// Currently, only the EXTRA_DATA_FORMAT_EMPTY=0 and EXTRA_DATA_FORMAT_LIST=1
        /// formats are supported. See the constant defining a specific data format for
        /// more info.
        ///
        uint256 extraDataFormat;
        /// @dev Hash of the extra data. See the constant defining a specific extra data
        /// format for the info on how to calculate the hash.
        ///
        /// Must be set to a zero hash if the oracle report contains no extra data.
        ///
        bytes32 extraDataHash;
        /// @dev Number of the extra data items.
        ///
        /// Must be set to zero if the oracle report contains no extra data.
        ///
        uint256 extraDataItemsCount;
    }

    function getContractVersion() external view returns (uint256);
    function getConsensusVersion() external view returns (uint256);
    function submitReportData(ReportData calldata data, uint256 contractVersion) external;

    struct ProcessingState {
        /// @notice Reference slot for the current reporting frame.
        uint256 currentFrameRefSlot;
        /// @notice The last time at which a data can be submitted for the current reporting frame.
        uint256 processingDeadlineTime;
        /// @notice Hash of the main report data. Zero bytes if consensus on the hash hasn't been
        /// reached yet for the current reporting frame.
        bytes32 mainDataHash;
        /// @notice Whether the main report data for the current reporting frame has already been
        /// submitted.
        bool mainDataSubmitted;
        /// @notice Hash of the extra report data. Should be ignored unless `mainDataSubmitted`
        /// is true.
        bytes32 extraDataHash;
        /// @notice Format of the extra report data for the current reporting frame. Should be
        /// ignored unless `mainDataSubmitted` is true.
        uint256 extraDataFormat;
        /// @notice Whether any extra report data for the current reporting frame has been submitted.
        bool extraDataSubmitted;
        /// @notice Total number of extra report data items for the current reporting frame.
        /// Should be ignored unless `mainDataSubmitted` is true.
        uint256 extraDataItemsCount;
        /// @notice How many extra report data items are already submitted for the current
        /// reporting frame.
        uint256 extraDataItemsSubmitted;
    }

    function getProcessingState() external view returns (ProcessingState memory result);
    function submitReportExtraDataList(bytes calldata data) external;
    function submitReportExtraDataEmpty() external;
}
