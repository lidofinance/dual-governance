import "./Escrow.spec"; 

// Run link, all rules: https://prover.certora.com/output/65266/fa2f29f414dc406dbfa12b701504877a/?anonymousKey=53abc4581dceae209943d4aa1385ec79f8f26267
// Status, all rules: PASSING

/******         Ghost declaration       *****/ 


/**  @title Ghost sumStETHLockedShares is:
     sum of _accounting.assets[a].stETHLockedShares Escrow.SharesValue 
     for all addresses a
**/ 
ghost mathint sumStETHLockedShares {
    // assuming value zero at the initial state before constructor 
	init_state axiom sumStETHLockedShares == 0; 
}


/** @title Count how many IDs in each bathcIndex:
    numOfIdsInBatch[batchIndex] = _batchesQueue.batches[batchIndex].lastUnstETHId - batchesQueue.batches[batchIndex].firstUnstETHId +1
**/
ghost mapping(mathint => mathint)  numOfIdsInBatch {
    init_state axiom forall mathint x. numOfIdsInBatch[x] == 0;
} 

/** @title Accumulated count of batch id in all previous index
    countOFBatchIds[0] = 0; there is one that is just a start
  countOFBatchIds[x] = \count_{i=1}^{x-1} batch[x].last - batch[x].first + 1 ;
**/
ghost mapping(mathint => mathint)  countOFBatchIds {
    init_state axiom forall mathint x. countOFBatchIds[x] == 0;
} 
///@title a mirror for batchesQueue.batches[batchIndex].length
ghost uint256  ghostLengthMirror {
    init_state axiom ghostLengthMirror == 0;
}

///@title mirror claimableETH
ghost mapping(mathint => mathint) claimableETH {
    init_state axiom forall mathint x. claimableETH[x] == 0;
}

/** @title the partial sum of all unstethRecord that is claimed status >= 3 (claimed or withdrawn)
 this can increase when moving to state 3 
 i.e., partialSumOfClaimedUnstETH[id] == sum of _accounting.unstETHRecords[id'].claimableAmount
 where: id' <= id and id' is in state >= 3 
**/
ghost mapping(mathint => mathint)  partialSumOfClaimedUnstETH {
    init_state axiom forall mathint x. partialSumOfClaimedUnstETH[x] == 0;
}

/// @title the sum of all unstethRecord.claimableAmount in status >= 3 /* claimed or withdrawn */
ghost mathint sumClaimedUnSTEth {
    init_state axiom sumClaimedUnSTEth == 0; 
}
/// @title the sum of all unstethRecord.claimableAmount that was claimed and then withdrawn form escrow, status == 4 /* withdrawn */ 
ghost mathint sumWithdrawnUnSTEth {
    init_state axiom sumWithdrawnUnSTEth == 0; 
}
/** @title the partial sum of all unstethRecord that is claimed status >= 4 (withdrawn)
 this can increase when moving to state 4 
 i.e., partialSumOfWithdrawnUnstETH[id] == sum of _accounting.unstETHRecords[id'].claimableAmount
 where: id' <= id and id' is in state >= 4 
**/
ghost mapping(mathint => mathint)  partialSumOfWithdrawnUnstETH
 {
    init_state axiom forall mathint x. partialSumOfWithdrawnUnstETH[x] == 0;
} 

/******         Hooks for ghost updates       *****/ 

hook Sload uint256 length currentContract._batchesQueue.batches.length {
    require length == ghostLengthMirror;
}

hook Sstore  currentContract._batchesQueue.batches.length uint256 newLength {
    ghostLengthMirror = newLength;
}

/* updated sumStETHLockedShares according to the change of a single account */
hook Sstore currentContract._accounting.assets[KEY address a].stETHLockedShares Escrow.SharesValue new_balance
// the old value that balances[a] holds before the store
    (Escrow.SharesValue old_balance) {
  sumStETHLockedShares = sumStETHLockedShares + new_balance - old_balance;
}

