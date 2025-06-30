
import "./Escrow_validState.spec";
/**
    Verification of asset holding

**/

// Run link, all rules: https://prover.certora.com/output/37629/2347e214e75545eaae7f9577963e9f05/?anonymousKey=9da0447d63d2b7c13a8bb5c5787b5d592c7f8c59
// Status, all rules: PASSING

/** @title Those request id left to claim are indeed not claimed
**/
invariant solvency_batchesQueue_solvent_leftToClaim(uint256 index, uint256 id) 
        (( index > 0 && index <  currentContract._batchesQueue.batches.length && id >= currentContract._batchesQueue.batches[index].firstUnstETHId && 
    id <= currentContract._batchesQueue.batches[index].lastUnstETHId && (!withdrawalQueue.requests[id].isClaimed)) => 
        ( currentContract._batchesQueue.info.totalUnstETHIdsCount - currentContract._batchesQueue.info.totalUnstETHIdsClaimed >=   
            // all indexes unclaimed completely (at least one element to claim)
            (countOFBatchIds[currentContract._batchesQueue.batches.length] - countOFBatchIds[index]) - 
            // claimed in this index 
            ( id - (currentContract._batchesQueue.batches[index].firstUnstETHId)) )
    )
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState(); 
            requireInvariant solvency_batchesQueue_allClaimed(index, id);
            assumingThreeOnly();
        }
    }

/** @title when all nft are claimed, the last one has been claimed **/ 
invariant solvency_batchesQueue_allClaimed(uint256 index, uint256 id) 

    // isAllBatchesClaimed and there are batches queues 
    (currentContract._batchesQueue.batches.length > 1 => 
        (isAllStEthNFTClaimed()  =>  withdrawalQueue.requests[currentContract._batchesQueue.batches[currentContract._batchesQueue.info.lastClaimedBatchIndex].lastUnstETHId].isClaimed
    ))
    &&
    ( currentContract._batchesQueue.info.lastClaimedBatchIndex < currentContract._batchesQueue.batches.length ||
    (currentContract._batchesQueue.info.lastClaimedBatchIndex==0 && currentContract._batchesQueue.batches.length==0 )
    )
    && ( currentContract._batchesQueue.info.lastClaimedUnstETHIdIndex <= currentContract._batchesQueue.batches[currentContract._batchesQueue.info.lastClaimedBatchIndex].lastUnstETHId -currentContract._batchesQueue.batches[currentContract._batchesQueue.info.lastClaimedBatchIndex].firstUnstETHId)
    &&
    ( getRageQuitExtensionPeriodStartedAt() > 0  =>  
        ((        
        withdrawalQueue.requests[currentContract._batchesQueue.batches[currentContract._batchesQueue.info.lastClaimedBatchIndex].lastUnstETHId].isFinalized ) 
        &&
        ( currentContract._batchesQueue.info.totalUnstETHIdsClaimed == currentContract._batchesQueue.info.totalUnstETHIdsCount && 
        isBatchQueueStateClosed() )
        )
    )
    

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState(); 
            requireInvariant solvency_batchesQueue_solvent_leftToClaim(index, id);
            assumingThreeOnly();
        }
    }




