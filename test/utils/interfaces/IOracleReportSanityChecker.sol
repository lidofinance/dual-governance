// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IOracleReportSanityChecker {
    /// @notice The set of restrictions used in the sanity checks of the oracle report
    /// @dev struct is loaded from the storage and stored in memory during the tx running
    struct LimitsList {
        /// @notice The max possible exited ETH amount that might be reported
        ///     per single day.
        /// @dev Must fit into uint32 (<= 4_294_967_295)
        uint256 exitedEthAmountPerDayLimit;
        /// @notice The max possible appeared ETH amount that might be reported
        ///     per single day.
        /// @dev Must fit into uint32 (<= 4_294_967_295)
        uint256 appearedEthAmountPerDayLimit;
        /// @notice The max annual increase of the total validators' balances on the Consensus Layer
        ///     since the previous oracle report
        /// (the increase that is limited does not include fresh deposits to the Beacon Chain as well as withdrawn ether)
        ///
        /// @dev Represented in the Basis Points (100% == 10_000)
        uint256 annualBalanceIncreaseBPLimit;

        /// @notice The max deviation of the provided `simulatedShareRate`
        ///     and the actual one within the currently processing oracle report
        /// @dev Represented in the Basis Points (100% == 10_000)
        uint256 simulatedShareRateDeviationBPLimit;

        /// @notice The max requested to exit balance in ETH
        /// @dev Sum of all max effective balances of all requested validators should be equal or lower in one report
        uint256 maxBalanceExitRequestedPerReportInEth;
        /// @notice WC 0x01 max effective balance equivalent weight in ETH
        /// @dev Must fit into uint16 and be non-zero
        uint256 maxEffectiveBalanceWeightWCType01;
        /// @notice WC 0x02 max effective balance equivalent weight in ETH
        /// @dev Must fit into uint16 and be non-zero
        uint256 maxEffectiveBalanceWeightWCType02;

        /// @notice The max number of data list items reported to accounting oracle in extra data per single transaction
        /// @dev Must fit into uint16 (<= 65_535)
        uint256 maxItemsPerExtraDataTransaction;
        /// @notice The max number of node operators reported per extra data list item
        /// @dev Must fit into uint16 (<= 65_535)
        uint256 maxNodeOperatorsPerExtraDataItem;
        /// @notice The min time required to be passed from the creation of the request to be
        ///     finalized till the time of the oracle report
        uint256 requestTimestampMargin;
        /// @notice The positive token rebase allowed per single LidoOracle report
        /// @dev uses 1e9 precision, e.g.: 1e6 - 0.1%; 1e9 - 100%, see `setMaxPositiveTokenRebase()`
        uint256 maxPositiveTokenRebase;
        /// @notice The max allowed CL balance decrease over the CL_BALANCE_WINDOW as a fraction of the adjusted balance
        /// @dev Represented in the Basis Points (100% == 10_000). Must fit into uint16 (<= 65_535)
        uint256 maxCLBalanceDecreaseBP;
        /// @notice The maximum percent on how Second Opinion Oracle reported value could be greater
        ///     than reported by the AccountingOracle. There is an assumption that second opinion oracle CL balance
        ///     can be greater as calculated for the withdrawal credentials.
        /// @dev Represented in the Basis Points (100% == 10_000)
        uint256 clBalanceOraclesErrorUpperBPLimit;
        /// @notice The max possible consolidation ETH amount that might be reported
        ///     per single day.
        /// @dev Must fit into uint32 (<= 4_294_967_295)
        uint256 consolidationEthAmountPerDayLimit;
        /// @notice Effective ETH amount attributed to a single exited validator
        ///     in the exited ETH amount per day check.
        /// @dev Stored in whole ETH units. Must fit into uint16.
        uint256 exitedValidatorEthAmountLimit;
        /// @notice Extra protocol-level pending balance cap to tolerate bounded side deposits
        ///     or same-validator top-ups that were not funded by Lido.
        /// @dev Stored in whole ETH units. Must fit into uint16.
        uint256 externalPendingBalanceCapEth;
    }

    function grantRole(bytes32 role, address account) external;

    function getOracleReportLimits() external view returns (LimitsList memory);

    function setAnnualBalanceIncreaseBPLimit(uint256 _annualBalanceIncreaseBPLimit) external;
    function setRequestTimestampMargin(uint256 _requestTimestampMargin) external;

    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);
    function REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE() external pure returns (bytes32);
    function ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE() external pure returns (bytes32);
}