/* assume a sum is ge it's element */ 
hook Sload Escrow.SharesValue value currentContract._accounting.assets[KEY address a].stETHLockedShares {
    require  value <= sumStETHLockedShares;
}

hook Sstore currentContract._batchesQueue.batches[INDEX uint256 batchIndex].firstUnstETHId uint256 newStart (uint256 oldStart) {
    // update numOFIdsInBatch for batchIndex
    mathint end = currentContract._batchesQueue.batches[batchIndex].lastUnstETHId;
    numOfIdsInBatch[batchIndex] = (batchIndex == 0 ? 0: end - newStart + 1);
    // update partial sums for x > to_mathint(batchIndex)
    countOFBatchIds[batchIndex+1] = countOFBatchIds[batchIndex]  + numOfIdsInBatch[batchIndex] ;
}

hook Sstore currentContract._batchesQueue.batches[INDEX uint256 batchIndex].lastUnstETHId uint256 newLastId (uint256 oldLastId) {
    mathint start = currentContract._batchesQueue.batches[batchIndex].firstUnstETHId;
    //require(numOfIdsInBatch[batchIndex] == (batchIndex == 0 ? 0: oldLastId - start + 1));
    numOfIdsInBatch[batchIndex] = (batchIndex == 0 ? 0: newLastId - start + 1);
    // update partial sums for x > to_mathint(batchIndex)
    countOFBatchIds[batchIndex+1] = countOFBatchIds[batchIndex]  + numOfIdsInBatch[batchIndex] ;
}

hook Sload uint256 end currentContract._batchesQueue.batches[INDEX uint256 batchIndex].lastUnstETHId {
    mathint start = currentContract._batchesQueue.batches[batchIndex].firstUnstETHId;
    require numOfIdsInBatch[batchIndex] ==  ((batchIndex == 0)? 0 :
                                            end - start +1 ); 
}

hook Sload uint256 start currentContract._batchesQueue.batches[INDEX uint256 batchIndex].firstUnstETHId {
    mathint end = currentContract._batchesQueue.batches[batchIndex].lastUnstETHId;
    require numOfIdsInBatch[batchIndex] ==  ((batchIndex == 0)? 0 :
                                            end - start +1 ); 
}


hook Sstore currentContract._accounting.unstETHRecords[KEY uint256 unstETHId].status Escrow.UnstETHRecordStatus new_status (Escrow.UnstETHRecordStatus old_status )
{
    // to claimed add to sumClaimedUnSTEth, note that it is also updated in the hook on  claimableAmount as order is not known 
  sumClaimedUnSTEth = sumClaimedUnSTEth + 
   ( (to_mathint(old_status) != 3  && to_mathint(new_status) == 3 ) ? currentContract._accounting.unstETHRecords[unstETHId].claimableAmount : 0 );

    // when chaning to state withrawn (state 4), claimableAmount must be already set, just update  sumWithdrawnUnSTEth
    sumWithdrawnUnSTEth = sumWithdrawnUnSTEth + 
   ( (to_mathint(old_status) != 4  && to_mathint(new_status) == 4 ) ? currentContract._accounting.unstETHRecords[unstETHId].claimableAmount : 0 );
    // update also partial sum of WithdrawanETH 
    if (to_mathint(old_status) == 3 && to_mathint(new_status) == 4) {
        havoc partialSumOfWithdrawnUnstETH assuming forall uint256 id. 
                (partialSumOfWithdrawnUnstETH@new[id] == partialSumOfWithdrawnUnstETH@old[id] +  ( id > unstETHId ? claimableETH[unstETHId] : 0));
    }

    // when claiming (state 3) update partialSumOfClaimedUnstETH for all indexes gt then  unstETHId
    if (to_mathint(old_status) != 3  && to_mathint(new_status) == 3 ) {
        havoc partialSumOfClaimedUnstETH assuming forall uint256 id. 
                (partialSumOfClaimedUnstETH@new[id] == partialSumOfClaimedUnstETH@old[id] +  ( id > unstETHId ?  claimableETH[unstETHId] : 0 ));
    }


}


