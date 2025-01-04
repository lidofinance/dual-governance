
import "./escrow_validState.spec";
/**
    Verification of asset holding

**/
/** 
@title Total holding of wst_eth is zero as all wst_eth are converted to st_eth
**/  
invariant solvency_zeroWstEthBalance() 
    wst_eth.balanceOf(currentContract) == 0
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
    }
}

 /** @title Total holding of stEth before rageQuit start 
 **/ 
invariant solvency_stETH_before_rageQuit() 
    !isRageQuitState() => stEth.getPooledEthByShares(currentContract._accounting.stETHTotals.lockedShares
    ) <=  stEth.balanceOf(currentContract) 

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
    }
}


/** @title Before rage quit eth value of escrow can not be reduced  
**/
rule solvency_ETH_before_rageQuit(method f) 
{
    bool rageQuitStateBefore = isRageQuitState();
    uint256 before = nativeBalances[currentContract]; 
    env e;
    calldataarg args;
    // Escrow is the starting point, it can never call directly an arbitrary function
    require (e.msg.sender != currentContract);  
    f(e,args);
    uint256 after = nativeBalances[currentContract]; 
    assert !rageQuitStateBefore => after >= before;
}


/** @title Total holding of eth by the escrow:
    1. For the locked shares:
        claimedETH * sumStETHLockedShares / stETHTotals.lockedShares 

        where sumStETHLockedShares is the current holding of shares 
    2. For the unstEth holding:
            sumClaimedUnSTEth - sumWithdrawnUnSTEth
        where:
            sumClaimedUnSTEth - total amount of all claimed unstEth 
            sumWithdrawnUnSTEth - total amount already withdrawn 

**/
invariant solvency_ETH() 
    // pool of batch queue
    // if lockedShares is zero than this pool is zero (to avoid divide by zero)
    (( (currentContract._batchesQueue.info.totalUnstETHIdsCount!= 0 && currentContract._accounting.stETHTotals.lockedShares!=0) ? (currentContract._accounting.stETHTotals.claimedETH * sumStETHLockedShares /currentContract._accounting.stETHTotals.lockedShares )  : 0 ) 
    // unstEth pool: the all claimed unsteth records minus those withdrawn already 
         +
        (sumClaimedUnSTEth - sumWithdrawnUnSTEth) 
        <=  nativeBalances[currentContract]  
    )
    && 
    (currentContract._batchesQueue.info.totalUnstETHIdsClaimed== 0 => currentContract._accounting.stETHTotals.claimedETH == 0) 

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
        requireInvariant solvency_stETH_before_rageQuit();
        validState(); 
    }
    preserved withdrawETH(uint256[] unstETHIds) with (env e) {
        require unstETHIds.length ==1; 
        require sumClaimedUnSTEth >= unstETHIds[0];
        require e.msg.sender != currentContract;
        requireInvariant solvency_stETH_before_rageQuit();
        validState(); 

    }
}

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
    ( getRageQuitExtensionDelayStartedAt() > 0  =>  
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




