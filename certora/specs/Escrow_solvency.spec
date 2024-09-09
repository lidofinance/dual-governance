
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
        calimedETH * sumStETHLockedShares / stETHTotals.lockedShares 

        where sumStETHLockedShares is the current holding of shares 
    2. For the unstEth holding:
            sumClaimedUnSTEth - sumWithdrawnUnSTEth
        where:
            sumClaimedUnSTEth - total amount of all claimed unstEth 
            sumWithdrawnUnSTEth - total amount already withdrawn 

**/
invariant solvency_ETH() 
    // pool of batch queue
    (( (currentContract._batchesQueue.info.totalUnstETHIdsCount!= 0 && currentContract._accounting.stETHTotals.lockedShares!=0) ? (currentContract._accounting.stETHTotals.claimedETH * sumStETHLockedShares /currentContract._accounting.stETHTotals.lockedShares )  : 0 ) 
    // unstEth pool 
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