hook Sstore currentContract._accounting.unstETHRecords[KEY uint256 unstETHId].claimableAmount Escrow.ETHValue new_claimableAmount (Escrow.ETHValue old_claimableAmount )
{
     if ( to_mathint(currentContract._accounting.unstETHRecords[unstETHId].status) == 3)  {
        havoc partialSumOfClaimedUnstETH assuming forall uint256 id. 
                (partialSumOfClaimedUnstETH@new[id] == partialSumOfClaimedUnstETH@old[id] +  ( id > unstETHId ? new_claimableAmount - old_claimableAmount : 0));
        sumClaimedUnSTEth = sumClaimedUnSTEth +  new_claimableAmount - old_claimableAmount ;
    }
    claimableETH[unstETHId] = new_claimableAmount;
}


hook Sload Escrow.ETHValue claimableAmount  currentContract._accounting.unstETHRecords[KEY uint256 unstETHId].claimableAmount 
{

    require claimableETH[unstETHId] == claimableAmount;
     if ( to_mathint(currentContract._accounting.unstETHRecords[unstETHId].status) >= 3)   {
        require forall uint256 id. (id > unstETHId) => partialSumOfClaimedUnstETH[id] >= claimableAmount;
        require claimableAmount <= sumClaimedUnSTEth;
     }
}

function getRageQuitExtensionPeriodStartedAt() returns uint40 {
    return currentContract._escrowState.rageQuitExtensionPeriodStartedAt;
}

/**
    @title CVL function to gather all valid state rules and a few other assumptions:
    1. the size of the batch queue is not close to max_uint
    2. lastRequestId zero is not valid 
**/
function validState() {
            // push is an unchecked operation, safely assume array will not overflow 
            require currentContract._batchesQueue.batches.length < 1000;
            require currentContract._batchesQueue.batches[0].lastUnstETHId < 1000000;
            require withdrawalQueue.lastRequestId < 100000000 &&  withdrawalQueue.lastRequestId > 0 ;
            requireInvariant validState_nonInitialized();
            requireInvariant validState_signalling();
            requireInvariant validState_rageQuit();
            uint256 any;
            requireInvariant validState_batchesQueue_monotonicity();
            requireInvariant validState_batchesQueue_withdrawalQueue();
            requireInvariant validState_totalLockedShares();
            requireInvariant validState_batchesQueue_distinct_unstETHRecords();
            requireInvariant validState_batchesQueue_ordering();
            validState_batchesQueue_claimed_vs_actual();
            requireInvariant validState_withdrawalQueue();
            requireInvariant validState_batchQueuesSum();
            requireInvariant validState_totalETHIds() ;
            requireInvariant validState_partialSumOfClaimedUnstETH();
            validState_partialSumMonotonicity();
            requireInvariant validState_claimedUnstEth();
            requireInvariant validState_withdrawnEth();
            requireInvariant valid_batchIndex();

            

    }

/** @title Current sum of all locked shares is le the total lockedShares 
    @notice lockedShares is the total and is not reduced on withdraw **/
invariant validState_totalLockedShares()
    sumStETHLockedShares <= currentContract._accounting.stETHTotals.lockedShares && sumStETHLockedShares >= 0 ;

/******         Escrow State Invariants       *****/ 


/// @title Before initialization everything is zero
invariant validState_nonInitialized() 
    ( isNotInitializedState() => (
                    isBatchQueueStateAbset() &&
                    currentContract._accounting.stETHTotals.claimedETH == 0 &&
                    getRageQuitExtensionPeriodStartedAt() == 0 &&
                    currentContract._batchesQueue.info.totalUnstETHIdsClaimed == 0 && 
                    currentContract._accounting.stETHTotals.lockedShares == 0 &&
                    sumClaimedUnSTEth == 0 &&
                    currentContract._batchesQueue.batches.length == 0
            ) 
    )
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            // push is an unchecked opetation, safely assume array will not overflow 
            require currentContract._batchesQueue.batches.length < max_uint256;
        }
    }

