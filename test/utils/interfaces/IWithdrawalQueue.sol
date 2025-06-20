// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IWithdrawalQueue as IWithdrawalQueueBase} from "contracts/interfaces/IWithdrawalQueue.sol";

interface IWithdrawalQueue is IWithdrawalQueueBase {
    function getLastRequestId() external view returns (uint256);
    function getWithdrawalRequests(address _owner) external view returns (uint256[] memory requestsIds);
    function setApprovalForAll(address _operator, bool _approved) external;
    function grantRole(bytes32 role, address account) external;
    function pauseFor(uint256 duration) external;
    function isPaused() external returns (bool);
    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;
    function PAUSE_ROLE() external view returns (bytes32);
    function RESUME_ROLE() external view returns (bytes32);

    //
    // FINALIZATION FLOW
    //
    // Process when protocol is fixing the withdrawal request value and lock the required amount of ETH.
    // The value of a request after finalization can be:
    //  - nominal (when the amount of eth locked for this request are equal to the request's stETH)
    //  - discounted (when the amount of eth will be lower, because the protocol share rate dropped
    //   before request is finalized, so it will be equal to `request's shares` * `protocol share rate`)
    // The parameters that are required for finalization are:
    //  - current share rate of the protocol
    //  - id of the last request that can be finalized
    //  - the amount of eth that must be locked for these requests
    // To calculate the eth amount we'll need to know which requests in the queue will be finalized as nominal
    // and which as discounted and the exact value of the discount. It's impossible to calculate without the unbounded
    // loop over the unfinalized part of the queue. So, we need to extract a part of the algorithm off-chain, bring the
    // result with oracle report and check it later and check the result later.
    // So, we came to this solution:
    // Off-chain
    // 1. Oracle iterates over the queue off-chain and calculate the id of the latest finalizable request
    // in the queue. Then it splits all the requests that will be finalized into batches the way,
    // that requests in a batch are all nominal or all discounted.
    // And passes them in the report as the array of the ending ids of these batches. So it can be reconstructed like
    // `[lastFinalizedRequestId+1, batches[0]], [batches[0]+1, batches[1]] ... [batches[n-2], batches[n-1]]`
    // 2. Contract checks the validity of the batches on-chain and calculate the amount of eth required to
    //  finalize them. It can be done without unbounded loop using partial sums that are calculated on request enqueueing.
    // 3. Contract marks the request's as finalized and locks the eth for claiming. It also,
    //  set's the discount checkpoint for these request's if required that will be applied on claim for each request's
    // individually depending on request's share rate.

    /// @notice transient state that is used to pass intermediate results between several `calculateFinalizationBatches`
    //   invocations
    struct BatchesCalculationState {
        /// @notice amount of ether available in the protocol that can be used to finalize withdrawal requests
        ///  Will decrease on each call and will be equal to the remainder when calculation is finished
        ///  Should be set before the first call
        uint256 remainingEthBudget;
        /// @notice flag that is set to `true` if returned state is final and `false` if more calls are required
        bool finished;
        /// @notice static array to store last request id in each batch
        uint256[36] batches;
        /// @notice length of the filled part of `batches` array
        uint256 batchesLength;
    }

    function calculateFinalizationBatches(
        uint256 _maxShareRate,
        uint256 _maxTimestamp,
        uint256 _maxRequestsPerCall,
        BatchesCalculationState memory _state
    ) external view returns (BatchesCalculationState memory);

    function unfinalizedStETH() external view returns (uint256);

    function requestWithdrawalsWstETH(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);
}