/// @title while in signaling no claims and no batch queues 
invariant validState_signalling() 
    // While in signaling state, no batch queues are open and no claim
    ( isSignallingState() =>  ( isBatchQueueStateAbset() &&
                    currentContract._accounting.stETHTotals.claimedETH == 0 &&
                    getRageQuitExtensionPeriodStartedAt() == 0 &&
                    currentContract._batchesQueue.info.totalUnstETHIdsClaimed == 0 && 
                    sumClaimedUnSTEth == 0 &&
                    currentContract._batchesQueue.batches.length == 0
        )
    ) 
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState();
        }
    }

/// @title Once rageQuit start, batch queues are either open or closed
invariant validState_rageQuit()     
    (isRageQuitState() <=> ( !isBatchQueueStateAbset() ) )
    && (isRageQuitState() <=> (currentContract._batchesQueue.batches.length >= 1 && currentContract._batchesQueue.batches[0].lastUnstETHId != 0))
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState();
        }
    }


/******         Batch Queue Invariants       *****/ 


/** @title Monotonicity of batch queues:
            1. In each entry, first id is le than the last id   
            2. Entry zero (if exist) has only one element
**/
invariant validState_batchesQueue_monotonicity( )  
    // each batch entry is monotonic, first <= last
    (forall uint256 h2. (h2 >=0 && h2 < currentContract._batchesQueue.batches.length) => (currentContract._batchesQueue.batches[h2].firstUnstETHId <=  currentContract._batchesQueue.batches[h2].lastUnstETHId) 
    ) && 
    ((currentContract._batchesQueue.batches.length > 0 ) => currentContract._batchesQueue.batches[0].firstUnstETHId == currentContract._batchesQueue.batches[0].lastUnstETHId)

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState();
        }
    }

/** @title Ordering of batch queues:
            The first id in each entry is greater than the last in the previous entry  
    @dev To help verification of other rules, we prove for next index and also for all indexes gt than the current one
**/
invariant validState_batchesQueue_ordering() 
    // monotonic, each batch is starting at a higher requestID than the previos one 
    (forall uint256 index. forall uint256 indexNext. (currentContract._batchesQueue.batches.length >= 1 && currentContract._batchesQueue.batches.length-1 >= indexNext  && to_mathint(indexNext) == index+1 ) =>
     (currentContract._batchesQueue.batches[indexNext].firstUnstETHId > currentContract._batchesQueue.batches[index].lastUnstETHId )       
    )
    &&
    (forall uint256 index. forall uint256 indexNext. (currentContract._batchesQueue.batches.length >= 1 && currentContract._batchesQueue.batches.length-1 >= indexNext  && indexNext > index ) =>
     (currentContract._batchesQueue.batches[indexNext].firstUnstETHId > currentContract._batchesQueue.batches[index].lastUnstETHId )       
    )
    
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState();
        }
    }

/** @title Validity of batch queue ids:
        1. The last id in the last entry is le than the lastRequestId in withdrawal queue  
        2. Escrow is the owner of the listed ids
    @notice Given the proof that all indexes are ordered, this implies that all ids are le lastRequestId
**/
invariant validState_batchesQueue_withdrawalQueue() 
    // last element is le  withdrawalQueue.lastRequestId 
    (currentContract._batchesQueue.batches.length >= 1 => currentContract._batchesQueue.batches[require_uint256(currentContract._batchesQueue.batches.length - 1)].lastUnstETHId <=  withdrawalQueue.lastRequestId) 
    && ( forall uint256 index. forall uint256 id. 
        (  ( index < ghostLengthMirror && index != 0 &&
            currentContract._batchesQueue.batches[index].firstUnstETHId <= id && currentContract._batchesQueue.batches[index].lastUnstETHId >= id  )) => withdrawalQueue.requests[id].owner == currentContract)
    && (forall address any. (!withdrawalQueue.allowance[currentContract][any])) 
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState(); 
        }
    }

/// @title all unstEth are less than the lastRequestId and first batch if exists
invariant validState_batchesQueue_distinct_unstETHRecords( )  
    forall uint256 id. ( 
        // if id is an unsetEth
        ( to_mathint(currentContract._accounting.unstETHRecords[id].status) != 0 => 
        // then id is a valid one in withdrawalQueue
        (id <= withdrawalQueue.lastRequestId && withdrawalQueue.requests[id].owner == currentContract )
        &&
        // and id is an unsetEth and there are batch queues
        ( ( to_mathint(currentContract._accounting.unstETHRecords[id].status) != 0 && 
        currentContract._batchesQueue.batches.length > 0 ) => 
        // then id has to be le than the batch queues ids (we check the first as the rest are monotonic increasing)
                id <= currentContract._batchesQueue.batches[0].firstUnstETHId ))) 

    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow 
            require e.msg.sender != currentContract;
            validState();
        }
    }

/** @title Valid state of withdrawalQueue:
    1. an id is claimed only if it a valid requestId and was finalized
    2. an id is finalized iff it is le lastFinalizedRequestId
    @dev This is only concerning withdrawlQueue but these properties are needed to prove properties of Escrow 
**/
invariant validState_withdrawalQueue() 
    (forall uint256 id. 
        ( (withdrawalQueue.requests[id].isClaimed)  => (
                        withdrawalQueue.requests[id].isFinalized &&  
                        id <= withdrawalQueue.lastRequestId 
                         )
        )
        && (id!=0 =>  (withdrawalQueue.requests[id].isFinalized <=> id <= withdrawalQueue.lastFinalizedRequestId))
    )
    && (withdrawalQueue.lastRequestId >=  withdrawalQueue.lastFinalizedRequestId) 
    && (!withdrawalQueue.requests[0].isClaimed && !withdrawalQueue.requests[0].isFinalized)
                        filtered { f ->  f.contract == withdrawalQueue} 
    
/// @title countOFBatchIds is as expected
 invariant validState_batchQueuesSum() 
    // batch index 0 is not relevant 
    countOFBatchIds[0] == 0 && numOfIdsInBatch[0] == 0 && countOFBatchIds[1] == 0 &&
    (forall uint256 index. (index > 0 && index < currentContract._batchesQueue.batches.length) =>  
                      (( numOfIdsInBatch[index] == currentContract._batchesQueue.batches[index].lastUnstETHId - currentContract._batchesQueue.batches[index].firstUnstETHId +1 ) && (numOfIdsInBatch[index] <= countOFBatchIds[index + 1]))
    )
    &&
    (forall uint256 index. (index > 0 && index <= currentContract._batchesQueue.batches.length) => 
                     countOFBatchIds[index] == countOFBatchIds[index-1] + numOfIdsInBatch[index-1] 
    )
    filtered { f ->  f.contract == currentContract} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState(); 
            
        }
    }

/** @title integrity of totalEthids:
        1. if lastClaimedBatchIndex is not zero, then totalUnstETHIdsClaimed is the count of all batch indexs calimed plus the number of ids claimed in the current batch
        2. if lastClaimedBatchIndex is zero, then claimed index is also zero and so it the total claimed ids
        3. totalUnstETHIdsCount is the total ids in all batch queues 
        4. total claimed le total ids 
*/
invariant validState_totalETHIds() 
   (( currentContract._batchesQueue.info.lastClaimedUnstETHIdIndex + countOFBatchIds[currentContract._batchesQueue.info.lastClaimedBatchIndex] + 1 == currentContract._batchesQueue.info.totalUnstETHIdsClaimed ) ||
   (currentContract._batchesQueue.info.lastClaimedBatchIndex == 0 ))
    &&
   (currentContract._batchesQueue.info.lastClaimedBatchIndex == 0 => 
        (   currentContract._batchesQueue.info.totalUnstETHIdsClaimed == 0 && 
            currentContract._batchesQueue.info.lastClaimedUnstETHIdIndex == 0))
    &&
    currentContract._batchesQueue.info.totalUnstETHIdsCount  == countOFBatchIds[currentContract._batchesQueue.batches.length]
    &&
    (currentContract._batchesQueue.info.totalUnstETHIdsClaimed== 0 => currentContract._accounting.stETHTotals.claimedETH == 0)
    && (currentContract._batchesQueue.info.totalUnstETHIdsClaimed <= currentContract._batchesQueue.info.totalUnstETHIdsCount) 
    
    filtered { f ->  f.contract == currentContract} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState(); 
        }
    }


/// @title Last claimed batch index is lt the length of batch queue, if exists 
invariant valid_batchIndex()
    ( currentContract._batchesQueue.info.lastClaimedBatchIndex < currentContract._batchesQueue.batches.length ||
        (currentContract._batchesQueue.info.lastClaimedBatchIndex==0 && currentContract._batchesQueue.batches.length==0 )
    )
    &&
    ( currentContract._batchesQueue.info.lastClaimedUnstETHIdIndex <= currentContract._batchesQueue.batches[currentContract._batchesQueue.info.lastClaimedBatchIndex].lastUnstETHId -   currentContract._batchesQueue.batches[currentContract._batchesQueue.info.lastClaimedBatchIndex].firstUnstETHId
    )
    && ghostLengthMirror == currentContract._batchesQueue.batches.length
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState(); 
        }
    }

/** @title If an id is within the claimed indexes than it is marked as claimed in the withdrawal queue
**/ 
invariant validState_batchesQueue_claimed_vs_actual_1(uint256 index, uint256 id)
    (       // if id is in one of the batch indexes 
            ( index < ghostLengthMirror && index != 0 &&
            currentContract._batchesQueue.batches[index].firstUnstETHId <= id && currentContract._batchesQueue.batches[index].lastUnstETHId >= id ) => 
            // then it is claimed iff the  lastClaimedBatchIndex , lastClaimedUnstETHIdIndex say so
            (
                // index is less than lastClaimedBatchIndex
                (  index  <  currentContract._batchesQueue.info.lastClaimedBatchIndex || 
                    ( index == currentContract._batchesQueue.info.lastClaimedBatchIndex &&  id <=  currentContract._batchesQueue.batches[index].firstUnstETHId + currentContract._batchesQueue.info.lastClaimedUnstETHIdIndex)
                ) 
                <=>  withdrawalQueue.requests[id].isClaimed
            )
    )
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState(); 
        }
    }
    
/** @dev since validState_batchesQueue_claimed_vs_actual_1 is proved for all index and for all id
we have a function that assume it for all values */
function validState_batchesQueue_claimed_vs_actual() {
    require ( forall uint256 index. forall uint256 id. 
        ( index < ghostLengthMirror && index != 0 &&
            currentContract._batchesQueue.batches[index].firstUnstETHId <= id && currentContract._batchesQueue.batches[index].lastUnstETHId >= id && withdrawalQueue.requests[id].isClaimed)
            =>
            ( index  <  currentContract._batchesQueue.info.lastClaimedBatchIndex || 
              ( index == currentContract._batchesQueue.info.lastClaimedBatchIndex &&  id <=  (currentContract._batchesQueue.batches[index].firstUnstETHId + currentContract._batchesQueue.info.lastClaimedUnstETHIdIndex) ) )
    )  
    &&
    ( forall uint256 index. forall uint256 id. 
        (  ( index < ghostLengthMirror && index != 0 &&
            currentContract._batchesQueue.batches[index].firstUnstETHId <= id && currentContract._batchesQueue.batches[index].lastUnstETHId >= id  && 
            (  index  <  currentContract._batchesQueue.info.lastClaimedBatchIndex || 
              ( index == currentContract._batchesQueue.info.lastClaimedBatchIndex &&  id <=  currentContract._batchesQueue.batches[index].firstUnstETHId + currentContract._batchesQueue.info.lastClaimedUnstETHIdIndex)) 
            )
         => withdrawalQueue.requests[id].isClaimed
         )
    );    
}

/** @title claimed unstETHRecords properties:
        1. if an unstETHRecord is finalized (status 2) then it is marked as finalized and not claimed in the withdrawal queue 
        2. if an unstETHRecord is claimed or withdrawn (status 3 or 4) then it is marked as finalized and claimed in the withdrawal queue 
**/
invariant validState_partialSumOfClaimedUnstETH() 
    // batch index 0 is not relevant 
    partialSumOfClaimedUnstETH[0] == 0 && claimableETH[0] == 0 && partialSumOfClaimedUnstETH[1] == 0 &&
    (
    forall uint256 id. (id > 0 && (to_mathint(currentContract._accounting.unstETHRecords[id].status) == 2)) => (withdrawalQueue.requests[id].isFinalized && !withdrawalQueue.requests[id].isClaimed)
    )
    &&
    (
    forall uint256 id. (id > 0 && (to_mathint(currentContract._accounting.unstETHRecords[id].status) == 3 || to_mathint(currentContract._accounting.unstETHRecords[id].status) == 4)) => (withdrawalQueue.requests[id].isClaimed && withdrawalQueue.requests[id].isFinalized)
    )
    filtered { f ->  f.contract == currentContract} {
        preserved with (env e) {
            // no dynamic call so Escrow
            require e.msg.sender != currentContract;
            validState(); 
            
        }
    }

/** @title partial sum of withdrawn is le partial sum of claimed, by at least the element that is claimed but not withdrawn 
    @notice proving on a single element
**/
invariant validState_partialSumMonotonicity_1(uint256 id) 
    partialSumOfWithdrawnUnstETH[require_uint256(id+1)]  + ( to_mathint(currentContract._accounting.unstETHRecords[id].status) == 3 ? currentContract._accounting.unstETHRecords[id].claimableAmount: 0 ) <= partialSumOfClaimedUnstETH[require_uint256(id+1)]
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
        validState(); 
    }
    preserved withdrawETH(uint256[] unstETHIds) with (env e) {
        require unstETHIds.length == 1;
        require unstETHIds[0] == id ||  unstETHIds[0] == require_uint256(id +1);
        require e.msg.sender != currentContract;
        validState(); 
    }

}

/** @title partial sum of two ids is as expected
**/
invariant validState_partialSumMonotonicity_2(uint256 id, uint256 id2) 
    id2 > id => (partialSumOfWithdrawnUnstETH[require_uint256(id2)]  +( to_mathint(currentContract._accounting.unstETHRecords[id].status) == 3 ? currentContract._accounting.unstETHRecords[id].claimableAmount: 0 ) <= partialSumOfClaimedUnstETH[require_uint256(id2)])
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
        validState(); 
    }
    preserved withdrawETH(uint256[] unstETHIds) with (env e) {
        require unstETHIds.length == 1;
        require unstETHIds[0] == id ;
        require e.msg.sender != currentContract;
        validState(); 
    }
}

/// @title a function for partialSumMonotonicity on all elements 
function validState_partialSumMonotonicity() {
    require ( forall uint256 id. forall uint256 idNext. ((idNext > id) =>  (partialSumOfWithdrawnUnstETH[idNext]  +( to_mathint(currentContract._accounting.unstETHRecords[id].status) == 3 ? currentContract._accounting.unstETHRecords[id].claimableAmount: 0 ) ) <= partialSumOfClaimedUnstETH[idNext]));
}

/// @title Total withdrawn unstEth is the partial sum of withdrawn of the  lastFinalizedRequestId+ 1
invariant validState_withdrawnEth() 
    (forall uint256 id. (id > withdrawalQueue.lastFinalizedRequestId) =>
        partialSumOfWithdrawnUnstETH[id] == sumWithdrawnUnSTEth )
    &&
    ( sumWithdrawnUnSTEth >= 0 &&  sumWithdrawnUnSTEth <= sumClaimedUnSTEth ) 
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
        // check requireInvariant solvency_stETH_before_ragequit();
        validState(); 
    }
    preserved withdrawETH(uint256[] unstETHIds) with (env e) {
        uint256 claimedId;
        require unstETHIds.length == 1;
        require unstETHIds[0] == claimedId ;
        // help grounding:
        requireInvariant validState_partialSumMonotonicity_1(claimedId);
        requireInvariant validState_partialSumMonotonicity_1(withdrawalQueue.lastFinalizedRequestId);

        require partialSumOfWithdrawnUnstETH[require_uint256(withdrawalQueue.lastFinalizedRequestId+1)]  +
            ( to_mathint(currentContract._accounting.unstETHRecords[claimedId].status) == 3 ? currentContract._accounting.unstETHRecords[claimedId].claimableAmount: 0 ) <= partialSumOfClaimedUnstETH[require_uint256(withdrawalQueue.lastFinalizedRequestId+1)];

        require withdrawalQueue.requests[claimedId].isFinalized <=> claimedId <= withdrawalQueue.lastFinalizedRequestId;

        require  (partialSumOfClaimedUnstETH[claimedId] <= sumClaimedUnSTEth);
        require  (partialSumOfClaimedUnstETH[claimedId+1] <= sumClaimedUnSTEth);
        require e.msg.sender != currentContract;
        validState(); 

}}

/// @title Total claimed unstEth is the partial sum of claimed of the  lastFinalizedRequestId+ 1
invariant validState_claimedUnstEth() 
    forall uint256 id. (id > withdrawalQueue.lastFinalizedRequestId) =>
        partialSumOfClaimedUnstETH[id] == sumClaimedUnSTEth 
    filtered { f ->  f.contract != stEth && f.contract != wst_eth} {
    preserved with (env e) {
        require e.msg.sender != currentContract;
        validState(); 
    }
}


/******        Helper Functions       *****/
    
/** @dev Use this function to get smaller counter examples, not needed for verification **/      
function assumingThreeOnly() {
    require currentContract._batchesQueue.batches.length <= 3;
    if (currentContract._batchesQueue.batches.length > 0) {
        require currentContract._batchesQueue.batches[0].firstUnstETHId == currentContract._batchesQueue.batches[0].lastUnstETHId &&
        currentContract._batchesQueue.batches[0].firstUnstETHId > 0;
    }
    if (currentContract._batchesQueue.batches.length > 1) {
        require currentContract._batchesQueue.batches[1].firstUnstETHId > currentContract._batchesQueue.batches[0].lastUnstETHId &&
            currentContract._batchesQueue.batches[1].firstUnstETHId <= currentContract._batchesQueue.batches[1].lastUnstETHId;
    }
    if (currentContract._batchesQueue.batches.length > 2) {
        require currentContract._batchesQueue.batches[2].firstUnstETHId > currentContract._batchesQueue.batches[1].lastUnstETHId &&
            currentContract._batchesQueue.batches[2].firstUnstETHId <= currentContract._batchesQueue.batches[2].lastUnstETHId;
    }
    // allow up to three unstEthIds
    uint256 i;
    uint256 j;
    uint256 k;
    require ( i > 0 && i < j && j < k && k <= withdrawalQueue.lastRequestId);
    require (currentContract._batchesQueue.batches.length > 0) => k <= currentContract._batchesQueue.batches[0].firstUnstETHId;  
    require ( forall uint256 any. (any != i && any != j && any != k ) =>
                to_mathint(currentContract._accounting.unstETHRecords[any].status) == 0 );
} 

